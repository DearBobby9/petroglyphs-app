import Foundation

struct CodexThread: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let cwd: String
    let updatedAt: TimeInterval
    var projectId: String? = nil
    var projectName: String? = nil

    var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled chat" : title
    }

}

struct CodexThreadPage: Decodable {
    let threads: [CodexThread]
    let nextCursor: String?
}

struct CodexChatTarget: Codable, Equatable {
    let thread: CodexThread
    let serverURL: URL
    let host: CodexHost
    var projectId: String? = nil
    var projectName: String? = nil
}
