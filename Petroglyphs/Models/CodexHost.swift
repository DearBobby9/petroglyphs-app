import Foundation

struct CodexHost: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let kind: String
    let configured: Bool
    let available: Bool
    let reason: String?

    var canSelect: Bool { configured && available }

    var unavailabilityReason: String? {
        guard !canSelect else { return nil }
        if let reason, !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return reason
        }
        return kind == "remote"
            ? "This remote connection is unavailable. Reconnect it in Codex, then refresh."
            : "This Mac is unavailable. Reconnect, then refresh."
    }
}

struct CodexHostList: Decodable {
    let hosts: [CodexHost]
}
