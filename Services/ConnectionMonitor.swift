import Foundation

@Observable
class ConnectionMonitor {
    var isConnected = false
    var serverURL: URL?

    private let network = NetworkService()
    private var timer: Timer?

    func start(url: URL) {
        serverURL = url
        checkHealth()
        timer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.checkHealth()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        isConnected = false
        serverURL = nil
    }

    func checkHealth() {
        guard let url = serverURL else { return }
        Task {
            do {
                _ = try await network.healthCheck(url)
                await MainActor.run { self.isConnected = true }
            } catch {
                await MainActor.run { self.isConnected = false }
            }
        }
    }
}
