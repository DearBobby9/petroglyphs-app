import Foundation

struct HealthResponse: Codable, Sendable {
    let status: String
    let version: String
    let submissions: Int
    let autoReply: AutoReplyHealth?
    var bridge: BridgeConnectionMetadata? = nil

    struct AutoReplyHealth: Codable, Sendable {
        let enabled: Bool
    }
}
