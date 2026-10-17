import XCTest

final class CodexTargetAvailabilityTests: XCTestCase {
    @MainActor
    func testRecoveredHostAndDistinctConnectionFailuresUpdateCurrentTarget() async throws {
        let network = TargetAvailabilityFixture()
        let model = CodexTargetAvailabilityModel(network: network)
        let target = makeTarget("a")
        let recovered = await model.refresh(for: target)
        XCTAssertEqual(recovered?.host.canSelect, true)
        XCTAssertNil(model.error)
        await network.setMode(.threadMissing)
        _ = await model.refresh(for: target)
        XCTAssertTrue(model.error?.contains("This chat is unavailable") == true)
        await network.setMode(.hostOffline)
        let offline = await model.refresh(for: target)
        XCTAssertEqual(offline?.host.canSelect, false)
        XCTAssertTrue(model.error?.contains("Execution host") == true)
        await network.setMode(.bridgeOffline)
        _ = await model.refresh(for: target)
        XCTAssertTrue(model.error?.contains("bridge Mac") == true)
        await network.setMode(.available)
        _ = await model.refresh(for: target)
        XCTAssertNil(model.error)
    }

    @MainActor
    func testOldHostReadCannotReplaceLaterSelectedChat() async throws {
        let network = TargetAvailabilityFixture()
        await network.suspendNextHosts()
        let model = CodexTargetAvailabilityModel(network: network)
        let old = Task { await model.refresh(for: makeTarget("a")) }
        await network.waitForHosts()
        _ = await model.refresh(for: makeTarget("b"))
        await network.finishHosts()
        let stale = await old.value
        XCTAssertNil(stale)
        XCTAssertEqual(model.target?.thread.id, "b")
        XCTAssertNil(model.error)
    }

    private func makeTarget(_ id: String) -> CodexChatTarget {
        CodexChatTarget(thread: CodexThread(id: id, title: id, cwd: "/project", updatedAt: 0),
            serverURL: URL(string: "http://bridge.invalid/device/test")!,
            host: CodexHost(id: "remote-control:mini", name: "Mini", kind: "remote", configured: true, available: false, reason: "Old cached offline state"))
    }
}

private actor TargetAvailabilityFixture: CodexTargetAvailabilityNetworking {
    enum Mode { case available, hostOffline, bridgeOffline, threadMissing }
    private var mode = Mode.available
    private var shouldSuspend = false
    private var gate: CheckedContinuation<Void, Never>?
    private var entered: CheckedContinuation<Void, Never>?
    func setMode(_ mode: Mode) { self.mode = mode }
    func suspendNextHosts() { shouldSuspend = true }
    func waitForHosts() async {
        if gate != nil { return }
        await withCheckedContinuation { entered = $0 }
    }
    func finishHosts() { gate?.resume(); gate = nil }
    func codexHosts(from serverURL: URL) async throws -> [CodexHost] {
        if shouldSuspend {
            shouldSuspend = false
            await withCheckedContinuation { continuation in gate = continuation; entered?.resume(); entered = nil }
        }
        if mode == .bridgeOffline { throw URLError(.cannotConnectToHost) }
        return [CodexHost(id: "remote-control:mini", name: "Mini", kind: "remote", configured: true, available: mode != .hostOffline, reason: nil)]
    }
    func codexModelSettings(from serverURL: URL, hostId: String, threadId: String) async throws -> CodexThreadModelSettings {
        if mode == .threadMissing { throw NetworkService.NetworkError.server(statusCode: 404, message: "Missing thread") }
        return CodexThreadModelSettings(hostId: hostId, threadId: threadId, model: "model", reasoningEffort: "high", observedAt: "2026-10-17T01:00:00Z")
    }
}
