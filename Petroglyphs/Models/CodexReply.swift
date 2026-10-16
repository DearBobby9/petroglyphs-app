import Foundation

enum CodexSubmissionState: String, Decodable {
    case pending, dispatching, queued, running, completed, failed, unknown

    var isTerminal: Bool { self == .completed || self == .failed }

    var label: String {
        switch self {
        case .pending: "Waiting to send"
        case .dispatching: "Sending to Codex"
        case .queued: "Queued in Codex"
        case .running: "Codex is replying"
        case .completed: "Completed"
        case .failed: "Could not complete"
        case .unknown: "Waiting for status"
        }
    }
}

struct CodexReplyMessage: Decodable, Identifiable, Equatable {
    let id: String
    let text: String
    let phase: String
}

struct CodexSubmissionStatus: Decodable {
    let id: String
    let threadId: String
    let hostId: String
    let state: CodexSubmissionState
    let messages: [CodexReplyMessage]
    let error: String?
    let coalescedSubmissionIds: [String]?
    let notice: String?
}

struct CodexRecentSubmission: Decodable {
    let id: String
    let threadId: String
    let hostId: String
    let createdAt: Date
}

struct CodexRecentSubmissions: Decodable {
    let submissions: [CodexRecentSubmission]
}

struct CodexReply: Identifiable {
    let id: String
    let threadId: String
    let hostId: String
    let hostName: String
    let chatTitle: String
    let serverURL: URL
    let imageData: Data?
    let sentAt: Date
    var state: CodexSubmissionState = .pending
    var messages: [CodexReplyMessage] = []
    var error: String?
    var notice: String?
    var updateError: String?
    var updatesPaused = false
    var canRetryUpdates = true
    var nextPollAt = Date()
    var failedReads = 0
    var unchangedReads = 0
    var needsStatusRefresh = false
    var refreshVersion = 0

    var needsUpdates: Bool { (!state.isTerminal || needsStatusRefresh) && !updatesPaused }
    var identity: String { "\(serverURL.absoluteString)|\(hostId)|\(id)" }
}
