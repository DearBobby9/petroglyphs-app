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
    @MainActor
    func testRestoresOnlyTheMostRecentChatForTheExactBridgeURL() throws {
        let name = "recent-mac-switch-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = CodexRecentChatStore(defaults: defaults)
        let a = URL(string: "http://mac-a.local:3333/device/aaa")!
        let b = URL(string: "http://mac-b.local:3333/device/bbb")!
        let host = CodexHost(id: "local", name: "This Mac", kind: "local", configured: true, available: true, reason: nil)
        for (url, id) in [(a, "a1"), (a, "a2"), (b, "b1")] {
            store.remember(CodexChatTarget(thread: CodexThread(id: id, title: id, cwd: "/", updatedAt: 0), serverURL: url, host: host))
        }
        XCTAssertEqual(store.latest(for: a)?.thread.id, "a2")
        XCTAssertEqual(store.latest(for: b)?.thread.id, "b1")
        XCTAssertNil(store.latest(for: URL(string: "http://mac-c.local:3333/device/ccc")!))
        XCTAssertNil(store.latest(for: URL(string: "http://mac-a.local:3333/device/new-token")!))
        XCTAssertEqual(CodexRecentChatStore(defaults: defaults).latest(for: a)?.thread.id, "a2")
    }

}
