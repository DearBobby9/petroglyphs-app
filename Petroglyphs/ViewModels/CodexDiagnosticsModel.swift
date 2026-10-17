import Foundation
import Observation

@MainActor
@Observable
final class CodexDiagnosticsModel {
    private(set) var diagnostics: CodexBridgeDiagnostics?
    private(set) var isLoading = false
    private(set) var error: String?
    @ObservationIgnored private let network: any CodexDiagnosticsNetworking
    @ObservationIgnored private var requestID = UUID()

    init(network: any CodexDiagnosticsNetworking = NetworkService()) { self.network = network }

    func load(for target: CodexChatTarget) async {
        let id = UUID()
        requestID = id
        let key = CodexConversationKey(target)
        isLoading = true
        diagnostics = nil
        error = nil
        defer { if requestID == id { isLoading = false } }
        do {
            let value = try await network.bridgeDiagnostics(for: key)
            guard requestID == id, !Task.isCancelled else { return }
            guard value.version == 1 else {
                throw NetworkService.NetworkError.server(statusCode: 409, message: "The bridge diagnostic protocol is incompatible with this app version.")
            }
            guard value.hostId == key.hostId, value.threadId == key.threadId else { throw NetworkService.NetworkError.badResponse }
            diagnostics = value
        } catch {
            guard requestID == id, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }
}
