import XCTest

final class CodexExecutionControlTests: XCTestCase {
    func testStopErrorJSONPreservesOnlyExplicitNotSentEvidence() throws {
        for (json, notSent) in [
            (#"{"error":"Unavailable","code":"controls_unavailable","outcome":"not_sent"}"#, true),
            (#"{"error":"Unavailable","outcome":"unknown"}"#, false),
            (#"{"error":"Unavailable"}"#, false)
        ] {
            XCTAssertThrowsError(try NetworkService.decodeControlResponse(Data(json.utf8), statusCode: 503) as CodexStopTurnResult) { error in
                XCTAssertEqual(error is CodexControlNotSent, notSent)
            }
        }
    }

    @MainActor
    func testUnknownStopNeverReplaysAndAnotherTurnRequiresFreshEvidence() async throws {
        let network = ControlNetworkFixture()
        let model = CodexExecutionControlModel(network: network)
        let target = makeTarget()
        await model.load(for: target)
        XCTAssertTrue(model.canStop)
        await model.stop()
        await model.stop()
        await model.load(for: target)
        XCTAssertFalse(model.canStop)
        XCTAssertEqual(model.uncertainTurnID, "turn-a")
        await network.advanceToNextTurn()
        await model.load(for: target)
        XCTAssertTrue(model.canStop)
        await model.stop()
        XCTAssertEqual(model.stopResult?.turnId, "turn-b")
        let stopped = await network.stopIDs
        XCTAssertEqual(stopped, ["turn-a", "turn-b"])
    }

    @MainActor
    func testLateStopResultDoesNotClearControlsForANewerTurn() async throws {
        let network = ControlNetworkFixture()
        await network.suspendStop()
        let model = CodexExecutionControlModel(network: network)
        let target = makeTarget()
        await model.load(for: target)
        let stop = Task { await model.stop() }
        await network.waitForStop()
        await network.advanceToNextTurn()
        await model.load(for: target)
        await network.finishStop()
        await stop.value
        XCTAssertEqual(model.controls?.activeTurnId, "turn-b")
        XCTAssertTrue(model.canStop)
        XCTAssertEqual(model.stopResult?.turnId, "turn-a")
        XCTAssertNil(model.stopFeedback(for: "turn-b"))
    }

    @MainActor
    func testNotSentAllowsManualRetryOnlyAfterFreshControls() async throws {
        let network = ControlNetworkFixture()
        await network.rejectWithoutSending()
        let model = CodexExecutionControlModel(network: network)
        await model.load(for: makeTarget())
        await model.stop()
        XCTAssertNil(model.uncertainTurnID)
        XCTAssertFalse(model.canStop)
        await model.stop()
        let firstCount = await network.stopIDs.count
        XCTAssertEqual(firstCount, 1)
        await model.load(for: makeTarget())
        XCTAssertTrue(model.canStop)
        await model.stop()
        let count = await network.stopIDs.count
        XCTAssertEqual(count, 2)
    }

    private func makeTarget() -> CodexChatTarget {
        CodexChatTarget(thread: CodexThread(id: "chat", title: "Chat", cwd: "/project", updatedAt: 0),
            serverURL: URL(string: "http://bridge.invalid/device/test")!,
            host: CodexHost(id: "local", name: "Mac", kind: "local", configured: true, available: true, reason: nil))
    }
}

private actor ControlNetworkFixture: CodexExecutionControlNetworking {
    private var turnID = "turn-a"
    private var shouldSuspend = false
    private var notSent = false
    func rejectWithoutSending() { notSent = true }
    private var gate: CheckedContinuation<Void, Never>?
    private var entered: CheckedContinuation<Void, Never>?
    var stopIDs: [String] = []

    func suspendStop() { shouldSuspend = true }
    func advanceToNextTurn() { turnID = "turn-b" }
    func waitForStop() async {
        if gate != nil { return }
        await withCheckedContinuation { entered = $0 }
    }
    func finishStop() { gate?.resume(); gate = nil }
    func executionControls(for key: CodexConversationKey) async throws -> CodexExecutionControls {
        CodexExecutionControls(hostId: key.hostId, threadId: key.threadId, observedAt: "2026-10-17T01:00:00Z", activeTurnId: turnID,
            capabilities: .init(stop: .init(supported: true, reason: nil, handlingLocation: "ipad"),
                answer: .init(supported: false, reason: "no_authoritative_receipt", handlingLocation: "desktop"),
                approve: .init(supported: false, reason: "no_authoritative_receipt", handlingLocation: "desktop")), pendingInteractions: [])
    }
    func stopTurn(_ turnID: String, for key: CodexConversationKey) async throws -> CodexStopTurnResult {
        stopIDs.append(turnID)
        if notSent { throw CodexControlNotSent(message: "Unavailable before dispatch") }
        if shouldSuspend {
            await withCheckedContinuation { continuation in
                gate = continuation
                entered?.resume()
                entered = nil
            }
        } else if turnID == "turn-a" { throw URLError(.timedOut) }
        return CodexStopTurnResult(hostId: key.hostId, threadId: key.threadId, turnId: turnID, status: "stopped", observedAt: "2026-10-17T01:00:01Z")
    }
}
