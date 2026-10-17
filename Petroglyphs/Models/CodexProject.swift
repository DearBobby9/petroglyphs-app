import Foundation

struct CodexProject: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let path: String
    let canCreate: Bool
    let reason: String?
    var supportsFirstMessageAttachments = false

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
    var attachments: [CodexCreateChatAttachment] = []
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
    var firstMessageState: String? = nil
    var firstMessageRequestId: String? = nil
    var firstTurnId: String? = nil
    var firstMessageId: String? = nil
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

struct CodexCreateChatAttachment: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let mimeType: String
    let dataBase64: String
    var imageData: Data? { Data(base64Encoded: dataBase64) }
}

extension CodexCreateChatRequest {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        hostId = try values.decode(String.self, forKey: .hostId)
        projectId = try values.decode(String.self, forKey: .projectId)
        prompt = try values.decode(String.self, forKey: .prompt)
        title = try values.decodeIfPresent(String.self, forKey: .title)
        selection = try values.decodeIfPresent(CodexModelSelection.self, forKey: .selection)
        attachments = try values.decodeIfPresent([CodexCreateChatAttachment].self, forKey: .attachments) ?? []
    }
}

extension CodexProject {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        name = try values.decode(String.self, forKey: .name)
        path = try values.decode(String.self, forKey: .path)
        canCreate = try values.decode(Bool.self, forKey: .canCreate)
        reason = try values.decodeIfPresent(String.self, forKey: .reason)
        supportsFirstMessageAttachments = try values.decodeIfPresent(Bool.self, forKey: .supportsFirstMessageAttachments) ?? false
    }
}
