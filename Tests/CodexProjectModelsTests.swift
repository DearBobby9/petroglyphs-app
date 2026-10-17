import XCTest

final class CodexProjectModelsTests: XCTestCase {
    @MainActor
    func testApprovalTimeoutCannotReplaceTheOriginalRequestWithANewUUID() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .approvalTimeout, receipt: .approvalTimeout)
        let model = creation(network, root: root)
        model.prompt = "Keep the original approval request"
        await model.submit()
        let original = try XCTUnwrap(model.request)
        XCTAssertFalse(model.canEditFailedAttempt)
        XCTAssertTrue(model.canRetryCreation)
        model.editFailedAttempt()
        XCTAssertEqual(model.request, original)
        XCTAssertTrue(model.status?.contains("Approval") == true)
    }

    @MainActor
    func testApprovalRetryUsesOriginalPayloadAndDoubleTapCannotDispatchOrReadTwice() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .approvalTimeout, receipt: .approvalTimeout)
        await network.configureRetry(.suspended)
        let model = creation(network, root: root)
        model.title = "Original title"
        model.prompt = "Original first message"
        model.modelSelection = CodexDraftModelSelection(model: "model-a", reasoningEffort: "high")
        await model.submit()
        let original = try XCTUnwrap(model.request)
        model.title = "Changed locally"
        model.prompt = "Changed locally"
        model.modelSelection = nil
        let retrying = Task { await model.retryCreation() }
        await network.waitForRetry()
        XCTAssertTrue(model.isRetrying)
        XCTAssertFalse(model.canRetryCreation)
        await model.retryCreation()
        await model.checkStatus()
        let inFlight = await network.retryCalls
        let reads = await network.receiptReadCount
        XCTAssertEqual(inFlight, [.init(original: original, attemptId: "attempt-1")])
        XCTAssertEqual(reads, 0)
        await network.finishRetry()
        await retrying.value
        XCTAssertEqual(model.request, original)
        XCTAssertEqual(model.receipt?.attemptNumber, 2)
        XCTAssertNil(model.retryPendingAttemptId)
        XCTAssertEqual(model.createdThread?.id, "created-chat")
    }

    @MainActor
    func testLostRetryResponseSurvivesRestartAndOnlyReadsTheOriginalJob() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .approvalTimeout, receipt: .unavailable)
        await network.configureRetry(.timeout)
        let model = creation(network, root: root)
        model.title = "Preserved title"
        model.prompt = "Preserved first message"
        model.modelSelection = CodexDraftModelSelection(model: "model-a", reasoningEffort: "high")
        await model.submit()
        let original = try XCTUnwrap(model.request)
        await model.retryCreation()
        XCTAssertEqual(model.retryPendingAttemptId, "attempt-1")
        XCTAssertFalse(model.canRetryCreation)
        XCTAssertFalse(model.canRetryOriginal)
        XCTAssertFalse(model.canEditFailedAttempt)

        let restored = creation(network, root: root)
        XCTAssertEqual(restored.retryPendingAttemptId, "attempt-1")
        XCTAssertEqual(restored.title, original.title)
        XCTAssertEqual(restored.prompt, original.prompt)
        XCTAssertEqual(restored.modelSelection?.selection, original.selection)
        await restored.retryCreation()
        await network.configure(post: .approvalTimeout, receipt: .retryCompleted)
        await restored.observeCreation(sleep: { _ in XCTFail("The retry is already completed.") })
        let posts = await network.posts
        let retries = await network.retryCalls
        let reads = await network.receiptRequests
        XCTAssertEqual(posts, [original])
        XCTAssertEqual(retries, [.init(original: original, attemptId: "attempt-1")])
        XCTAssertTrue(reads.allSatisfy { $0 == original })
        XCTAssertEqual(restored.request, original)
        XCTAssertEqual(restored.receipt?.attemptId, "attempt-2")
        XCTAssertNil(restored.retryPendingAttemptId)
        XCTAssertEqual(restored.createdThread?.id, "created-chat")
    }

    @MainActor
    func testUnadmittedRetryCanOnlyBeRetriedExplicitlyAfterFreshStatusConfirmsOriginalAttempt() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .approvalTimeout, receipt: .approvalTimeout)
        await network.configureRetry(.admissionFailed)
        let model = creation(network, root: root)
        model.prompt = "Keep the request when retry admission fails"
        await model.submit()
        let original = try XCTUnwrap(model.request)

        await model.retryCreation()
        XCTAssertNil(model.retryPendingAttemptId)
        XCTAssertTrue(model.canRetryCreation)
        XCTAssertEqual(model.request, original)
        let firstRetries = await network.retryCalls
        let reads = await network.receiptRequests
        XCTAssertEqual(firstRetries, [.init(original: original, attemptId: "attempt-1")])
        XCTAssertEqual(reads, [original])

        let restored = creation(network, root: root)
        XCTAssertNil(restored.retryPendingAttemptId)
        XCTAssertTrue(restored.canRetryCreation)
        await restored.checkStatus()
        let retriesBeforeTap = await network.retryCalls
        XCTAssertEqual(retriesBeforeTap, firstRetries, "Status recovery must not automatically POST the retry.")

        await network.configureRetry(.completed)
        await restored.retryCreation()
        let retriesAfterTap = await network.retryCalls
        let posts = await network.posts
        XCTAssertEqual(retriesAfterTap, Array(repeating: .init(original: original, attemptId: "attempt-1"), count: 2))
        XCTAssertEqual(posts, [original])
        XCTAssertEqual(restored.request, original)
        XCTAssertEqual(restored.receipt?.attemptNumber, 2)
        XCTAssertEqual(restored.createdThread?.id, "created-chat")
    }

    @MainActor
    func testSecondAttemptPreflightFailureRequiresExplicitEditingAndAnotherStart() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .approvalTimeout, receipt: .approvalTimeout)
        await network.configureRetry(.preflightFailed)
        let model = creation(network, root: root)
        model.title = "Keep the failed title"
        model.prompt = "Keep the failed first message"
        model.modelSelection = CodexDraftModelSelection(model: "model-a", reasoningEffort: "high")
        await model.submit()
        let original = try XCTUnwrap(model.request)
        await model.retryCreation()

        let restored = creation(network, root: root)
        XCTAssertEqual(restored.receipt?.state, .failed)
        XCTAssertEqual(restored.receipt?.attemptNumber, 2)
        XCTAssertNil(restored.receipt?.failureCode)
        XCTAssertTrue(restored.canEditFailedAttempt)
        XCTAssertFalse(restored.canRetryCreation)
        XCTAssertFalse(restored.canStartNewRequest)
        await restored.retryCreation()
        await restored.submit()
        XCTAssertEqual(restored.request, original)

        restored.editFailedAttempt()
        XCTAssertNil(restored.request)
        XCTAssertNil(restored.receipt)
        XCTAssertEqual(restored.title, original.title)
        XCTAssertEqual(restored.prompt, original.prompt)
        XCTAssertEqual(restored.modelSelection?.selection, original.selection)
        let postsBeforeStart = await network.posts
        let retriesBeforeStart = await network.retryCalls
        XCTAssertEqual(postsBeforeStart, [original])
        XCTAssertEqual(retriesBeforeStart.count, 1)

        let reopened = creation(network, root: root)
        XCTAssertNil(reopened.request, "Editing must not allocate a new request ID.")
        await network.configure(post: .completed, receipt: .completed)
        await reopened.submit()
        let postsAfterStart = await network.posts
        let retriesAfterStart = await network.retryCalls
        XCTAssertEqual(postsAfterStart.count, 2)
        XCTAssertNotEqual(postsAfterStart.last?.id, original.id)
        XCTAssertEqual(postsAfterStart.last?.prompt, original.prompt)
        XCTAssertEqual(postsAfterStart.last?.title, original.title)
        XCTAssertEqual(postsAfterStart.last?.selection, original.selection)
        XCTAssertEqual(retriesAfterStart.count, 1)
    }

    @MainActor
    func testSecondApprovalFailureCannotRetryOrReplaceTheJobAcrossRestart() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .approvalTimeout, receipt: .retryExhausted)
        await network.configureRetry(.exhausted)
        let model = creation(network, root: root)
        model.prompt = "Only one native retry"
        await model.submit()
        let original = try XCTUnwrap(model.request)
        await model.retryCreation()
        let restored = creation(network, root: root)
        XCTAssertEqual(restored.receipt?.attemptNumber, 2)
        XCTAssertFalse(restored.canRetryCreation)
        XCTAssertFalse(restored.canEditFailedAttempt)
        await restored.retryCreation()
        restored.editFailedAttempt()
        await restored.submit()
        XCTAssertEqual(restored.request, original)
        let posts = await network.posts
        let retries = await network.retryCalls
        XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(retries.count, 1)
    }

    @MainActor
    func testExhaustedApprovalRequiresExplicitNewDraftActionAndThenAnotherStart() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .approvalTimeout, receipt: .retryExhausted)
        await network.configureRetry(.exhausted)
        let model = creation(network, root: root)
        model.title = "Keep this title"
        model.prompt = "Keep this first message"
        model.modelSelection = CodexDraftModelSelection(model: "model-a", reasoningEffort: "high")
        await model.submit()
        let original = try XCTUnwrap(model.request)
        await model.retryCreation()
        let exhausted = creation(network, root: root)
        XCTAssertEqual(exhausted.request, original)
        XCTAssertTrue(exhausted.canStartNewRequest)
        XCTAssertFalse(exhausted.canSubmit)

        exhausted.startNewRequest()
        XCTAssertNil(exhausted.request)
        XCTAssertNil(exhausted.receipt)
        XCTAssertEqual(exhausted.title, original.title)
        XCTAssertEqual(exhausted.prompt, original.prompt)
        XCTAssertEqual(exhausted.modelSelection?.selection, original.selection)
        let postsBeforeStart = await network.posts
        let retriesBeforeStart = await network.retryCalls
        XCTAssertEqual(postsBeforeStart, [original])
        XCTAssertEqual(retriesBeforeStart.count, 1)

        let reopened = creation(network, root: root)
        XCTAssertNil(reopened.request, "Reopening a draft must not allocate a new request ID.")
        XCTAssertEqual(reopened.prompt, original.prompt)
        await network.configure(post: .completed, receipt: .completed)
        await reopened.submit()
        let postsAfterStart = await network.posts
        let retriesAfterStart = await network.retryCalls
        XCTAssertEqual(postsAfterStart.count, 2)
        XCTAssertNotEqual(postsAfterStart.last?.id, original.id)
        XCTAssertEqual(postsAfterStart.last?.prompt, original.prompt)
        XCTAssertEqual(postsAfterStart.last?.title, original.title)
        XCTAssertEqual(postsAfterStart.last?.selection, original.selection)
        XCTAssertEqual(retriesAfterStart.count, 1, "A new request must not dispatch a third attempt on the old job.")
    }

    @MainActor
    func testUnknownAndLegacyReceiptsNeverAuthorizeApprovalRetry() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .timeout, receipt: .unknown)
        let model = creation(network, root: root)
        model.prompt = "Unknown is not retry permission"
        await model.submit()
        XCTAssertFalse(model.canRetryCreation)
        let original = model.request
        XCTAssertFalse(model.canStartNewRequest)
        model.startNewRequest()
        XCTAssertEqual(model.request, original)
        await model.retryCreation()
        await network.configure(post: .timeout, receipt: .unknownWithRetryFlag)
        await model.checkStatus()
        XCTAssertFalse(model.canRetryCreation, "An unknown receipt cannot authorize retry even with a stale capability bit.")
        XCTAssertFalse(model.canStartNewRequest)
        model.startNewRequest()
        XCTAssertEqual(model.request, original)
        await model.retryCreation()
        let retries = await network.retryCalls
        XCTAssertTrue(retries.isEmpty)
    }

    @MainActor
    func testRetryReceiptRejectsAnotherTargetAndOlderAttempt() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .approvalTimeout, receipt: .unavailable)
        await network.configureRetry(.wrongTarget)
        let model = creation(network, root: root)
        model.prompt = "Keep retry scoped"
        await model.submit()
        await model.retryCreation()
        XCTAssertNil(model.createdThread)
        XCTAssertNotNil(model.retryPendingAttemptId)
        await network.configure(post: .approvalTimeout, receipt: .retryUnknown)
        await model.checkStatus()
        XCTAssertEqual(model.receipt?.attemptNumber, 2)
        XCTAssertFalse(model.canEditFailedAttempt)
        await network.configure(post: .approvalTimeout, receipt: .approvalTimeout)
        await model.checkStatus()
        XCTAssertEqual(model.receipt?.attemptNumber, 2)
        XCTAssertFalse(model.canRetryCreation)
        XCTAssertNotNil(model.error)
    }

    @MainActor
    func testNativeCreationKeepsKnownChatWhenFirstMessageIsUnconfirmed() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .timeout, receipt: .nativeCreatedUnconfirmed)
        let model = creation(network, root: root)
        model.prompt = "Preserve the existing native chat"
        await model.submit()
        await model.checkStatus()
        XCTAssertEqual(model.receipt?.creationMethod, "native")
        XCTAssertEqual(model.recoverableThread?.id, "native-created-chat")
        XCTAssertNil(model.createdThread, "Do not automatically dismiss the first-message warning.")
        XCTAssertTrue(model.status?.hasPrefix("Chat created.") == true)
        XCTAssertFalse(model.canRetryCreation)
        XCTAssertFalse(model.canSubmit)
        let original = try XCTUnwrap(model.request)
        let posts = await network.posts
        XCTAssertEqual(posts, [original], "Checking a known chat must not create or send again.")
        let restored = creation(network, root: root)
        XCTAssertEqual(restored.recoverableThread?.id, "native-created-chat")
        restored.acknowledgeOpenedChat()
        await restored.checkStatus()
        XCTAssertNil(creation(network, root: root).request, "Opening the known chat must free this project's next new-chat draft, including after a late status read.")
    }

    @MainActor
    func testUnknownCreationContinuesReadingOriginalRequestUntilLateCompletion() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .timeout, receipt: .unknown)
        let model = creation(network, root: root)
        model.prompt = "One creation only, including a late result"
        await model.submit()
        let original = try XCTUnwrap(model.request)
        var uptime: TimeInterval = 0
        var waits: [TimeInterval] = []
        await model.observeCreation(now: { uptime }, sleep: { interval in
            waits.append(interval)
            uptime += interval
            await network.configure(post: .completed, receipt: .completed)
        })
        XCTAssertEqual(model.createdThread?.id, "created-chat")
        XCTAssertEqual(waits, [2])
        XCTAssertFalse(model.isObservingCreation)
        let posts = await network.posts
        let reads = await network.receiptRequests
        XCTAssertEqual(posts, [original])
        XCTAssertTrue(reads.count >= 3)
        XCTAssertTrue(reads.allSatisfy { $0 == original })
    }

    @MainActor
    func testCancellingCreationObservationStopsReadsAndReentryRestoresTheSameRequest() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .timeout, receipt: .unknown)
        let model = creation(network, root: root)
        model.prompt = "Resume this request after leaving the panel"
        await model.submit()
        let original = try XCTUnwrap(model.request)
        let gate = CreationSleepGate()
        let observing = Task { await model.observeCreation(sleep: { try await gate.sleep($0) }) }
        await gate.waitUntilSleeping()
        let readCountAtCancellation = await network.receiptReadCount
        observing.cancel()
        await gate.release()
        await observing.value
        let readCountAfterCancellation = await network.receiptReadCount
        XCTAssertEqual(readCountAfterCancellation, readCountAtCancellation)
        XCTAssertFalse(model.isObservingCreation)

        let restored = creation(network, root: root)
        await network.configure(post: .completed, receipt: .completed)
        await restored.observeCreation(sleep: { _ in XCTFail("A completed request must stop observing immediately.") })
        XCTAssertEqual(restored.request, original)
        XCTAssertEqual(restored.createdThread?.id, "created-chat")
        let posts = await network.posts
        XCTAssertEqual(posts, [original])
    }

    @MainActor
    func testLongUnknownCreationStopsAutomaticReadsAtItsBudgetAndKeepsManualRecovery() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .timeout, receipt: .unknown)
        let model = creation(network, root: root)
        model.prompt = "Keep an unknown request without replaying it"
        await model.submit()
        let original = try XCTUnwrap(model.request)
        var uptime: TimeInterval = 0
        var waits: [TimeInterval] = []
        await model.observeCreation(now: { uptime }, sleep: { interval in
            waits.append(interval)
            uptime += interval
        })
        XCTAssertEqual(uptime, 300)
        XCTAssertTrue(waits.prefix(5).allSatisfy { $0 == 2 })
        XCTAssertTrue(waits.contains(10))
        XCTAssertTrue(model.statusChecksPaused)
        XCTAssertFalse(model.isObservingCreation)
        XCTAssertFalse(model.canSubmit)
        let reads = await network.receiptRequests
        XCTAssertLessThanOrEqual(reads.count, 40)
        XCTAssertTrue(reads.allSatisfy { $0 == original })

        await network.configure(post: .completed, receipt: .completed)
        await model.checkStatus()
        XCTAssertEqual(model.createdThread?.id, "created-chat")
        XCTAssertFalse(model.statusChecksPaused)
        let posts = await network.posts
        XCTAssertEqual(posts, [original])
    }

    @MainActor
    func testExplicitValidationRejectionRestoresEditableDraftAndNeedsANewStart() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .validationRejected, receipt: .missing)
        let model = creation(network, root: root)
        model.prompt = "Keep my first message"
        model.modelSelection = CodexDraftModelSelection(model: "removed-model", reasoningEffort: "high")
        await model.submit()
        let rejected = try XCTUnwrap(model.request)
        XCTAssertTrue(model.canEditFailedAttempt)
        XCTAssertFalse(model.canStartNewRequest, "A legacy failure is not proof of an exhausted approval attempt.")
        XCTAssertFalse(model.canRetryOriginal)

        let restored = creation(network, root: root)
        await restored.checkStatus()
        XCTAssertTrue(restored.canEditFailedAttempt)
        XCTAssertFalse(restored.canRetryOriginal)
        restored.editFailedAttempt()
        XCTAssertEqual(restored.prompt, rejected.prompt)
        XCTAssertEqual(restored.modelSelection?.selection, rejected.selection)
        XCTAssertNil(restored.request)
        let postsBeforeStart = await network.posts.count
        XCTAssertEqual(postsBeforeStart, 1)

        restored.modelSelection = nil
        await network.configure(post: .completed, receipt: .completed)
        await restored.submit()
        let posts = await network.posts
        XCTAssertEqual(posts.count, 2)
        XCTAssertNotEqual(posts.last?.id, rejected.id)
        XCTAssertNil(posts.last?.selection)
    }

    func testOnlyRecognizedCreationValidationResponsesAreSafeToEdit() throws {
        for code in ["invalid_chat_request", "unsupported_model", "unsupported_reasoning_effort", "unsupported_input_modality"] {
            let data = try JSONSerialization.data(withJSONObject: ["code": code, "error": "Rejected before admission"])
            XCTAssertNotNil(NetworkService.creationRejection(statusCode: 400, data: data))
            XCTAssertNil(NetworkService.creationRejection(statusCode: 409, data: data))
            XCTAssertNil(NetworkService.creationRejection(statusCode: 404, data: data))
        }
        for code in ["id_conflict", "unknown_error"] {
            let data = try JSONSerialization.data(withJSONObject: ["code": code, "error": "Outcome is unknown"])
            XCTAssertNil(NetworkService.creationRejection(statusCode: 400, data: data))
        }
        XCTAssertNil(NetworkService.creationRejection(statusCode: 400, data: Data(#"{"error":"Unclassified error"}"#.utf8)))
    }

    @MainActor
    func testUnsentNewChatDraftRestoresTextAndPartialModelChoiceOnlyForItsDestination() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        let model = creation(network, root: root)
        model.prompt = "Keep this unsent project draft"
        model.title = "My draft"
        model.modelSelection = CodexDraftModelSelection(model: "example-model", reasoningEffort: nil)
        XCTAssertFalse(model.canSubmit, "A newly selected model still needs a supported effort.")

        let restored = creation(network, root: root)
        XCTAssertNil(restored.request)
        XCTAssertEqual(restored.prompt, model.prompt)
        XCTAssertEqual(restored.title, model.title)
        XCTAssertEqual(restored.modelSelection, model.modelSelection)
        XCTAssertTrue(creation(network, root: root, host: "remote").prompt.isEmpty)
        XCTAssertTrue(creation(network, root: root, projectID: "other").prompt.isEmpty)
        XCTAssertTrue(creation(network, root: root, base: URL(string: "http://other.invalid/device/paired")!).prompt.isEmpty)
    }

    @MainActor
    func testCreationRetryAndRestartRetainSubmittedModelRatherThanLaterDraftChoice() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .timeout, receipt: .missing)
        let model = creation(network, root: root)
        model.prompt = "Create with the chosen settings"
        model.modelSelection = CodexDraftModelSelection(model: "model-a", reasoningEffort: "high")
        await model.submit()
        let original = try XCTUnwrap(model.request)
        model.modelSelection = CodexDraftModelSelection(model: "model-b", reasoningEffort: "low")
        model.prompt = "Changed locally after submission"
        let restored = creation(network, root: root)
        XCTAssertEqual(restored.request?.selection, CodexModelSelection(model: "model-a", reasoningEffort: "high"))
        XCTAssertEqual(restored.prompt, original.prompt)
        XCTAssertEqual(restored.modelSelection?.selection, original.selection)
        await restored.checkStatus()
        await network.configure(post: .completed, receipt: .completed)
        await restored.retryOriginal()
        let posts = await network.posts
        XCTAssertEqual(posts, [original, original])
    }

    @MainActor
    func testLegacySavedCreationRestoresWithoutModelOrDraftFieldsAndDoesNotRepost() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .timeout, receipt: .unknown)
        let model = creation(network, root: root)
        model.prompt = "Legacy request"
        await model.submit()
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        legacy.removeValue(forKey: "draft")
        try JSONSerialization.data(withJSONObject: legacy).write(to: file)
        let restored = creation(network, root: root)
        XCTAssertEqual(restored.request, model.request)
        XCTAssertNil(restored.modelSelection)
        XCTAssertFalse(restored.canSubmit)
        await restored.checkStatus()
        let posts = await network.posts
        XCTAssertEqual(posts.count, 1)
    }

    @MainActor
    func testLateProjectListCannotReplaceAnotherHostAndMismatchedResponsesAreRejected() async {
        let network = ProjectNetworkFixture()
        await network.suspendProjects(host: "remote")
        let model = CodexProjectListModel(network: network)
        let old = Task { await model.load(from: server, hostId: "remote") }
        await network.waitForProjectRead()
        await model.load(from: server, hostId: "local")
        await network.finishProjectRead()
        await old.value
        XCTAssertEqual(model.hostId, "local")
        XCTAssertEqual(model.projects.first?.id, "project-local")

        await network.returnWrongProjectHost()
        await model.load(from: server, hostId: "local")
        XCTAssertTrue(model.projects.isEmpty)
        XCTAssertNotNil(model.error)
    }

    @MainActor
    func testLatePaginationCannotAppendChatsFromPreviousProject() async {
        let network = ProjectNetworkFixture()
        let model = CodexThreadListModel(network: network)
        await model.load(from: server, hostId: "local", projectId: "first", search: "", debounce: false)
        await network.suspendPagination()
        let loading = Task { await model.loadMore() }
        await network.waitForPaginationRead()
        await model.load(from: server, hostId: "local", projectId: "second", search: "", debounce: false)
        await network.finishPaginationRead()
        await loading.value
        XCTAssertEqual(model.threads.map(\.id), ["second-chat"])
        XCTAssertEqual(model.projectId, "second")
        XCTAssertFalse(model.isLoadingMore)
    }

    @MainActor
    func testLostCreateResponseSurvivesRestartAndOnlyReadsOriginalRequest() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .timeout, receipt: .unknown)
        let model = creation(network, root: root)
        model.prompt = "Remember this first message"
        model.title = "Test project chat"
        await model.submit()
        let original = try XCTUnwrap(model.request)
        XCTAssertNil(model.createdThread)
        XCTAssertFalse(model.canSubmit)
        XCTAssertFalse(model.canEditFailedAttempt, "An ambiguous timeout must not enable a replacement creation.")
        let restored = creation(network, root: root)
        XCTAssertEqual(restored.request, original)
        XCTAssertEqual(restored.prompt, "Remember this first message")

        let anotherHost = creation(network, root: root, host: "remote")
        let anotherProject = creation(network, root: root, projectID: "another-project")
        let anotherServer = creation(network, root: root, base: URL(string: "http://other.invalid/device/paired")!)
        XCTAssertNil(anotherHost.request)
        XCTAssertNil(anotherProject.request)
        XCTAssertNil(anotherServer.request)

        await network.configure(post: .completed, receipt: .completed)
        await restored.checkStatus()
        await restored.checkStatus()
        let posts = await network.posts
        XCTAssertEqual(posts, [original], "Restoring and checking must not repeat a create POST.")
        XCTAssertEqual(restored.createdThread?.id, "created-chat")
        restored.acknowledgeOpenedChat()
        XCTAssertNil(creation(network, root: root).request)
    }

    @MainActor
    func testDoubleTapAndStatusReadCannotRaceAnInFlightCreate() async {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .suspended, receipt: .missing)
        let model = creation(network, root: root)
        model.prompt = "   "
        await model.submit()
        let emptyCount = await network.posts.count
        XCTAssertEqual(emptyCount, 0, "Creating a chat requires an explicit first message.")
        model.prompt = "Start once"
        let creating = Task { await model.submit() }
        await network.waitForPost()
        await model.submit()
        await model.checkStatus()
        let posts = await network.posts
        let reads = await network.receiptReadCount
        XCTAssertEqual(posts.count, 1)
        XCTAssertEqual(reads, 0, "A GET must not outrun an unresolved POST and offer a duplicate retry.")
        await network.finishPost()
        await creating.value
        XCTAssertEqual(model.createdThread?.id, "created-chat")
    }

    @MainActor
    func testConfirmedMissingRetryKeepsOriginalIDPromptAndProject() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .timeout, receipt: .missing)
        let model = creation(network, root: root)
        model.title = "Original title"
        model.prompt = "Original first message"
        await model.submit()
        XCTAssertTrue(model.canRetryOriginal)
        let original = try XCTUnwrap(model.request)
        model.title = "Changed title"
        model.prompt = "Changed message"
        await network.configure(post: .completed, receipt: .completed)
        await model.retryOriginal()
        let posts = await network.posts
        XCTAssertEqual(posts, [original, original])
        XCTAssertEqual(model.createdThread?.id, "created-chat")
    }

    @MainActor
    func testCreationReceiptFromAnotherTargetCannotSelectAChat() async {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .wrongTarget, receipt: .wrongTarget)
        let model = creation(network, root: root)
        model.prompt = "A message for this project"
        await model.submit()
        XCTAssertNil(model.createdThread)
        XCTAssertNotNil(model.error)
        XCTAssertNotNil(model.request)
        XCTAssertFalse(model.canSubmit)
    }

    @MainActor
    func testConfirmedFailureRequiresExplicitEditingAndAnotherStartBeforeANewRequest() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .failed, receipt: .unknown)
        let model = creation(network, root: root)
        model.prompt = "First attempt"
        await model.submit()
        let originalID = try XCTUnwrap(model.request?.id)
        XCTAssertTrue(model.canEditFailedAttempt)
        model.editFailedAttempt()
        let postsBeforeAnotherStart = await network.posts.count
        XCTAssertEqual(postsBeforeAnotherStart, 1, "Editing must not send a replacement request.")
        XCTAssertNil(model.request)
        XCTAssertNil(creation(network, root: root).request)
        model.prompt = "Revised message"
        await network.configure(post: .completed, receipt: .completed)
        await model.submit()
        let posts = await network.posts
        XCTAssertEqual(posts.count, 2)
        XCTAssertNotEqual(posts[1].id, originalID)
        XCTAssertEqual(posts[1].prompt, "Revised message")
    }

    @MainActor
    func testFailedEditPreservesOriginalRequestWhenAtomicSaveFails() async throws {
        let root = temporaryDirectory()
        let backup = root.appendingPathExtension("backup")
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: backup) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .failed, receipt: .unknown)
        let model = creation(network, root: root)
        model.prompt = "Keep my request"
        await model.submit()
        let requestID = try XCTUnwrap(model.request?.id)
        let file = root.appendingPathComponent(model.draftID + ".json")
        let originalBytes = try Data(contentsOf: file)
        try FileManager.default.moveItem(at: root, to: backup)
        try Data("blocks directory creation".utf8).write(to: root)
        model.editFailedAttempt()
        XCTAssertEqual(model.request?.id, requestID)
        XCTAssertNotNil(model.storageError)
        try FileManager.default.removeItem(at: root)
        try FileManager.default.moveItem(at: backup, to: root)
        XCTAssertEqual(try Data(contentsOf: file), originalBytes)
        XCTAssertEqual(creation(network, root: root).request?.id, requestID)
    }

    @MainActor
    func testLegacyDraftRecoveryRequiresExactOriginalDestinationWithoutSending() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .failed, receipt: .unknown)
        let model = creation(network, root: root)
        model.prompt = "Old request"
        await model.submit()
        let file = root.appendingPathComponent(model.draftID + ".json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        object.removeValue(forKey: "destination")
        let bytes = try JSONSerialization.data(withJSONObject: object)
        try bytes.write(to: file)
        let summary = try XCTUnwrap(CodexProjectCreationModel.savedDrafts(storageRoot: root).first)
        XCTAssertThrowsError(try CodexProjectCreationModel.recoverLegacyDraft(summary, project: model.project, host: model.host,
            serverURL: URL(string: "http://wrong.invalid")!, storageRoot: root))
        let recovered = try CodexProjectCreationModel.recoverLegacyDraft(summary, project: model.project, host: model.host,
            serverURL: model.serverURL, storageRoot: root)
        XCTAssertEqual(recovered.request?.id, model.request?.id)
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        let count = await network.posts.count
        XCTAssertEqual(count, 1)
    }

    private var server: URL { URL(string: "http://test.invalid/device/paired")! }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    @MainActor
    func testDestinationChangeKeepsDraftIdentityAndDoesNotLoadOrOverwriteAnotherDraft() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        let first = creation(network, root: root)
        first.prompt = "Carry this requirement"
        first.title = "First draft"
        first.modelSelection = CodexDraftModelSelection(model: "model-a", reasoningEffort: "high")
        let second = creation(network, root: root, projectID: "project-b")
        second.prompt = "Unrelated B draft"
        let originalID = first.draftID
        XCTAssertTrue(first.changeDestination(project: second.project, host: second.host, serverURL: second.serverURL))
        XCTAssertEqual(first.draftID, originalID)
        XCTAssertEqual(first.prompt, "Carry this requirement")
        XCTAssertEqual(first.title, "First draft")
        XCTAssertTrue(first.destinationNeedsValidation)
        XCTAssertFalse(first.canSubmit)
        let reopened = CodexProjectCreationModel(project: second.project, host: second.host, serverURL: server,
            network: network, storageRoot: root, draftID: originalID)
        XCTAssertEqual(reopened.project.id, second.project.id)
        XCTAssertEqual(reopened.prompt, first.prompt)
        XCTAssertEqual(creation(network, root: root, projectID: "project-b").prompt, "Unrelated B draft")
    }

    @MainActor
    func testSubmittedDraftCannotBeRetargeted() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .timeout, receipt: .unknown)
        let first = creation(network, root: root)
        first.prompt = "Immutable requirement"
        await first.submit()
        let original = first.request
        let second = creation(network, root: root, projectID: "another")
        XCTAssertFalse(first.changeDestination(project: second.project, host: second.host, serverURL: second.serverURL))
        XCTAssertEqual(first.request, original)
        XCTAssertEqual(first.project.id, original?.projectId)
    }

    @MainActor
    func testDraftListKeepsIndependentTasksAndUnknownCreationDiscoverableAfterRestart() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .timeout, receipt: .unknown)
        let old = creation(network, root: root)
        old.prompt = "Unknown original task"
        await old.submit()
        let new = CodexProjectCreationModel(project: old.project, host: old.host, serverURL: old.serverURL,
            network: network, storageRoot: root, draftID: UUID().uuidString.lowercased())
        new.prompt = "Independent task in the same project"
        let entries = CodexProjectCreationModel.savedDrafts(storageRoot: root)
        XCTAssertEqual(entries.count, 2)
        let original = try XCTUnwrap(entries.first { $0.id == old.draftID })
        XCTAssertEqual(original.state, "unknown")
        XCTAssertEqual(original.requestID, old.request?.id)
        XCTAssertEqual(original.destination?.project.id, old.project.id)
        let reopened = CodexProjectCreationModel(project: old.project, host: old.host, serverURL: old.serverURL,
            network: network, storageRoot: root, draftID: original.id)
        XCTAssertEqual(reopened.request, old.request)
        XCTAssertEqual(reopened.prompt, "Unknown original task")
        XCTAssertEqual(entries.first { $0.id == new.draftID }?.prompt, new.prompt)
        let posts = await network.posts
        XCTAssertEqual(posts.count, 1)
    }

    @MainActor
    func testInvalidCreationVersionsProtectBytesAndKeepRecoveryIndex() async throws {
        for version in [0, -1] {
            for hasRequest in [false, true] {
                let root = temporaryDirectory()
                defer { try? FileManager.default.removeItem(at: root) }
                let network = ProjectNetworkFixture()
                await network.configure(post: .timeout, receipt: .unknown)
                let original = creation(network, root: root)
                original.title = "Original title"
                original.prompt = "Keep the original requirement"
                original.modelSelection = CodexDraftModelSelection(model: "model-a", reasoningEffort: "high")
                if hasRequest { await original.submit() }
                let path = root.appendingPathComponent(original.draftID).appendingPathExtension("json")
                var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
                saved["version"] = version
                let bytes = try JSONSerialization.data(withJSONObject: saved, options: .sortedKeys)
                try bytes.write(to: path)
                let independent = creation(network, root: root, projectID: "another-project")
                independent.prompt = "Independent usable draft"
                let postsBeforeRecovery = await network.posts
                let readsBeforeRecovery = await network.receiptReadCount

                let entries = CodexProjectCreationModel.savedDrafts(storageRoot: root)
                XCTAssertEqual(entries.count, 2)
                let protected = try XCTUnwrap(entries.first { $0.id == original.draftID })
                XCTAssertEqual(protected.state, "unreadable")
                XCTAssertNotNil(protected.recoveryError)
                XCTAssertNil(protected.destination)
                XCTAssertNil(protected.requestID)
                XCTAssertEqual(entries.first { $0.id == independent.draftID }?.prompt, independent.prompt)

                let restored = creation(network, root: root)
                XCTAssertNotNil(restored.storageError)
                XCTAssertNil(restored.request)
                XCTAssertNil(restored.receipt)
                XCTAssertTrue(restored.prompt.isEmpty)
                XCTAssertTrue(restored.title.isEmpty)
                XCTAssertNil(restored.modelSelection)
                restored.title = "New local title"
                restored.prompt = "New local input must not overwrite the original"
                XCTAssertFalse(restored.canSubmit)
                XCTAssertFalse(restored.changeDestination(project: independent.project, host: independent.host, serverURL: independent.serverURL))
                await restored.submit()
                await restored.checkStatus()
                await restored.retryOriginal()
                await restored.retryCreation()
                XCTAssertFalse(restored.acknowledgeOpenedChat())
                XCTAssertEqual(try Data(contentsOf: path), bytes)
                let postsAfterRecovery = await network.posts
                let readsAfterRecovery = await network.receiptReadCount
                XCTAssertEqual(postsAfterRecovery, postsBeforeRecovery)
                XCTAssertEqual(readsAfterRecovery, readsBeforeRecovery)
                let reopened = CodexProjectCreationModel.savedDrafts(storageRoot: root)
                XCTAssertEqual(reopened.first { $0.id == original.draftID }?.state, "unreadable")
                XCTAssertNotNil(reopened.first { $0.id == original.draftID }?.recoveryError)
            }
        }
    }

    @MainActor
    func testSupportedAndLegacyCreationVersionsRestoreOriginalRequestAndIndex() async throws {
        for version in [nil, 1, 2] as [Int?] {
            let root = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let network = ProjectNetworkFixture()
            await network.configure(post: .timeout, receipt: .unknown)
            let original = creation(network, root: root)
            original.prompt = "Existing supported request"
            await original.submit()
            let request = try XCTUnwrap(original.request)
            let path = root.appendingPathComponent(original.draftID).appendingPathExtension("json")
            var saved = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
            saved["version"] = version
            try JSONSerialization.data(withJSONObject: saved, options: .sortedKeys).write(to: path)
            let restored = creation(network, root: root)
            XCTAssertNil(restored.storageError)
            XCTAssertEqual(restored.request, request)
            XCTAssertEqual(restored.prompt, request.prompt)
            let summary = try XCTUnwrap(CodexProjectCreationModel.savedDrafts(storageRoot: root).first)
            XCTAssertEqual(summary.requestID, request.id)
            XCTAssertEqual(summary.state, "unknown")
            XCTAssertNil(summary.recoveryError)
        }
    }

    @MainActor
    func testFirstMessageImagesStayImmutableAcrossTimeoutRestartAndExplicitRetry() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        await network.configure(post: .timeout, receipt: .missing)
        let seed = creation(network, root: root)
        var project = seed.project
        project.supportsFirstMessageAttachments = true
        let id = UUID().uuidString.lowercased()
        let model = CodexProjectCreationModel(project: project, host: seed.host, serverURL: server,
            network: network, storageRoot: root, draftID: id)
        model.prompt = "Implement this drawing"
        let bytes = Data([137, 80, 78, 71, 1, 2, 3])
        try model.addImage(CodexImportedImage(data: bytes, name: "Canvas.png", mimeType: "image/png"))
        await model.submit()
        let original = try XCTUnwrap(model.request)
        model.removeAttachment(original.attachments[0].id)
        XCTAssertEqual(model.attachments.count, 1, "Submitted attachments cannot change.")
        let restored = CodexProjectCreationModel(project: project, host: seed.host, serverURL: server,
            network: network, storageRoot: root, draftID: id)
        XCTAssertEqual(restored.attachments[0].imageData, bytes)
        XCTAssertEqual(restored.request, original)
        await restored.checkStatus()
        await network.configure(post: .completed, receipt: .completed)
        await restored.retryOriginal()
        let posts = await network.posts
        XCTAssertEqual(posts, [original, original])
    }

    @MainActor
    func testUnsupportedImageDestinationKeepsDraftButBlocksCreation() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ProjectNetworkFixture()
        let seed = creation(network, root: root)
        var project = seed.project
        project.supportsFirstMessageAttachments = true
        let model = CodexProjectCreationModel(project: project, host: seed.host, serverURL: server,
            network: network, storageRoot: root, draftID: UUID().uuidString.lowercased())
        try model.addImage(CodexImportedImage(data: Data([1, 2, 3]), name: "Snapshot.png", mimeType: "image/png"))
        XCTAssertTrue(model.canSubmit, "An image-only first requirement is complete input.")
        XCTAssertTrue(model.changeDestination(project: seed.project, host: seed.host, serverURL: server))
        XCTAssertFalse(model.canSubmit)
        XCTAssertEqual(model.attachments.count, 1)
        let legacy = try JSONDecoder().decode(CodexCreateChatRequest.self, from: Data(#"{"id":"id","hostId":"local","projectId":"project","prompt":"legacy"}"#.utf8))
        XCTAssertTrue(legacy.attachments.isEmpty)
    }

    @MainActor
    private func creation(_ network: ProjectNetworkFixture, root: URL, host: String = "local", projectID: String = "project-local", base: URL? = nil) -> CodexProjectCreationModel {
        CodexProjectCreationModel(
            project: CodexProject(id: projectID, name: "Project", path: "/project", canCreate: true, reason: nil),
            host: CodexHost(id: host, name: host, kind: host == "local" ? "local" : "remote", configured: true, available: true, reason: nil),
            serverURL: base ?? server, network: network, storageRoot: root)
    }
}

