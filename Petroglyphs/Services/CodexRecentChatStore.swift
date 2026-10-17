import Foundation
import Observation

@MainActor
@Observable
final class CodexRecentChatStore {
    private(set) var targets: [CodexChatTarget]
    @ObservationIgnored private let defaults: UserDefaults
    private static let storageKey = "recentCodexChats.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        targets = defaults.data(forKey: Self.storageKey).flatMap { try? JSONDecoder().decode([CodexChatTarget].self, from: $0) } ?? []
    }

    func latest(for serverURL: URL) -> CodexChatTarget? {
        targets.first { $0.serverURL == serverURL }
    }

    func remember(_ target: CodexChatTarget) {
        targets.removeAll { $0.serverURL == target.serverURL && $0.host.id == target.host.id && $0.thread.id == target.thread.id }
        targets.insert(target, at: 0)
        targets = Array(targets.prefix(100))
        if let data = try? JSONEncoder().encode(targets) { defaults.set(data, forKey: Self.storageKey) }
    }
}
