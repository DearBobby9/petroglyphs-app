import Foundation

/// Keeps the paired URL as the durable conversation key. Only the authority of
/// an outgoing request changes, after a token-free proof from the same bridge.
actor BridgeTransport {
    typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    static let shared = BridgeTransport()
    static let failedNotification = Notification.Name("PetroglyphsBridgeConnectionFailed")
    private static let storageKey = "bridgeConnectionProfiles.v1"

    private struct CachedConnection { let snapshot: BridgeConnectionSnapshot; let checkedAt: Date }
    private let defaults: UserDefaults
    private let send: Send
    private var profiles: [String: BridgeConnectionMetadata]
    private var connections: [String: CachedConnection] = [:]
    private var failures: [String: BridgeConnectionFailure] = [:]
    private var attempts: [String: Task<BridgeConnectionSnapshot, Error>] = [:]

    init(defaults: UserDefaults = .standard, send: @escaping Send = { request in try await BridgeHTTPSession.data(for: request) }) {
        self.defaults = defaults
        self.send = send
        profiles = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([String: BridgeConnectionMetadata].self, from: $0) } ?? [:]
    }

    func data(for original: URLRequest) async throws -> (Data, URLResponse) {
        guard let url = original.url, let bridge = PairedBridge(url) else { return try await send(original) }
        let connection = try await connect(to: bridge.baseURL)
        var request = original
        request.url = try bridge.replacingOrigin(of: url, with: connection.origin)
        do {
            // Never retry a business request here. A POST timeout can mean that
            // Codex accepted it; existing receipt recovery retains its request ID.
            return try await send(request)
        } catch {
            if (error as? URLError)?.code != .cancelled,
               let current = connections[bridge.storageKey]?.snapshot,
               current.origin == connection.origin, current.generation == connection.generation {
                let failure = BridgeConnectionFailure(pairedKey: bridge.storageKey, origin: connection.origin, generation: connection.generation)
                connections[bridge.storageKey] = nil
                failures[bridge.storageKey] = failure
                NotificationCenter.default.post(name: Self.failedNotification, object: failure)
            }
            throw error
        }
    }

    func connect(to url: URL, force: Bool = false) async throws -> BridgeConnectionSnapshot {
        guard let bridge = PairedBridge(url) else {
            let health = try await Self.readHealth(base: url, send: send)
            return BridgeConnectionSnapshot(health: health, origin: PairedBridge.origin(url) ?? url, route: .direct,
                                            backupReady: false, automaticRecoveryReady: false)
        }
        let key = bridge.storageKey
        if !force, let cached = connections[key], Date().timeIntervalSince(cached.checkedAt) < 10 { return cached.snapshot }
        if let task = attempts[key] { return try await task.value }
        let profile = profiles[key]
        let active = connections[key]?.snapshot.origin
        let task = Task { try await Self.resolve(bridge: bridge, profile: profile, active: active, send: send) }
        attempts[key] = task
        do {
            let result = try await task.value
            attempts[key] = nil
            connections[key] = CachedConnection(snapshot: result, checkedAt: Date())
            failures[key] = nil
            if let metadata = result.health.bridge, result.automaticRecoveryReady {
                profiles[key] = metadata
                if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: Self.storageKey) }
            }
            return result
        } catch {
            attempts[key] = nil
            connections[key] = nil
            throw error
        }
    }

    func isCurrentFailure(_ failure: BridgeConnectionFailure) -> Bool {
        connections[failure.pairedKey] == nil && failures[failure.pairedKey] == failure
    }

    func forget(_ url: URL) {
        guard let bridge = PairedBridge(url) else { return }
        let key = bridge.storageKey
        attempts[key]?.cancel(); attempts[key] = nil
        connections[key] = nil; profiles[key] = nil; failures[key] = nil
        if let data = try? JSONEncoder().encode(profiles) { defaults.set(data, forKey: Self.storageKey) }
    }

    private static func resolve(bridge: PairedBridge, profile: BridgeConnectionMetadata?, active: URL?, send: @escaping Send) async throws -> BridgeConnectionSnapshot {
        let profile = profile?.id == bridge.identity && profile?.version == 1 ? profile : nil
        var local = (profile?.lanOrigins ?? []).filter { bridge.accepts($0, route: .local) }
        var tailscale = (profile?.tailscaleOrigins ?? []).filter { bridge.accepts($0, route: .tailscale) }
        if bridge.accepts(bridge.origin, route: .tailscale) { tailscale.append(bridge.origin) }
        else { local.append(bridge.origin) }
        local = unique(local)
        tailscale = unique(tailscale)
        if let active, let index = local.firstIndex(of: active) { local.remove(at: index); local.insert(active, at: 0) }

        // A LAN round has one bounded deadline, regardless of the number of old
        // DHCP candidates. Tailscale is only attempted after that round fails.
        for (candidates, route) in [(Array(local.prefix(6)), BridgeRoute.local), (Array(tailscale.prefix(2)), .tailscale)] {
            if let connected = await firstReachable(candidates, route: route, bridge: bridge, send: send) { return connected }
        }
        // A saved IP can now belong to another service. A missing identity
        // endpoint must never downgrade a paired URL to an unauthenticated send.
        throw URLError(.cannotConnectToHost)
    }

    private static func firstReachable(_ origins: [URL], route: BridgeRoute, bridge: PairedBridge, send: @escaping Send) async -> BridgeConnectionSnapshot? {
        await withTaskGroup(of: BridgeConnectionSnapshot?.self) { group in
            for origin in origins { group.addTask { try? await verify(origin: origin, route: route, bridge: bridge, send: send) } }
            for await result in group {
                if let result { group.cancelAll(); return result }
            }
            return nil
        }
    }

    private static func verify(origin: URL, route: BridgeRoute, bridge: PairedBridge, send: @escaping Send) async throws -> BridgeConnectionSnapshot {
        let nonce = nonce()
        let (data, response) = try await send(identityRequest(origin: origin, nonce: nonce))
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 2048 else { throw URLError(.userAuthenticationRequired) }
        let proof = try JSONDecoder().decode(IdentityProof.self, from: data)
        let message = "petroglyphs-bridge-proof-v1\n\(nonce)\n\(origin.absoluteString)\n\(bridge.identity)"
        guard proof.id == bridge.identity, proof.nonce == nonce, proof.origin == origin.absoluteString,
              proof.proof == bridge.hmac(message) else { throw URLError(.userAuthenticationRequired) }
        try Task.checkCancellation()
        let base = try bridge.replacingOrigin(of: bridge.baseURL, with: origin)
        let health = try await readHealth(base: base, send: send)
        guard let metadata = health.bridge, metadata.id == bridge.identity, metadata.version == 1 else { throw URLError(.userAuthenticationRequired) }
        let filtered = BridgeConnectionMetadata(version: 1, id: metadata.id,
            lanOrigins: Array(metadata.lanOrigins.filter { bridge.accepts($0, route: .local) }.prefix(5)),
            tailscaleOrigins: Array(metadata.tailscaleOrigins.filter { bridge.accepts($0, route: .tailscale) }.prefix(2)))
        return BridgeConnectionSnapshot(health: HealthResponse(status: health.status, version: health.version,
            submissions: health.submissions, autoReply: health.autoReply, bridge: filtered), origin: origin, route: route,
            backupReady: !filtered.tailscaleOrigins.isEmpty, automaticRecoveryReady: true)
    }

    private static func readHealth(base: URL, send: Send) async throws -> HealthResponse {
        let request = URLRequest(url: base.appendingPathComponent("api/health"), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 3)
        let (data, response) = try await send(request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 64 * 1024 else { throw URLError(.badServerResponse) }
        let health = try JSONDecoder().decode(HealthResponse.self, from: data)
        guard health.status == "ok" else { throw URLError(.badServerResponse) }
        return health
    }

    private static func identityRequest(origin: URL, nonce: String) -> URLRequest {
        var parts = URLComponents(url: origin.appendingPathComponent("api/bridge/identity"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "nonce", value: nonce), URLQueryItem(name: "origin", value: origin.absoluteString)]
        return URLRequest(url: parts.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2)
    }

    private static func nonce() -> String { UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() + UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() }
    private static func unique(_ urls: [URL]) -> [URL] { var seen = Set<URL>(); return urls.filter { seen.insert($0).inserted } }
    private struct IdentityProof: Decodable { let id: String; let nonce: String; let origin: String; let proof: String }
}

private final class BridgeHTTPSession: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    static let shared = BridgeHTTPSession()
    private var session: URLSession!
    override init() {
        super.init()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }

    static func data(for request: URLRequest) async throws -> (Data, URLResponse) { try await shared.session.data(for: request) }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        // Neither a discovery probe nor a bearer-bearing URL may follow an
        // unverified redirect to another host or path.
        completionHandler(nil)
    }
}
