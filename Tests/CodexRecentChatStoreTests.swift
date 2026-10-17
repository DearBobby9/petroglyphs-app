import XCTest

final class CodexRecentChatStoreTests: XCTestCase {
    @MainActor
    func testRecentChatsRemainAvailableWithoutDirectoryRequestsAfterRestart() throws {
        let name = "recent-chats-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let bridge = URL(string: "http://bridge.invalid/device/test")!
        let host = CodexHost(id: "local", name: "Mac", kind: "local", configured: true, available: false, reason: "Offline")
        let a = CodexChatTarget(thread: CodexThread(id: "a", title: "A", cwd: "/a", updatedAt: 0), serverURL: bridge, host: host)
        let b = CodexChatTarget(thread: CodexThread(id: "b", title: "B", cwd: "/b", updatedAt: 0), serverURL: bridge, host: host)
        let store = CodexRecentChatStore(defaults: defaults)
        store.remember(a)
        store.remember(b)
        let restored = CodexRecentChatStore(defaults: defaults)
        XCTAssertEqual(restored.targets.map(\.thread.id), ["b", "a"])
        XCTAssertFalse(restored.targets[1].host.canSelect, "Cached browsing must not pretend the host is online.")
        restored.remember(a)
        XCTAssertEqual(restored.targets.map(\.thread.id), ["a", "b"])
    }
}
