import Foundation
import Observation

@MainActor
@Observable
final class CodexModelSettingsModel {
    private(set) var catalogue: CodexModelCatalog?
    private(set) var settings: CodexThreadModelSettings?
    private(set) var isLoading = false
    private(set) var error: String?

    @ObservationIgnored private let network: any CodexModelSettingsNetworking
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var requestID = UUID()
    private var catalogueError: String?
    private var context: LoadContext?

    init(network: any CodexModelSettingsNetworking = NetworkService(), now: @escaping () -> Date = Date.init) {
        self.network = network
        self.now = now
    }

    func observe(from serverURL: URL, hostId: String, threadId: String?,
                 sleep: @MainActor (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) async {
        while !Task.isCancelled {
            await load(from: serverURL, hostId: hostId, threadId: threadId)
            guard !Task.isCancelled, matches(from: serverURL, hostId: hostId, threadId: threadId) else { return }
            do { try await sleep(nextRefreshInterval) }
            catch { return }
            guard matches(from: serverURL, hostId: hostId, threadId: threadId) else { return }
        }
    }

    func load(from serverURL: URL, hostId: String, threadId: String?) async {
        let id = UUID()
        requestID = id
        context = LoadContext(serverURL: serverURL, hostId: hostId, threadId: threadId)
        catalogue = nil
        settings = nil
        error = nil
        catalogueError = nil
        isLoading = true
        defer { if requestID == id { isLoading = false } }

        async let catalogueResult = readCatalogue(from: serverURL, hostId: hostId)
        async let settingsResult = readSettings(from: serverURL, hostId: hostId, threadId: threadId)
        let results = await (catalogueResult, settingsResult)
        guard requestID == id, !Task.isCancelled else { return }

        var errors: [String] = []
        switch results.0 {
        case .success(let result): catalogue = result
        case .failure(let failure):
            let message = "Available models could not be loaded. \(failure.localizedDescription)"
            catalogueError = message
            errors.append(message)
        }
        switch results.1 {
        case .success(let result): settings = result
        case .failure(let failure):
            errors.append("Chat settings could not be loaded. \(failure.localizedDescription)")
        }
        error = errors.isEmpty ? nil : errors.joined(separator: "\n")
    }

    func matches(from serverURL: URL, hostId: String, threadId: String?) -> Bool {
        context == LoadContext(serverURL: serverURL, hostId: hostId, threadId: threadId)
    }

    var nextRefreshInterval: TimeInterval {
        let retryInterval: TimeInterval = 30
        guard !isLoading, let catalogue, catalogue.status == "available", !catalogue.models.isEmpty,
              let expiry = catalogueExpiry else { return retryInterval }
        let remaining = expiry.timeIntervalSince(now())
        guard remaining > 0 else { return retryInterval }
        // Retry a failed settings read without waiting past a still-valid catalogue's expiry.
        return error == nil ? remaining : min(retryInterval, remaining)
    }

    var selectionUnavailableReason: String? {
        if isLoading { return "Loading available models…" }
        if let catalogueError { return catalogueError }
        guard let catalogue else { return "Load the models available on this host to choose a model." }
        guard catalogue.status == "available" else {
            switch catalogue.reason {
            case "not_configured": return "Model selection is not configured on this host."
            case "catalogue_stale": return "The model list has expired. Reload it before choosing a model."
            case "invalid_catalogue": return "This host returned an invalid model list."
            default: return "The model list is unavailable on this host."
            }
        }
        guard let expiry = catalogueExpiry else {
            return "This host returned an invalid model list."
        }
        // Recheck time at submission, even when the picker has stayed open.
        guard now() < expiry else {
            return "The model list has expired. Reload it before choosing a model."
        }
        return catalogue.models.isEmpty ? "No models are available on this host." : nil
    }

    func validationMessage(for selection: CodexDraftModelSelection?, hasImages: Bool = false) -> String? {
        guard let selection else { return nil }
        if let reason = selectionUnavailableReason { return reason }
        guard let model = model(named: selection.model) else { return "This model is no longer available on this host. Choose another model." }
        guard model.inputModalities.contains("text") else {
            return "This model does not accept text. Choose a model that supports text."
        }
        if hasImages && !model.inputModalities.contains("image") {
            return "This model does not accept images. Choose a model that supports images or remove the images."
        }
        guard let effort = selection.reasoningEffort, !effort.isEmpty else { return "Choose a reasoning effort for this model." }
        guard model.supportedReasoningEfforts.contains(where: { $0.reasoningEffort == effort }) else {
            return "This reasoning effort is not supported by the selected model. Choose another effort."
        }
        return nil
    }

    func model(named name: String) -> CodexAvailableModel? {
        catalogue?.models.first { $0.model == name }
    }

    private var catalogueExpiry: Date? {
        guard let observedAt = catalogue?.observedAt.flatMap(Self.date),
              let expiresAt = catalogue?.expiresAt.flatMap(Self.date), expiresAt > observedAt else { return nil }
        return min(expiresAt, observedAt.addingTimeInterval(5 * 60))
    }

    private func readCatalogue(from serverURL: URL, hostId: String) async -> Result<CodexModelCatalog, Error> {
        do {
            let result = try await network.codexModels(from: serverURL, hostId: hostId)
            guard result.hostId == hostId else { throw NetworkService.NetworkError.badResponse }
            return .success(result)
        } catch { return .failure(error) }
    }

    private func readSettings(from serverURL: URL, hostId: String, threadId: String?) async -> Result<CodexThreadModelSettings?, Error> {
        guard let threadId else { return .success(nil) }
        do {
            let result = try await network.codexModelSettings(from: serverURL, hostId: hostId, threadId: threadId)
            guard result.hostId == hostId, result.threadId == threadId else { throw NetworkService.NetworkError.badResponse }
            return .success(result)
        } catch { return .failure(error) }
    }

    private static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private struct LoadContext: Equatable {
        let serverURL: URL
        let hostId: String
        let threadId: String?
    }
}
