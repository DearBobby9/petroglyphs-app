import Foundation

struct CodexModelSelection: Codable, Equatable {
    let model: String
    let reasoningEffort: String
}

struct CodexDraftModelSelection: Codable, Equatable {
    var model: String
    var reasoningEffort: String?

    var selection: CodexModelSelection? {
        guard !model.isEmpty, let reasoningEffort, !reasoningEffort.isEmpty else { return nil }
        return CodexModelSelection(model: model, reasoningEffort: reasoningEffort)
    }
}

struct CodexModelCatalog: Codable, Equatable {
    let hostId: String
    let status: String
    let source: String?
    let observedAt: String?
    let expiresAt: String?
    let models: [CodexAvailableModel]
    let reason: String?
}

struct CodexAvailableModel: Codable, Identifiable, Equatable {
    let id: String
    let model: String
    let displayName: String
    let description: String
    let supportedReasoningEfforts: [CodexReasoningOption]
    let defaultReasoningEffort: String
    let inputModalities: [String]
    let isDefault: Bool
}

struct CodexReasoningOption: Codable, Equatable {
    let reasoningEffort: String
    let description: String
}

struct CodexThreadModelSettings: Codable, Equatable {
    let hostId: String
    let threadId: String
    let model: String?
    let reasoningEffort: String?
    let observedAt: String
}

struct CodexModelEvidence: Codable, Equatable {
    let model: String
    let reasoningEffort: String?
    let reroutes: [CodexModelReroute]
}

struct CodexModelReroute: Codable, Equatable {
    let fromModel: String
    let toModel: String
    let reason: String
}
