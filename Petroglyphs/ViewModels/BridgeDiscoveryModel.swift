import Foundation
import UIKit

@Observable
@MainActor
final class BridgeDiscoveryModel: NSObject, @preconcurrency NetServiceBrowserDelegate, @preconcurrency NetServiceDelegate {
    private(set) var bridges: [DiscoveredBridge] = []
    private(set) var isSearching = false
    private(set) var discoveryStatus = "Looking for Mac bridges…"
    private(set) var pairingBridge: DiscoveredBridge?
    private(set) var pairingCode: String?
    private(set) var pairingStatus: String?
    private(set) var pairedURL: URL?
    private(set) var pairedName: String?
    private(set) var error: String?
    private(set) var connectionRevision = 0

    @ObservationIgnored private let client: BridgeDiscoveryClient
    private var savedBridges: SavedBridgeRegistry
    @ObservationIgnored private let transport: BridgeTransport
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var browser: NetServiceBrowser?
    @ObservationIgnored private var services: [NetService] = []
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var probeTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var pairingTask: Task<Void, Never>?
    @ObservationIgnored private var challenge: WirelessPairingChallenge?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var active = false
    @ObservationIgnored private var seeds: [URL]
    @ObservationIgnored private var found: [String: (DiscoveredBridge, Date)] = [:]

    init(client: BridgeDiscoveryClient = BridgeDiscoveryClient(), seeds: [URL]? = nil, defaults: UserDefaults = .standard, transport: BridgeTransport = .shared) {
        self.client = client
        self.defaults = defaults
        self.transport = transport
        self.savedBridges = SavedBridgeRegistry(defaults: defaults)
        self.seeds = seeds ?? (Bundle.main.object(forInfoDictionaryKey: "PetroglyphsDiscoveryOrigins") as? [String] ?? [])
            .compactMap(URL.init(string:)).filter(DiscoveredBridge.allowedOrigin)
        super.init()
    }

    func setForeground(_ foreground: Bool) {
        guard foreground != active else { return }
        active = foreground
        if foreground {
            let browser = NetServiceBrowser()
            browser.delegate = self
            // Foundation delegates use the scheduled run loop. Keep callbacks
            // on the same main actor that owns discovery and pairing state.
            browser.schedule(in: .main, forMode: .common)
            self.browser = browser
            browser.searchForServices(ofType: "_petroglyphs._tcp.", inDomain: "local.")
            refreshTask = Task { [weak self] in
                while !Task.isCancelled {
                    guard let self else { return }
                    await self.refresh()
                    try? await Task.sleep(for: .seconds(20))
                }
            }
        } else {
            browser?.stop(); browser = nil
            services.forEach { $0.stop() }; services = []
            refreshTask?.cancel(); refreshTask = nil
            probeTasks.forEach { $0.cancel() }; probeTasks = []
            isSearching = false
        }
    }

    func refresh() async {
        guard !isSearching else { return }
        isSearching = true
        defer { isSearching = false }
        var origins = seeds + savedBridges.bridges.compactMap { PairedBridge($0.durableURL)?.origin }
        origins += (defaults.stringArray(forKey: "bridgeDiscoveryOrigins.v1") ?? []).compactMap(URL.init(string:))
        if let saved = defaults.string(forKey: "serverURLString"), let url = URL(string: saved), let paired = PairedBridge(url) {
            origins.append(paired.origin)
        }
        var seen = Set<URL>()
        origins = origins.filter { DiscoveredBridge.allowedOrigin($0) && seen.insert($0).inserted }
        var tailnetReached = false
        await withTaskGroup(of: (URL, BridgeDiscoveryResponse?).self) { group in
            for origin in origins.prefix(4) { group.addTask { [client] in (origin, try? await client.discover(at: origin)) } }
            for await (origin, response) in group {
                guard !Task.isCancelled, let response else { continue }
                // A Mac can report a running daemon while this iPad only reached
                // it over LAN. Show the route this discovery request actually used.
                tailnetReached = tailnetReached || (origin.host.map(PairedBridge.isTailscaleHost) == true && response.tailscale.state == "running")
                for bridge in [response.bridge] + response.bridges { merge(bridge) }
            }
        }
        prune()
        if tailnetReached { discoveryStatus = "Tailscale directory reachable · \(bridges.count) Mac bridge(s)" }
        else if !bridges.isEmpty { discoveryStatus = "Nearby Mac bridges found · Tailscale directory unavailable" }
        else if seeds.isEmpty { discoveryStatus = "Searching nearby. This installation has no Tailscale discovery entry." }
        else { discoveryStatus = "No Mac reached. Connect Tailscale on both devices and keep the Mac bridge running." }
    }

