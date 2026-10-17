import Foundation
import CryptoKit

struct CodexConversationKey: Hashable, Codable {
    let serverURL: URL
    let hostId: String
    let threadId: String

    init(_ target: CodexChatTarget) {
        serverURL = target.serverURL
        hostId = target.host.id
        threadId = target.thread.id
    }

    var storageID: String {
        let bytes = Data("\(serverURL.absoluteString)\n\(hostId)\n\(threadId)".utf8)
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
}

enum CodexMessageState: String, Codable {
    case pending, dispatching, queued, running, completed, failed, unknown

    var isTerminal: Bool { self == .completed || self == .failed }
    var label: String {
        switch self {
        case .pending: "Waiting to send"
        case .dispatching: "Sending…"
        case .queued: "Queued for the next turn"
        case .running: "Codex is replying"
        case .completed: "Sent"
        case .failed: "Could not complete"
        case .unknown: "Checking delivery…"
        }
    }
}

struct CodexConversationAttachment: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let mimeType: String
    let availability: String
    let byteCount: Int?
    let assetPath: String?
    var localFilename: String? = nil
}

struct CodexConversationMessage: Codable, Identifiable, Equatable {
    let id: String
    let turnId: String?
    let clientMessageId: String?
    let role: String
    let text: String
    let phase: String
    let createdAt: Date?
    var state: CodexMessageState
    var attachments: [CodexConversationAttachment]

    // A native turn replaces its optimistic receipt without replacing the visible row.
    var displayID: String {
        role == "user" ? clientMessageId.map { "user:\($0)" } ?? id : id
    }
}

struct CodexMessageReceipt: Codable, Identifiable, Equatable {
    let id: String
    let hostId: String
    let threadId: String
    let createdAt: Date
    let updatedAt: Date
    let state: CodexMessageState
    let turnId: String?
    let message: CodexConversationMessage
    let error: String?
    let notice: String?
    let selection: CodexModelSelection?
    let modelEvidence: CodexModelEvidence?
    let modelVerification: String?

    init(id: String, hostId: String, threadId: String, createdAt: Date, updatedAt: Date,
         state: CodexMessageState, turnId: String?, message: CodexConversationMessage,
         error: String?, notice: String?, selection: CodexModelSelection? = nil,
         modelEvidence: CodexModelEvidence? = nil, modelVerification: String? = nil) {
        self.id = id
        self.hostId = hostId
        self.threadId = threadId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.state = state
        self.turnId = turnId
        self.message = message
        self.error = error
        self.notice = notice
        self.selection = selection
        self.modelEvidence = modelEvidence
        self.modelVerification = modelVerification
    }
}

struct CodexConversationPage: Decodable {
    let hostId: String
    let threadId: String
    let messages: [CodexConversationMessage]
    let beforeCursor: String?
    let runState: String
    let receipts: [CodexMessageReceipt]
    let updatedAt: Date
}

struct CodexMessageRequest: Encodable {
    let id: String
    let hostId: String
    let threadId: String
    let text: String
    let attachments: [Attachment]
    let selection: CodexModelSelection?

    init(id: String, hostId: String, threadId: String, text: String, attachments: [Attachment], selection: CodexModelSelection? = nil) {
        self.id = id
        self.hostId = hostId
        self.threadId = threadId
        self.text = text
        self.attachments = attachments
        self.selection = selection
    }

    struct Attachment: Encodable {
        let id: String
        let name: String
        let mimeType: String
        let dataBase64: String
    }
}

struct CodexDraftAttachment: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let mimeType: String
    let byteCount: Int
    let filename: String

    var messageAttachment: CodexConversationAttachment {
        CodexConversationAttachment(id: id, name: name, mimeType: mimeType,
                                    availability: "available", byteCount: byteCount,
                                    assetPath: nil, localFilename: filename)
    }
}

struct CodexMessageDraft: Codable, Equatable {
    var text = ""
    var attachments: [CodexDraftAttachment] = []
    var modelSelection: CodexDraftModelSelection? = nil
    var isEmpty: Bool { text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && attachments.isEmpty }
}

struct CodexLocalMessage: Codable, Identifiable {
    let id: String
    let text: String
    let attachments: [CodexDraftAttachment]
    let createdAt: Date
    var state: CodexMessageState
    var error: String?
    var notice: String?
    var canRetry = false
    var appearedInHistory = false
    let selection: CodexModelSelection?

    init(id: String, text: String, attachments: [CodexDraftAttachment], createdAt: Date,
         state: CodexMessageState, error: String? = nil, notice: String? = nil,
         canRetry: Bool = false, appearedInHistory: Bool = false, selection: CodexModelSelection? = nil) {
        self.id = id
        self.text = text
        self.attachments = attachments
        self.createdAt = createdAt
        self.state = state
        self.error = error
        self.notice = notice
        self.canRetry = canRetry
        self.appearedInHistory = appearedInHistory
        self.selection = selection
    }

    var message: CodexConversationMessage {
        CodexConversationMessage(id: id, turnId: nil, clientMessageId: id, role: "user", text: text,
                                 phase: "user", createdAt: createdAt, state: state,
                                 attachments: attachments.map(\.messageAttachment))
    }
}
