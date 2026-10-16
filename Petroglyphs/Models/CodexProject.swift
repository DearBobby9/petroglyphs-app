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
}