    func pair(with bridge: DiscoveredBridge) {
        guard bridge.isValid else { return }
        if isPaired(bridge) {
            Task { await connect(to: bridge) }
            return
        }
        guard pairingTask == nil else { return }
        generation = UUID()
        let generation = generation
        pairingBridge = bridge; pairingCode = nil; error = nil
        pairingStatus = "Requesting approval on \(bridge.name)…"
        pairingTask = Task { [weak self] in
            guard let self else { return }
            let key = WirelessPairingKey()
            do {
                let challenge = try await client.begin(bridge: bridge, clientName: UIDevice.current.name, key: key)
                guard self.generation == generation, !Task.isCancelled else {
                    await client.cancel(bridge: bridge, challenge: challenge); return
                }
                self.challenge = challenge
                _ = try key.verifiedKey(challenge)
                pairingCode = challenge.code
                pairingStatus = "Compare this code with the Mac approval window, then choose Allow on the Mac."
                let deadline = Date().addingTimeInterval(300)
                while Date() < deadline {
                    try await Task.sleep(for: .seconds(2))
                    try Task.checkCancellation()
                    let result: WirelessPairingPoll
                    do {
                        result = try await client.poll(bridge: bridge, challenge: challenge)
                    } catch {
                        try Task.checkCancellation()
                        pairingStatus = "Waiting for the Mac connection. Keep Tailscale connected, or cancel pairing."
                        continue
                    }
                    guard self.generation == generation else { return }
                    switch result.state {
                    case "pending":
                        pairingStatus = "Compare this code with the Mac approval window, then choose Allow on the Mac."
                        continue
                    case "approved":
                        guard let envelope = result.encrypted else { throw URLError(.cannotParseResponse) }
                        let credentials = try key.decrypt(envelope, challenge: challenge, bridge: bridge)
                        pairingStatus = "Mac approved. Verifying the connection…"
                        try await completePairing(credentials, origin: bridge.origin, generation: generation)
                        return
                    case "rejected": throw PairingError.rejected
                    case "expired": throw PairingError.expired
                    default: throw URLError(.cannotParseResponse)
                    }
                }
                throw PairingError.expired
            } catch {
                guard self.generation == generation, !Task.isCancelled else { return }
                if let challenge = self.challenge { await client.cancel(bridge: bridge, challenge: challenge) }
                guard self.generation == generation, !Task.isCancelled else { return }
                if let failure = error as? BridgePairingFailure {
                    self.error = failure.message
                } else if let failure = error as? URLError {
                    self.error = "Pairing connection failed (\(failure.code.rawValue)). Check Tailscale and the Mac approval window, then try again."
                } else {
                    self.error = (error as? PairingError)?.message ?? "The Mac returned an invalid pairing response. Refresh discovery and try again."
                }
                pairingStatus = nil; pairingTask = nil; pairingCode = nil; self.challenge = nil
            }
        }
    }

    func cancelPairing() {
        generation = UUID()
        pairingTask?.cancel(); pairingTask = nil
        if let bridge = pairingBridge, let challenge {
            Task { [client] in await client.cancel(bridge: bridge, challenge: challenge) }
        }
        challenge = nil; pairingBridge = nil; pairingCode = nil; pairingStatus = nil; error = nil
    }

