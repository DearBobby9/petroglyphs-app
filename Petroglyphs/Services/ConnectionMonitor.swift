import Foundation
import Network

@Observable
@MainActor
class ConnectionMonitor {
    private(set) var isConnected = false
    private(set) var serverURL: URL?
    private(set) var requiresCodexThread: Bool?
    private(set) var activeEndpoint: URL?
    private(set) var route: BridgeRoute?
    private(set) var backupReady = false
    private(set) var automaticRecoveryReady = false
    private(set) var isReconnecting = false

    private var timer: Timer?
    private var pathMonitor: NWPathMonitor?
    private var check: Task<Void, Never>?
    private var failureObserver: NSObjectProtocol?
    private var foreground = true
    private var lastCheck = Date.distantPast
    private var verifiedGeneration: UUID?

    var transportDescription: String { isConnected ? (route?.rawValue ?? "Direct") : "Disconnected" }
    var recoveryDescription: String {
        if backupReady { return "Local network first · Tailscale backup address saved. Keep Tailscale connected on this iPad to use it." }
        if automaticRecoveryReady { return "Local network reconnect ready · Tailscale unavailable" }
        return "Connect once to learn this Mac’s recovery addresses"
    }

    func start(url: URL) {
        if serverURL != url {
            check?.cancel(); check = nil
            isConnected = false; requiresCodexThread = nil; activeEndpoint = nil; route = nil
            verifiedGeneration = nil
            backupReady = false; automaticRecoveryReady = false
        }
        // This stays the original paired URL across route changes. Conversation
        // keys, drafts, selected chats and pending IDs continue to use it.
        serverURL = url
        if foreground { beginMonitoring(); checkHealth() }
    }

    func stop() {
        endMonitoring()
        check?.cancel(); check = nil
        isConnected = false; isReconnecting = false; serverURL = nil
        requiresCodexThread = nil; activeEndpoint = nil; route = nil
        verifiedGeneration = nil
        backupReady = false; automaticRecoveryReady = false
    }

    func setForeground(_ active: Bool) {
        foreground = active
        if active, serverURL != nil { beginMonitoring(); checkHealth() }
        else { endMonitoring() }
    }

    func checkHealth() {
        guard foreground, let url = serverURL, check == nil else { return }
        isReconnecting = !isConnected
        lastCheck = Date()
        check = Task { [weak self] in
            do {
                let snapshot = try await BridgeTransport.shared.connect(to: url, force: true)
                guard let self, !Task.isCancelled, self.serverURL == url else { return }
                self.requiresCodexThread = snapshot.health.autoReply?.enabled ?? false
                self.activeEndpoint = snapshot.origin; self.route = snapshot.route
                self.verifiedGeneration = snapshot.generation
                self.backupReady = snapshot.backupReady
                self.automaticRecoveryReady = snapshot.automaticRecoveryReady
                self.isConnected = true
            } catch {
                guard let self, !Task.isCancelled, self.serverURL == url else { return }
                self.isConnected = false
            }
            guard let self, self.serverURL == url, !Task.isCancelled else { return }
            self.isReconnecting = false
            self.check = nil
        }
    }

    private func beginMonitoring() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.checkHealth() }
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, Date().timeIntervalSince(self.lastCheck) > 1 else { return }
                self.checkHealth()
            }
        }
        monitor.start(queue: DispatchQueue(label: "Petroglyphs.ConnectionPath"))
        pathMonitor = monitor
        failureObserver = NotificationCenter.default.addObserver(forName: BridgeTransport.failedNotification, object: nil, queue: .main) { [weak self] notification in
            guard let failure = notification.object as? BridgeConnectionFailure else { return }
            Task { @MainActor in
                guard let self, let url = self.serverURL,
                      PairedBridge(url)?.storageKey == failure.pairedKey,
                      await BridgeTransport.shared.isCurrentFailure(failure), self.serverURL == url else { return }
                // A notification can wait on the main queue while another check
                // succeeds. Only its verified generation may change UI state.
                guard self.activeEndpoint == failure.origin, self.verifiedGeneration == failure.generation else {
                    self.checkHealth()
                    return
                }
                self.isConnected = false
                if Date().timeIntervalSince(self.lastCheck) > 1 { self.checkHealth() }
            }
        }
    }

    private func endMonitoring() {
        timer?.invalidate(); timer = nil
        pathMonitor?.cancel(); pathMonitor = nil
        if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
        failureObserver = nil
    }
}
