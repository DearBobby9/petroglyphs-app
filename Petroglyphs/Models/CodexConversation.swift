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
    case pending, dispatching, queued, running, completed, failed, unknown, cancelled

    var isTerminal: Bool { self == .completed || self == .failed || self == .cancelled }
    var label: String {
        switch self {
        case .pending: "Waiting to send"
        case .dispatching: "Sending…"
        case .queued: "Queued for the next turn"
        case .running: "Codex is replying"
        case .completed: "Sent"
        case .failed: "Could not complete"
        case .unknown: "Checking delivery…"
        case .cancelled: "Removed from queue"
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
    var unavailableReason: String? = nil
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
    var omittedResultImageCount: Int? = nil

    private enum CodingKeys: String, CodingKey {
        case id, turnId, clientMessageId, role, text, phase, createdAt, state, attachments
        case omittedResultImageCount = "omittedAttachmentCount"
    }

    private enum LegacyCodingKeys: String, CodingKey { case omittedResultImageCount }

    // A native turn replaces its optimistic receipt without replacing the visible row.
    var displayID: String {
        role == "user" ? clientMessageId.map { "user:\($0)" } ?? id : id
    }

    func deliveryLabel(receipt: CodexMessageReceipt?) -> String {
        switch state {
        case .pending: return "Waiting in bridge queue"
        case .dispatching: return "Bridge is dispatching…"
        case .queued, .running, .completed: return "Received by Codex"
        case .failed: return hasNativeTurn(receipt: receipt) ? "Received by Codex" : "Sending failed"
        case .unknown: return hasNativeTurn(receipt: receipt) ? "Received by Codex" : "Delivery not confirmed"
        case .cancelled: return "Cancelled before dispatch"
        }
    }

    func uncertaintyLabel(receipt: CodexMessageReceipt?) -> String {
        hasNativeTurn(receipt: receipt) ? "Response completion not confirmed" : "Delivery not confirmed"
    }

    func uncertaintyNotice(receipt: CodexMessageReceipt?) -> String {
        let uncertainty = hasNativeTurn(receipt: receipt) ? "Response completion is not confirmed." : "Delivery is uncertain."
        return uncertainty + (receipt?.queueBlocking == false
            ? " This request no longer blocks the queue."
            : " This request is still being checked.")
    }

    private func hasNativeTurn(receipt: CodexMessageReceipt?) -> Bool {
        // A turn ID comes from a native start response or observed native history.
        // A bridge receipt/client ID alone does not prove delivery, and a native
        // turn does not prove successful completion (interrupted turns are unknown).
        [turnId, receipt?.turnId, receipt?.message.turnId].compactMap { $0 }
            .contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

extension CodexConversationMessage {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        turnId = try values.decodeIfPresent(String.self, forKey: .turnId)
        clientMessageId = try values.decodeIfPresent(String.self, forKey: .clientMessageId)
        role = try values.decode(String.self, forKey: .role)
        text = try values.decode(String.self, forKey: .text)
        phase = try values.decode(String.self, forKey: .phase)
        createdAt = try values.decodeIfPresent(Date.self, forKey: .createdAt)
        state = try values.decode(CodexMessageState.self, forKey: .state)
        attachments = try values.decode([CodexConversationAttachment].self, forKey: .attachments)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        omittedResultImageCount = try values.decodeIfPresent(Int.self, forKey: .omittedResultImageCount)
            ?? legacy.decodeIfPresent(Int.self, forKey: .omittedResultImageCount)
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
    var queueBlocking: Bool? = nil
    var waitReleasedAt: Date? = nil

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
    var sourceCreationID: String? = nil

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

struct CodexRecoveredDraft: Codable, Identifiable {
    let id: String
    let draft: CodexMessageDraft
    let createdAt: Date
}

struct CodexSubmissionReference: Codable, Equatable, Identifiable {
    let id: String
    let target: CodexChatTarget
}
