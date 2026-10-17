import Foundation

struct CodexExecutionControls: Decodable {
    let hostId: String
    let threadId: String
    let observedAt: String
    let activeTurnId: String?
    let capabilities: Capabilities
    let pendingInteractions: [PendingInteraction]

    struct Capability: Decodable {
        let supported: Bool
        let reason: String?
        let handlingLocation: String
    }
    struct Capabilities: Decodable {
        let stop: Capability
        let answer: Capability
        let approve: Capability
    }
    struct PendingInteraction: Decodable, Identifiable {
        let kind: String
        let turnId: String?
        let handlingLocation: String
        let reason: String
        var id: String { "\(kind):\(turnId ?? "unknown")" }
    }
}

struct CodexStopTurnResult: Decodable {
    let hostId: String
    let threadId: String
    let turnId: String
    let status: String
    let observedAt: String
}