    private func completePairing(_ credentials: WirelessPairingCredentials, origin: URL, generation: UUID) async throws {
        let durableURL = savedBridges[credentials.bridgeId]?.durableURL ?? credentials.baseURL
        try await transport.learn(origin: origin, for: durableURL)
        guard self.generation == generation, !Task.isCancelled else { return }
        commitConnection(url: durableURL, name: credentials.name)
    }

    func isPaired(_ bridge: DiscoveredBridge) -> Bool { savedBridges[bridge.id] != nil }

    func connect(to bridge: DiscoveredBridge) async {
        guard bridge.isValid, let saved = savedBridges[bridge.id] else { return }
        cancelPairing()
        let generation = generation
        pairingBridge = bridge
        pairingStatus = "Verifying \(bridge.name)…"
        do {
            try await transport.learn(origin: bridge.origin, for: saved.durableURL)
            guard self.generation == generation, !Task.isCancelled else { return }
            commitConnection(url: saved.durableURL, name: bridge.name)
        } catch {
            guard self.generation == generation, !Task.isCancelled else { return }
            self.error = "Could not verify \(bridge.name). The previous Mac connection is unchanged. Refresh discovery and try again."
            pairingBridge = nil; pairingStatus = nil
        }
    }

    private func commitConnection(url durableURL: URL, name: String) {
        savedBridges.remember(url: durableURL, name: name)
        defaults.set(durableURL.absoluteString, forKey: "localURLString")
        defaults.set(durableURL.absoluteString, forKey: "serverURLString")
        defaults.set("local", forKey: "connectionMode")
        defaults.set("", forKey: "pairingCode")
        defaults.set(name, forKey: "pairedBridgeName")
        pairedURL = durableURL; pairedName = name
        pairingStatus = "Connected to \(name)"
        pairingTask = nil; pairingBridge = nil; pairingCode = nil; challenge = nil
        connectionRevision += 1
    }

    private func merge(_ bridge: DiscoveredBridge) {
        guard bridge.isValid else { return }
        // Prefer a Tailscale origin for the wireless pairing handshake.
        if let old = found[bridge.id], old.0.route == .tailscale, bridge.route != .tailscale { return }
        found[bridge.id] = (bridge, Date())
        prune()
        defaults.set(Array(bridges.filter { $0.route == .tailscale }.map { $0.origin.absoluteString }.prefix(4)), forKey: "bridgeDiscoveryOrigins.v1")
    }

    private func prune() {
        found = found.filter { Date().timeIntervalSince($0.value.1) < 65 }
        bridges = Array(found.values.map(\.0).sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.prefix(33))
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didFind service: NetService, moreComing: Bool) {
        guard active, services.count < 32 else { return }
        services.append(service); service.delegate = self
        service.schedule(in: .main, forMode: .common)
        service.resolve(withTimeout: 4)
    }

    func netServiceBrowser(_ browser: NetServiceBrowser, didRemove service: NetService, moreComing: Bool) {
        services.removeAll { $0 == service }
    }

    func netServiceDidResolveAddress(_ sender: NetService) {
        guard active, let host = sender.hostName?.trimmingCharacters(in: CharacterSet(charactersIn: ".")),
              let origin = URL(string: "http://\(host):\(sender.port)"), DiscoveredBridge.allowedOrigin(origin) else { return }
        probeTasks.removeAll { $0.isCancelled }
        let task = Task { [weak self, client] in
            guard let response = try? await client.discover(at: origin, selfOnly: true), !Task.isCancelled else { return }
            self?.merge(response.bridge)
        }
        probeTasks.append(task)
    }

    private enum PairingError: Error {
        case rejected, expired
        var message: String { self == .rejected ? "The Mac rejected this pairing request." : "Pairing expired. Select the Mac to try again." }
    }
}
