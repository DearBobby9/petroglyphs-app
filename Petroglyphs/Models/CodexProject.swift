import Foundation

struct CodexProject: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let canCreate: Bool
    let reason: String?

    var displayName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled project" : name
    }
}

struct CodexProjectList: Decodable {
    let hostId: String
    let projects: [CodexProject]
}

struct CodexCreateChatRequest: Codable, Equatable {
    let id: String
    let hostId: String
    let projectId: String
    let prompt: String
    let title: String?
    var selection: CodexModelSelection? = nil
}

enum CodexChatCreationState: String, Codable {
    case pending, creating, completed, failed, unknown

    var isActive: Bool { self == .pending || self == .creating }
}

struct CodexChatCreationReceipt: Codable, Equatable {
    let id: String
    let hostId: String
    let projectId: String
    let state: CodexChatCreationState
    let thread: CodexThread?
    let error: String?
    let notice: String?
    var selection: CodexModelSelection? = nil
    var modelEvidence: CodexModelEvidence? = nil
    var modelVerification: String? = nil
    var attemptId: String? = nil
    var attemptNumber: Int? = nil
    var canRetry: Bool? = nil
    var failureCode: String? = nil
    var creationMethod: String? = nil
}

struct CodexCreationRetryRequest: Codable, Equatable {
    let hostId: String
    let projectId: String
    let attemptId: String
}

struct CodexNewChatDestination: Codable {
    let serverURL: URL
    let host: CodexHost
    let project: CodexProject
    var draftID: String? = nil
}

struct CodexCreationDraftSummary: Identifiable {
    let id: String
    let destination: CodexNewChatDestination?
    let title: String
    let prompt: String
    let updatedAt: Date
    let state: String
    let requestID: String?
    let recoveryError: String?

    var displayTitle: String {
        let text = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? String(prompt.prefix(80)) : text
    }
}