private actor CreationSleepGate {
    private var continuation: CheckedContinuation<Void, Error>?
    private var enteredWaiter: CheckedContinuation<Void, Never>?

    func sleep(_ interval: TimeInterval) async throws {
        try await withCheckedThrowingContinuation {
            continuation = $0
            enteredWaiter?.resume()
            enteredWaiter = nil
        }
    }

    func waitUntilSleeping() async {
        if continuation != nil { return }
        await withCheckedContinuation { enteredWaiter = $0 }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

private actor ProjectNetworkFixture: CodexProjectNetworking, CodexThreadListNetworking {
    enum PostMode { case completed, timeout, suspended, wrongTarget, failed, validationRejected, approvalTimeout }
    enum ReceiptMode { case completed, unknown, missing, unavailable, wrongTarget, approvalTimeout, retryCompleted, retryUnknown, retryExhausted, unknownWithRetryFlag, nativeCreatedUnconfirmed }
    enum RetryMode { case suspended, completed, timeout, admissionFailed, preflightFailed, exhausted, wrongTarget }
    struct RetryCall: Equatable { let original: CodexCreateChatRequest; let attemptId: String }
    private var retryMode = RetryMode.completed
    private(set) var retryCalls: [RetryCall] = []
    private var retryWaiter: CheckedContinuation<Void, Never>?
    private var suspendedRetry: CheckedContinuation<CodexChatCreationReceipt, Error>?
    private var postMode = PostMode.completed
    private var receiptMode = ReceiptMode.completed
    private(set) var posts: [CodexCreateChatRequest] = []
    private(set) var receiptReadCount = 0
    private(set) var receiptRequests: [CodexCreateChatRequest] = []
    private var postWaiter: CheckedContinuation<Void, Never>?
    private var suspendedPost: CheckedContinuation<CodexChatCreationReceipt, Error>?
    private var suspendedProjectHost: String?
    private var projectWaiter: CheckedContinuation<Void, Never>?
    private var projectRead: CheckedContinuation<CodexProjectList, Never>?
    private var wrongProjectHost = false
    private var shouldSuspendPagination = false
    private var paginationWaiter: CheckedContinuation<Void, Never>?
    private var paginationRead: CheckedContinuation<CodexThreadPage, Never>?

    func configure(post: PostMode, receipt: ReceiptMode) { postMode = post; receiptMode = receipt }
    func configureRetry(_ mode: RetryMode) { retryMode = mode }
    func waitForRetry() async {
        if suspendedRetry != nil { return }
        await withCheckedContinuation { retryWaiter = $0 }
    }
    func finishRetry() {
        guard let call = retryCalls.last else { return }
        suspendedRetry?.resume(returning: secondAttemptReceipt(call.original, state: .completed))
        suspendedRetry = nil
    }
    func suspendProjects(host: String) { suspendedProjectHost = host }
    func returnWrongProjectHost() { wrongProjectHost = true }
    func suspendPagination() { shouldSuspendPagination = true }

    func waitForPost() async {
        if suspendedPost != nil { return }
        await withCheckedContinuation { postWaiter = $0 }
    }

    func finishPost() {
        guard let request = posts.last else { return }
        suspendedPost?.resume(returning: receipt(request, state: .completed))
        suspendedPost = nil
    }

    func waitForProjectRead() async {
        if projectRead != nil { return }
        await withCheckedContinuation { projectWaiter = $0 }
    }

    func finishProjectRead() {
        projectRead?.resume(returning: projectList(suspendedProjectHost ?? "remote"))
        projectRead = nil
    }

    func waitForPaginationRead() async {
        if paginationRead != nil { return }
        await withCheckedContinuation { paginationWaiter = $0 }
    }

    func finishPaginationRead() {
        paginationRead?.resume(returning: CodexThreadPage(threads: [thread("old-page-chat")], nextCursor: nil))
        paginationRead = nil
    }

    func codexProjects(from serverURL: URL, hostId: String) async throws -> CodexProjectList {
        if hostId == suspendedProjectHost {
            return await withCheckedContinuation {
                projectRead = $0
                projectWaiter?.resume()
                projectWaiter = nil
            }
        }
        return projectList(wrongProjectHost ? "wrong-host" : hostId)
    }

    func codexThreads(from serverURL: URL, hostId: String, search: String, cursor: String?) async throws -> CodexThreadPage {
        CodexThreadPage(threads: [thread("all-chat")], nextCursor: nil)
    }

    func codexProjectThreads(from serverURL: URL, hostId: String, projectId: String, search: String, cursor: String?) async throws -> CodexThreadPage {
        if cursor != nil && shouldSuspendPagination {
            return await withCheckedContinuation {
                paginationRead = $0
                paginationWaiter?.resume()
                paginationWaiter = nil
            }
        }
        return CodexThreadPage(threads: [thread("\(projectId)-chat")], nextCursor: "next")
    }

    func createCodexChat(_ body: CodexCreateChatRequest, from serverURL: URL) async throws -> CodexChatCreationReceipt {
        posts.append(body)
        switch postMode {
        case .completed: return receipt(body, state: .completed)
        case .wrongTarget: return receipt(body, state: .completed, wrongHost: true)
        case .failed: return receipt(body, state: .failed)
        case .approvalTimeout: return approvalTimeoutReceipt(body)
        case .timeout: throw URLError(.timedOut)
        case .validationRejected:
            let body = Data(#"{"code":"unsupported_model","error":"The selected model is not available on this host."}"#.utf8)
            throw NetworkService.creationRejection(statusCode: 400, data: body)!
        case .suspended:
            return try await withCheckedThrowingContinuation {
                suspendedPost = $0
                postWaiter?.resume()
                postWaiter = nil
            }
        }
    }

    func codexChatCreation(_ body: CodexCreateChatRequest, from serverURL: URL) async throws -> CodexChatCreationReceipt {
        receiptReadCount += 1
        receiptRequests.append(body)
        switch receiptMode {
        case .completed: return receipt(body, state: .completed)
        case .unknown: return receipt(body, state: .unknown)
        case .nativeCreatedUnconfirmed:
            var result = CodexChatCreationReceipt(id: body.id, hostId: body.hostId, projectId: body.projectId,
                                                 state: .unknown, thread: thread("native-created-chat"), error: nil, notice: nil)
            result.creationMethod = "native"
            result.canRetry = false
            return result
        case .approvalTimeout: return approvalTimeoutReceipt(body)
        case .retryCompleted: return secondAttemptReceipt(body, state: .completed)
        case .retryUnknown: return secondAttemptReceipt(body, state: .unknown)
        case .retryExhausted: return secondAttemptReceipt(body, state: .failed)
        case .unknownWithRetryFlag:
            var result = receipt(body, state: .unknown)
            result.attemptId = "attempt-1"
            result.attemptNumber = 1
            result.canRetry = true
            result.failureCode = "approval_review_timeout"
            return result
        case .wrongTarget: return receipt(body, state: .completed, wrongHost: true)
        case .missing: throw NetworkService.NetworkError.server(statusCode: 404, message: "Request not found")
        case .unavailable: throw URLError(.cannotConnectToHost)
        }
    }

    func retryCodexChatCreation(_ original: CodexCreateChatRequest, attemptId: String, from serverURL: URL) async throws -> CodexChatCreationReceipt {
        retryCalls.append(RetryCall(original: original, attemptId: attemptId))
        switch retryMode {
        case .completed: return secondAttemptReceipt(original, state: .completed)
        case .exhausted: return secondAttemptReceipt(original, state: .failed)
        case .wrongTarget: return secondAttemptReceipt(original, state: .completed, wrongHost: true)
        case .timeout: throw URLError(.timedOut)
        case .admissionFailed:
            throw NetworkService.NetworkError.server(statusCode: 503, message: "Retry could not be saved before dispatch")
        case .preflightFailed:
            var result = secondAttemptReceipt(original, state: .failed)
            result.failureCode = nil
            return result
        case .suspended:
            return try await withCheckedThrowingContinuation {
                suspendedRetry = $0
                retryWaiter?.resume()
                retryWaiter = nil
            }
        }
    }

    private func approvalTimeoutReceipt(_ request: CodexCreateChatRequest) -> CodexChatCreationReceipt {
        var result = receipt(request, state: .failed)
        result.attemptId = "attempt-1"
        result.attemptNumber = 1
        result.canRetry = true
        result.failureCode = "approval_review_timeout"
        return result
    }

    private func secondAttemptReceipt(_ request: CodexCreateChatRequest, state: CodexChatCreationState, wrongHost: Bool = false) -> CodexChatCreationReceipt {
        var result = receipt(request, state: state, wrongHost: wrongHost)
        result.attemptId = "attempt-2"
        result.attemptNumber = 2
        result.canRetry = false
        result.failureCode = state == .failed ? "approval_review_timeout" : nil
        return result
    }

    private func receipt(_ request: CodexCreateChatRequest, state: CodexChatCreationState, wrongHost: Bool = false) -> CodexChatCreationReceipt {
        CodexChatCreationReceipt(id: request.id, hostId: wrongHost ? "wrong-host" : request.hostId,
                                 projectId: request.projectId, state: state,
                                 thread: state == .completed ? thread("created-chat") : nil, error: nil, notice: nil)
    }

    private func projectList(_ host: String) -> CodexProjectList {
        CodexProjectList(hostId: host, projects: [CodexProject(id: "project-\(host)", name: host, path: "/project", canCreate: true, reason: nil)])
    }

    private func thread(_ id: String) -> CodexThread { CodexThread(id: id, title: id, cwd: "/project", updatedAt: 1) }
}
