import XCTest

final class BridgeTransportTests: XCTestCase {
    private let old = URL(string: "http://192.168.1.10:3333")!
    private let stable = URL(string: "http://paired-mac.local:3333")!
    private let tail = URL(string: "http://100.64.0.10:3333")!
    private var suite: String!
    private var defaults: UserDefaults!
    private var paired: URL { old.appendingPathComponent("device/" + String(repeating: "a", count: 32)) }

    override func setUp() {
        suite = "PetroglyphsReconnectTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() { defaults.removePersistentDomain(forName: suite) }

    func testWirelessPairingLearnsRouteWithoutForkingSavedChatIdentity() async throws {
        let bridge = PairedBridge(paired)!
        let fixture = BridgeFixture(bridge: bridge, lan: [stable], tail: [tail])
        await fixture.setReachable([tail])
        let transport = BridgeTransport(defaults: defaults, send: { try await fixture.send($0) })
        try await transport.learn(origin: tail, for: paired)
        let request = URLRequest(url: paired.appendingPathComponent("api/codex/conversation"))
        _ = try await transport.data(for: request)
        let calls = await fixture.requests()
        XCTAssertEqual(calls.last?.url?.host, tail.host)
        XCTAssertEqual(calls.last?.url?.path, request.url?.path)
        XCTAssertEqual(PairedBridge(paired)?.storageKey, bridge.storageKey)
        let restarted = BridgeTransport(defaults: defaults, send: { try await fixture.send($0) })
        let recovered = try await restarted.connect(to: paired)
        XCTAssertEqual(recovered.origin, tail)
    }

    func testMagicDNSRouteRequiresTheSameBridgeIdentityBeforeSendingCredentials() async throws {
        let dns = URL(string: "http://fixture-mac.tail-example.ts.net:3333")!
        let bridge = PairedBridge(paired)!
        let fixture = BridgeFixture(bridge: bridge, lan: [], tail: [dns])
        await fixture.setReachable([dns])
        let transport = BridgeTransport(defaults: defaults, send: { try await fixture.send($0) })
        try await transport.learn(origin: dns, for: paired)
        _ = try await transport.data(for: URLRequest(url: paired.appendingPathComponent("api/codex/conversation")))
        let calls = await fixture.requests()
        XCTAssertEqual(calls.last?.url?.host, dns.host)
        XCTAssertEqual(PairedBridge(paired)?.storageKey, bridge.storageKey)
        await fixture.setInvalidProof("signature")
        let rejected = BridgeTransport(defaults: defaults, send: { try await fixture.send($0) })
        let before = await fixture.requests().count
        do { try await rejected.learn(origin: dns, for: paired); XCTFail("Accepted an unverified DNS route") } catch {}
        let newCalls = await fixture.requests().dropFirst(before)
        XCTAssertFalse(newCalls.contains { $0.url?.path.contains("/device/") == true })
    }

    func testPairedHealthPreservesModernCapabilitiesAndLegacyFallback() async throws {
        let fixture = BridgeFixture(bridge: PairedBridge(paired)!, lan: [stable], tail: [])
        let transport = BridgeTransport(defaults: defaults, send: { try await fixture.send($0) })
        await fixture.setHealth(autoReply: false, capabilities: .init(conversations: true, projects: true, controls: true))
        let modern = try await transport.connect(to: paired)
        XCTAssertTrue(modern.health.supportsCodexConversations)
        XCTAssertEqual(modern.health.capabilities?.projects, true)
        XCTAssertEqual(modern.health.capabilities?.controls, true)
        await fixture.setHealth(autoReply: true, capabilities: .init(conversations: false, projects: false, controls: false))
        let disabled = try await transport.connect(to: paired, force: true)
        XCTAssertFalse(disabled.health.supportsCodexConversations, "Explicit capabilities take precedence over the legacy worker")
        await fixture.setHealth(autoReply: true, capabilities: nil)
        let legacy = try await transport.connect(to: paired, force: true)
        XCTAssertTrue(legacy.health.supportsCodexConversations)
    }

    func testExpiredIPUsesPersistedHostnameWithoutChangingChatOrReceiptIdentity() async throws {
        let bridge = PairedBridge(paired)!
        let fixture = BridgeFixture(bridge: bridge, lan: [stable, old], tail: [tail])
        var transport = BridgeTransport(defaults: defaults, send: { try await fixture.send($0) })
        _ = try await transport.connect(to: paired)
        await fixture.setReachable([stable])
        // Simulates app restart after DHCP changes, retaining only authenticated metadata.
        transport = BridgeTransport(defaults: defaults, send: { try await fixture.send($0) })
        let original = paired.appendingPathComponent("api/codex/messages/receipt-id").absoluteString
            + "?hostId=remote-control%3Amini&threadId=existing-thread"
        let request = URLRequest(url: URL(string: original)!)
        _ = try await transport.data(for: request)
        let calls = await fixture.requests()
        let actual = try XCTUnwrap(calls.last { $0.url?.path.hasSuffix("messages/receipt-id") == true })
        XCTAssertEqual(actual.url?.host, stable.host)
        XCTAssertEqual(actual.url?.path, request.url?.path)
        XCTAssertEqual(actual.url?.query, request.url?.query)
        XCTAssertEqual(request.url?.absoluteString, original)
        XCTAssertEqual(PairedBridge(paired)?.storageKey, bridge.storageKey)
    }

    func testLocalFailureFallsBackAndNextRefreshReturnsToLocal() async throws {
        let fixture = BridgeFixture(bridge: PairedBridge(paired)!, lan: [stable, old], tail: [tail])
        let transport = BridgeTransport(defaults: defaults, send: { try await fixture.send($0) })
        let first = try await transport.connect(to: paired)
        XCTAssertEqual(first.route, .local)
        XCTAssertTrue(first.backupReady)
        let initial = await fixture.requests()
        XCTAssertFalse(initial.contains { $0.url?.host == tail.host }, "backup is not probed while LAN works")
        let newLAN = URL(string: "http://192.168.1.20:3333")!
        await fixture.setLAN([stable, newLAN])
        await fixture.setReachable([tail])
        let backup = try await transport.connect(to: paired, force: true)
        XCTAssertEqual(backup.route, .tailscale)
        XCTAssertTrue(backup.health.bridge?.lanOrigins.contains(newLAN) == true)
        await fixture.setReachable([newLAN, tail])
        let restored = try await transport.connect(to: paired, force: true)
        XCTAssertEqual(restored.route, .local)
        XCTAssertEqual(restored.origin, newLAN, "learns the changed LAN address through the Tailscale health response")
    }

    func testInvalidNonceOriginSignatureAndRedirectNeverReceivePairedURL() async throws {
        for invalid in ["nonce", "origin", "signature", "redirect"] {
            let fixture = BridgeFixture(bridge: PairedBridge(paired)!, lan: [stable], tail: [])
            await fixture.setInvalidProof(invalid)
            let transport = BridgeTransport(defaults: defaults, send: { try await fixture.send($0) })
            do { _ = try await transport.connect(to: paired); XCTFail("accepted \(invalid)") } catch {}
            let requests = await fixture.requests()
            XCTAssertFalse(requests.contains { $0.url?.path.contains("/device/") == true }, "sent credentials after \(invalid)")
        }
    }

    func testAmbiguousPostIsNotReplayedWhenTheRouteChanges() async throws {
        let fixture = BridgeFixture(bridge: PairedBridge(paired)!, lan: [stable, old], tail: [tail])
        let transport = BridgeTransport(defaults: defaults, send: { try await fixture.send($0) })
        _ = try await transport.connect(to: paired)
        await fixture.setFailPost(true)
        var request = URLRequest(url: paired.appendingPathComponent("api/codex/chats"))
        request.httpMethod = "POST"
        request.httpBody = Data(#"{"id":"fixed-request-id","hostId":"remote-control:mini","projectId":"fixed-project","prompt":"test"}"#.utf8)
        do { _ = try await transport.data(for: request); XCTFail("expected ambiguous timeout") } catch {}
        await fixture.setReachable([tail])
        _ = try await transport.data(for: URLRequest(url: paired.appendingPathComponent("api/codex/chats/fixed-request-id")))
        let posts = await fixture.requests().filter { $0.httpMethod == "POST" }
        XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(posts.first?.httpBody, request.httpBody)
    }

    func testMissingIdentityNeverReceivesTheTokenOrBusinessPost() async throws {
        let fixture = BridgeFixture(bridge: PairedBridge(paired)!, lan: [old], tail: [])
        await fixture.setInvalidProof("notFound")
        let transport = BridgeTransport(defaults: defaults, send: { try await fixture.send($0) })
        var request = URLRequest(url: paired.appendingPathComponent("api/codex/chats"))
        request.httpMethod = "POST"
        request.httpBody = Data("private content".utf8)
        do { _ = try await transport.data(for: request); XCTFail("accepted an unverified paired endpoint") } catch {}
        let requests = await fixture.requests()
        XCTAssertFalse(requests.contains { $0.url?.path.contains("/device/") == true })
        XCTAssertFalse(requests.contains { $0.httpMethod == "POST" })

        // A deliberately non-paired server continues to use its explicit URL.
        var unpaired = URLRequest(url: old.appendingPathComponent("api/submit"))
        unpaired.httpMethod = "POST"
        _ = try await transport.data(for: unpaired)
        let directRequests = await fixture.requests()
        XCTAssertEqual(directRequests.last?.url, unpaired.url)
    }

    func testLateRequestFailureCannotInvalidateANewerRouteOrGeneration() async throws {
        for nextOrigin in [tail, old] {
            let fixture = BridgeFixture(bridge: PairedBridge(paired)!, lan: [old], tail: [tail])
            let transport = BridgeTransport(defaults: defaults, send: { try await fixture.send($0) })
            _ = try await transport.connect(to: paired)
            let notifications = FailureNotifications()
            let observer = NotificationCenter.default.addObserver(forName: BridgeTransport.failedNotification, object: nil, queue: nil) { _ in notifications.record() }
            defer { NotificationCenter.default.removeObserver(observer) }
            await fixture.holdNextBusinessRequest()
            let pending = Task { try await transport.data(for: URLRequest(url: paired.appendingPathComponent("api/codex/conversation"))) }
            await fixture.waitForHeldBusinessRequest()
            await fixture.setReachable([nextOrigin])
            let current = try await transport.connect(to: paired, force: true)
            XCTAssertEqual(current.origin, nextOrigin)
            await fixture.failHeldBusinessRequest()
            do { _ = try await pending.value; XCTFail("expected the old request timeout") } catch {}
            XCTAssertEqual(notifications.count, 0, "a late old request must not disconnect a newer route, including the same origin")
        }
    }

    func testCurrentFailureIsScopedAndExpiresAfterANewVerification() async throws {
        let fixture = BridgeFixture(bridge: PairedBridge(paired)!, lan: [old], tail: [])
        let transport = BridgeTransport(defaults: defaults, send: { try await fixture.send($0) })
        let current = try await transport.connect(to: paired)
        let notifications = FailureNotifications()
        let observer = NotificationCenter.default.addObserver(forName: BridgeTransport.failedNotification, object: nil, queue: nil) { notifications.record($0) }
        defer { NotificationCenter.default.removeObserver(observer) }
        await fixture.setFailPost(true)
        var request = URLRequest(url: paired.appendingPathComponent("api/codex/messages"))
        request.httpMethod = "POST"
        do { _ = try await transport.data(for: request); XCTFail("expected timeout") } catch {}
        let failure = try XCTUnwrap(notifications.latest)
        XCTAssertEqual(failure.pairedKey, PairedBridge(paired)?.storageKey)
        XCTAssertEqual(failure.origin, current.origin)
        XCTAssertEqual(failure.generation, current.generation)
        let valid = await transport.isCurrentFailure(failure)
        XCTAssertTrue(valid)
        _ = try await transport.connect(to: paired, force: true)
        let stale = await transport.isCurrentFailure(failure)
        XCTAssertFalse(stale, "a delayed observer must reject an event after successful verification")
    }

    func testUntrustedMetadataCannotIntroduceArbitraryCredentialDestinations() async throws {
        let bridge = PairedBridge(paired)!
        let invalid = ["http://evil.example:3333", "http://user@paired-mac.local:3333", "http://paired-mac.local:4000", "http://paired-mac.local:3333/path", "http://paired-mac.local:3333?q=1", "https://paired-mac.local:3333", "http://127.0.0.1:3333"]
        let fixture = BridgeFixture(bridge: bridge, lan: [stable] + invalid.map { URL(string: $0)! }, tail: [URL(string: "http://8.8.8.8:3333")!, tail])
        let transport = BridgeTransport(defaults: defaults, send: { try await fixture.send($0) })
        let result = try await transport.connect(to: paired)
        XCTAssertEqual(result.health.bridge?.lanOrigins, [stable])
        XCTAssertEqual(result.health.bridge?.tailscaleOrigins, [tail])
        await fixture.setReachable([tail])
        _ = try await transport.connect(to: paired, force: true)
        let calls = await fixture.requests()
        XCTAssertFalse(calls.contains { request in invalid.contains { request.url?.absoluteString.hasPrefix($0) == true } })
    }
}

private actor BridgeFixture {
    let bridge: PairedBridge
    var metadata: BridgeConnectionMetadata
    var reachable: Set<URL>
    var invalidProof: String?
    var failPost = false
    var autoReplyEnabled = true
    var capabilities: HealthResponse.Capabilities?
    var calls: [URLRequest] = []
    var holdBusiness = false
    var heldBusiness: CheckedContinuation<(Data, URLResponse), Error>?
    var heldWaiters: [CheckedContinuation<Void, Never>] = []

    init(bridge: PairedBridge, lan: [URL], tail: [URL]) {
        self.bridge = bridge
        metadata = BridgeConnectionMetadata(version: 1, id: bridge.identity, lanOrigins: lan, tailscaleOrigins: tail)
        reachable = Set(lan + tail + [bridge.origin])
    }
    func setReachable(_ origins: [URL]) { reachable = Set(origins) }
    func setLAN(_ origins: [URL]) { metadata = BridgeConnectionMetadata(version: 1, id: metadata.id, lanOrigins: origins, tailscaleOrigins: metadata.tailscaleOrigins) }
    func setInvalidProof(_ value: String) { invalidProof = value }
    func setFailPost(_ value: Bool) { failPost = value }
    func setHealth(autoReply: Bool, capabilities: HealthResponse.Capabilities?) {
        autoReplyEnabled = autoReply
        self.capabilities = capabilities
    }
    func requests() -> [URLRequest] { calls }
    func holdNextBusinessRequest() { holdBusiness = true }
    func waitForHeldBusinessRequest() async {
        if heldBusiness != nil { return }
        await withCheckedContinuation { heldWaiters.append($0) }
    }
    func failHeldBusinessRequest() {
        let held = heldBusiness
        heldBusiness = nil
        held?.resume(throwing: URLError(.timedOut))
    }

    func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        calls.append(request)
        let url = request.url!
        guard let origin = PairedBridge.origin(url), reachable.contains(origin) else { throw URLError(.cannotConnectToHost) }
        if url.path == "/api/bridge/identity" {
            if invalidProof == "notFound" { return response(url, status: 404, data: Data()) }
            if invalidProof == "redirect" { return response(url, status: 302, data: Data()) }
            let fields = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
            let nonce = fields.first { $0.name == "nonce" }!.value!
            let proofOrigin = fields.first { $0.name == "origin" }!.value!
            let proof = bridge.hmac("petroglyphs-bridge-proof-v1\n\(nonce)\n\(proofOrigin)\n\(bridge.identity)")
            let data = try JSONSerialization.data(withJSONObject: ["id": bridge.identity,
                "nonce": invalidProof == "nonce" ? "old-nonce" : nonce,
                "origin": invalidProof == "origin" ? "http://other.local:3333" : proofOrigin,
                "proof": invalidProof == "signature" ? "forged" : proof])
            return response(url, data: data)
        }
        if url.path.hasSuffix("/api/health") {
            return response(url, data: try JSONEncoder().encode(HealthResponse(status: "ok", version: "test", submissions: 0,
                autoReply: .init(enabled: autoReplyEnabled), capabilities: capabilities, bridge: metadata)))
        }
        if request.httpMethod == "POST", failPost { throw URLError(.timedOut) }
        if holdBusiness {
            holdBusiness = false
            return try await withCheckedThrowingContinuation { continuation in
                heldBusiness = continuation
                let waiters = heldWaiters
                heldWaiters = []
                waiters.forEach { $0.resume() }
            }
        }
        return response(url, data: Data("{}".utf8))
    }

    private func response(_ url: URL, status: Int = 200, data: Data) -> (Data, URLResponse) {
        (data, HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: [:])!)
    }
}

private final class FailureNotifications: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded = 0
    private var lastFailure: BridgeConnectionFailure?
    func record(_ notification: Notification? = nil) {
        lock.withLock {
            recorded += 1
            lastFailure = notification?.object as? BridgeConnectionFailure
        }
    }
    var count: Int { lock.withLock { recorded } }
    var latest: BridgeConnectionFailure? { lock.withLock { lastFailure } }
}
