import Foundation
import Observation

@MainActor
@Observable
final class CodexExecutionControlModel {
    private(set) var controls: CodexExecutionControls?
    private(set) var isLoading = false
    private(set) var isStopping = false
    private(set) var error: String?
    private(set) var stopResult: CodexStopTurnResult?
    private(set) var uncertainTurnID: String?
    @ObservationIgnored private let network: any CodexExecutionControlNetworking
    @ObservationIgnored private var key: CodexConversationKey?
    @ObservationIgnored private var loadID = UUID()
    @ObservationIgnored private var destinationGeneration = UUID()

    init(network: any CodexExecutionControlNetworking = NetworkService()) { self.network = network }

    var canStop: Bool {
        controls?.capabilities.stop.supported == true && controls?.activeTurnId != nil
            && controls?.activeTurnId != uncertainTurnID && !isStopping
    }

    func load(for target: CodexChatTarget) async {
        let key = CodexConversationKey(target)
        let id = UUID()
        loadID = id
        if self.key != key { destinationGeneration = UUID(); controls = nil; uncertainTurnID = nil; stopResult = nil; isStopping = false }
        self.key = key
        isLoading = true
        defer { if loadID == id { isLoading = false } }
        do {
            let result = try await network.executionControls(for: key)
            guard loadID == id, !Task.isCancelled else { return }
            guard result.hostId == key.hostId, result.threadId == key.threadId else { throw NetworkService.NetworkError.badResponse }
            controls = result
            if result.activeTurnId != uncertainTurnID { uncertainTurnID = nil }
            error = uncertainTurnID == nil ? nil : "The stop result is not confirmed. Check this turn in Codex in ChatGPT Desktop."
        } catch {
            guard loadID == id, !Task.isCancelled else { return }
            controls = nil
            self.error = error.localizedDescription
        }
    }

    func stop() async {
        guard canStop, let key, let turnID = controls?.activeTurnId else { return }
        let generation = destinationGeneration
        isStopping = true
        defer { if destinationGeneration == generation { isStopping = false } }
        do {
            let result = try await network.stopTurn(turnID, for: key)
            guard self.key == key, destinationGeneration == generation else { return }
            guard result.hostId == key.hostId, result.threadId == key.threadId, result.turnId == turnID,
                  ["stopped", "already_finished"].contains(result.status) else { throw NetworkService.NetworkError.badResponse }
            stopResult = result
            if controls?.activeTurnId == turnID { controls = nil }
            error = nil
        } catch {
            guard self.key == key, destinationGeneration == generation else { return }
            // A lost response may follow a successful stop. Never retry it from polling.
            uncertainTurnID = turnID
            self.error = "The stop result is not confirmed. Check this turn in Codex in ChatGPT Desktop. \(error.localizedDescription)"
        }
    }
}
