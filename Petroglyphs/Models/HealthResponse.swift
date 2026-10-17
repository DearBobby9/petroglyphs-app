import Foundation

struct HealthResponse: Codable, Sendable {
    let status: String
    let version: String
    let submissions: Int
    let autoReply: AutoReplyHealth?
    var capabilities: Capabilities? = nil
    var supportsCodexConversations: Bool { capabilities?.conversations ?? autoReply?.enabled ?? false }

    struct Capabilities: Codable, Sendable {
        let conversations: Bool
        let projects: Bool
        let controls: Bool
    }
    var bridge: BridgeConnectionMetadata? = nil

    struct AutoReplyHealth: Codable, Sendable {
        let enabled: Bool
    }
}
