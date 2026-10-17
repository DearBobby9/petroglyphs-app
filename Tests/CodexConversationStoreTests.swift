import XCTest
import UIKit

final class CodexConversationStoreTests: XCTestCase {
    @MainActor
    func testDraftsAndImageSnapshotsSurviveRestartWithoutCrossingTargets() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ConversationNetworkFixture()
        let first = target(host: "local")
        let remote = target(host: "remote-control:mini")
        let otherServer = target(host: "local", base: "http://second.invalid/device/test-pair")
        let store = CodexConversationStore(network: network, storageRoot: root)
        store.setDraftText("Local draft 草稿", for: first)
        let selection = CodexDraftModelSelection(model: "model-a", reasoningEffort: "high")
        store.setDraftModelSelection(selection, for: first)
        store.setDraftText("Remote draft", for: remote)
        store.setDraftText("Other server", for: otherServer)
        let bytes = imageBytes()
        try store.addImage(CodexImportedImage(data: bytes, name: "Snapshot.png", mimeType: "image/png"), for: first)

        let restored = CodexConversationStore(network: network, storageRoot: root)
        XCTAssertEqual(restored.session(for: first).draft.text, "Local draft 草稿")
        XCTAssertEqual(restored.session(for: first).draft.modelSelection, selection)
        XCTAssertNil(restored.session(for: remote).draft.modelSelection)
        XCTAssertEqual(restored.session(for: remote).draft.text, "Remote draft")
        XCTAssertEqual(restored.session(for: otherServer).draft.text, "Other server")
        XCTAssertTrue(restored.session(for: remote).draft.attachments.isEmpty)
        let attachment = try XCTUnwrap(restored.session(for: first).draft.attachments.first)
        let restoredBytes = try await restored.imageData(attachment.messageAttachment, for: first)
        XCTAssertEqual(restoredBytes, bytes)
    }

    @MainActor
    func testLostSendResponseIsReconciledAndNeverRepostedAcrossRestart() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ConversationNetworkFixture()
        await network.configure(post: .timeout, receipt: .accepted)
        let destination = target()
        let store = CodexConversationStore(network: network, storageRoot: root)
        store.setDraftText("Sent once", for: destination)
        await store.sendDraft(to: destination)
        let original = try XCTUnwrap(store.session(for: destination).outgoing.first)
        XCTAssertEqual(original.state, .queued)
        XCTAssertFalse(original.canRetry)
        XCTAssertTrue(store.session(for: destination).draft.isEmpty)

        let restored = CodexConversationStore(network: network, storageRoot: root)
        await restored.refresh(for: destination)
        await restored.refresh(for: destination)
        let requests = await network.requests
        XCTAssertEqual(requests.count, 1, "Status reads must never replay a POST.")
        XCTAssertEqual(restored.session(for: destination).outgoing.first?.id, original.id)
        XCTAssertEqual(restored.session(for: destination).outgoing.first?.state, .queued)
    }

    @MainActor
    func testConfirmedUnacceptedMessageRetriesTheSameImmutableRequest() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ConversationNetworkFixture()
        await network.configure(post: .timeout, receipt: .missing)
        let destination = target()
        let store = CodexConversationStore(network: network, storageRoot: root)
        store.setDraftText("Original text", for: destination)
        let originalSelection = CodexDraftModelSelection(model: "model-a", reasoningEffort: "high")
        store.setDraftModelSelection(originalSelection, for: destination)
        try store.addImage(CodexImportedImage(data: imageBytes(), name: "Image.png", mimeType: "image/png"), for: destination)
        await store.sendDraft(to: destination)
        let failed = try XCTUnwrap(store.session(for: destination).outgoing.first)
        XCTAssertTrue(failed.canRetry)
        XCTAssertEqual(failed.selection, originalSelection.selection)
        let restored = CodexConversationStore(network: network, storageRoot: root)
        XCTAssertEqual(restored.session(for: destination).draft.modelSelection, originalSelection)
        let nextSelection = CodexDraftModelSelection(model: "model-b", reasoningEffort: "low")
        restored.setDraftText("A separate draft", for: destination)
        restored.setDraftModelSelection(nextSelection, for: destination)
        await network.configure(post: .accepted, receipt: .accepted)
        await restored.retryUnaccepted(failed.id, for: destination)
        let requests = await network.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].id, requests[1].id)
        XCTAssertEqual(requests[0].text, requests[1].text)
        XCTAssertEqual(requests[0].attachments.first?.dataBase64, requests[1].attachments.first?.dataBase64)
        XCTAssertEqual(requests[0].selection, originalSelection.selection)
        XCTAssertEqual(requests[1].selection, originalSelection.selection)
        XCTAssertEqual(restored.session(for: destination).draft.text, "A separate draft")
        XCTAssertEqual(restored.session(for: destination).draft.modelSelection, nextSelection)
        XCTAssertFalse(restored.session(for: destination).outgoing[0].canRetry)
    }

    @MainActor
    func testHistoryRefreshCannotMarkAnInFlightPostUnaccepted() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ConversationNetworkFixture()
        await network.configure(post: .suspended, receipt: .missing)
        let destination = target()
        let store = CodexConversationStore(network: network, storageRoot: root)
        store.setDraftText("In flight", for: destination)
        let sending = Task { await store.sendDraft(to: destination) }
        await network.waitForRequest()
        await store.refresh(for: destination)
        let readCount = await network.receiptReadCount
        XCTAssertEqual(readCount, 0, "A status read can outrun a still-running POST.")
        XCTAssertEqual(store.session(for: destination).outgoing.first?.state, .dispatching)
        XCTAssertFalse(store.session(for: destination).outgoing[0].canRetry)
        await network.finishSuspendedPost()
        await sending.value
        XCTAssertEqual(store.session(for: destination).outgoing.first?.state, .queued)
    }

    @MainActor
    func testNativeHistoryReplacesOptimisticMessageAndRejectsAnotherTarget() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ConversationNetworkFixture()
        let destination = target()
        let store = CodexConversationStore(network: network, storageRoot: root)
        store.setDraftText("Same text", for: destination)
        await store.sendDraft(to: destination)
        let id = try XCTUnwrap(store.session(for: destination).outgoing.first?.id)
        let native = CodexConversationMessage(id: "native-message", turnId: "native-turn", clientMessageId: id,
                                              role: "user", text: "Same text", phase: "user", createdAt: Date(), state: .queued, attachments: [])
        await network.setPage(messages: [native], host: destination.host.id)
        await store.refresh(for: destination)
        XCTAssertEqual(store.session(for: destination).messages.count, 1)
        XCTAssertEqual(store.session(for: destination).messages[0].displayID, "user:\(id)")
        await network.setPage(messages: [], host: "another-host")
        await store.refresh(for: destination)
        XCTAssertEqual(store.session(for: destination).messages.count, 1)
        XCTAssertNotNil(store.session(for: destination).error)
    }

    @MainActor
    func testCanvasSendLeavesComposerDraftAndPreservesPNGBytes() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ConversationNetworkFixture()
        let destination = target()
        let store = CodexConversationStore(network: network, storageRoot: root)
        store.setDraftText("Keep writing", for: destination)
        let selection = CodexDraftModelSelection(model: "model-a", reasoningEffort: "high")
        store.setDraftModelSelection(selection, for: destination)
        let bytes = imageBytes()
        let accepted = try await store.sendDrawing(bytes, to: destination)
        XCTAssertTrue(accepted)
        XCTAssertEqual(store.session(for: destination).draft.text, "Keep writing")
        XCTAssertEqual(store.session(for: destination).draft.modelSelection, selection)
        let requests = await network.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertTrue(request.text.isEmpty)
        XCTAssertEqual(request.attachments.first?.mimeType, "image/png")
        XCTAssertEqual(request.attachments.first?.dataBase64, bytes.base64EncodedString())
        XCTAssertEqual(request.selection, selection.selection)
    }

    @MainActor
    func testTextOnlyModelRejectsDraftImagesAndCanvasBeforeQueueing() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ConversationNetworkFixture()
        await network.setModelInputModalities(["text"])
        let destination = target()
        let modelSettings = CodexModelSettingsModel(network: network, now: { ConversationNetworkFixture.modelObservedAt })
        await modelSettings.load(from: destination.serverURL, hostId: destination.host.id, threadId: destination.thread.id)
        let store = CodexConversationStore(network: network, storageRoot: root)
        store.setDraftText("Keep the text and image", for: destination)
        store.setDraftModelSelection(CodexDraftModelSelection(model: "model-a", reasoningEffort: "high"), for: destination)
        let bytes = imageBytes()
        try store.addImage(CodexImportedImage(data: bytes, name: "Image.png", mimeType: "image/png"), for: destination)
        let draft = store.session(for: destination).draft
        let directory = root.appendingPathComponent(CodexConversationKey(destination).storageID)
        let filesBefore = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()

        await store.sendDraft(to: destination, modelSettings: modelSettings)
        XCTAssertEqual(store.session(for: destination).draft, draft)
        XCTAssertTrue(store.session(for: destination).draftError?.contains("images") == true)
        do {
            let sent = try await store.sendDrawing(bytes, to: destination, modelSettings: modelSettings)
            XCTAssertFalse(sent, "A text-only model cannot accept a canvas image.")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("images"))
        }
        XCTAssertEqual(store.session(for: destination).draft, draft)
        XCTAssertTrue(store.session(for: destination).outgoing.isEmpty)
        let blockedRequests = await network.requests
        XCTAssertTrue(blockedRequests.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted(), filesBefore,
            "Reject a canvas send before creating another image file.")

        store.removeAttachment(draft.attachments[0].id, for: destination)
        await store.sendDraft(to: destination, modelSettings: modelSettings)
        let requests = await network.requests
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.last?.text, draft.text)
        XCTAssertEqual(requests.last?.selection, draft.modelSelection?.selection)
        XCTAssertTrue(store.session(for: destination).draft.isEmpty)

        store.setDraftModelSelection(nil, for: destination)
        try store.addImage(CodexImportedImage(data: bytes, name: "Follow.png", mimeType: "image/png"), for: destination)
        await store.sendDraft(to: destination, modelSettings: modelSettings)
        let followingRequests = await network.requests
        XCTAssertEqual(followingRequests.count, 2)
        XCTAssertNil(followingRequests.last?.selection)
        XCTAssertEqual(followingRequests.last?.attachments.count, 1, "Follow chat settings must not guess the execution-time model's capabilities.")
    }

    @MainActor
    func testModelPreflightRejectsWrongScopeAndExpiredSelectionWithoutClearingDraft() async {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ConversationNetworkFixture()
        let destination = target()
        var now = ConversationNetworkFixture.modelObservedAt
        let settings = CodexModelSettingsModel(network: network, now: { now })
        await settings.load(from: destination.serverURL, hostId: "another-host", threadId: destination.thread.id)
        let store = CodexConversationStore(network: network, storageRoot: root)
        store.setDraftText("Keep this explicit message", for: destination)
        store.setDraftModelSelection(CodexDraftModelSelection(model: "model-a", reasoningEffort: "high"), for: destination)
        let draft = store.session(for: destination).draft
        await store.sendDraft(to: destination, modelSettings: settings)
        XCTAssertEqual(store.session(for: destination).draft, draft)
        XCTAssertNotNil(store.session(for: destination).draftError)
        XCTAssertTrue(store.session(for: destination).outgoing.isEmpty)

        await settings.load(from: destination.serverURL, hostId: destination.host.id, threadId: destination.thread.id)
        now = now.addingTimeInterval(300)
        await store.sendDraft(to: destination, modelSettings: settings)
        XCTAssertEqual(store.session(for: destination).draft, draft)
        XCTAssertTrue(store.session(for: destination).outgoing.isEmpty)
        let blockedRequests = await network.requests
        XCTAssertTrue(blockedRequests.isEmpty)

        await settings.load(from: destination.serverURL, hostId: "another-host", threadId: destination.thread.id)
        store.setDraftModelSelection(nil, for: destination)
        await store.sendDraft(to: destination, modelSettings: settings)
        let followingRequests = await network.requests
        XCTAssertEqual(followingRequests.count, 1)
        XCTAssertNil(followingRequests.first?.selection)
    }

    @MainActor
    func testIncompleteExplicitSelectionKeepsTextAndRejectsDrawing() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ConversationNetworkFixture()
        let destination = target()
        let store = CodexConversationStore(network: network, storageRoot: root)
        store.setDraftText("Keep this message", for: destination)
        store.setDraftModelSelection(CodexDraftModelSelection(model: "model-a", reasoningEffort: nil), for: destination)
        await store.sendDraft(to: destination)
        XCTAssertEqual(store.session(for: destination).draft.text, "Keep this message")
        XCTAssertNotNil(store.session(for: destination).draftError)
        do {
            _ = try await store.sendDrawing(imageBytes(), to: destination)
            XCTFail("Drawing must also require a complete explicit selection.")
        } catch CodexConversationStore.ConversationError.incompleteModelSelection { }
        XCTAssertTrue(store.session(for: destination).outgoing.isEmpty)
        let requests = await network.requests
        XCTAssertTrue(requests.isEmpty)

        store.setDraftModelSelection(nil, for: destination)
        await store.sendDraft(to: destination)
        let followingRequests = await network.requests
        XCTAssertEqual(followingRequests.count, 1)
        XCTAssertNil(followingRequests[0].selection)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(followingRequests[0])) as? [String: Any])
        XCTAssertNil(encoded["selection"], "Following chat settings must not send an explicit model pair.")
    }

    @MainActor
    func testLegacySavedDraftOutgoingAndReceiptDecodeWithoutModelFields() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = target()
        let directory = root.appendingPathComponent(CodexConversationKey(destination).storageID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let id = "00000000-0000-4000-8000-000000000002"
        let state = """
        {"draft":{"text":"Legacy draft","attachments":[]},"outgoing":[{"id":"\(id)","text":"Legacy message","attachments":[],"createdAt":0,"state":"failed","canRetry":true,"appearedInHistory":false}],"isAtBottom":true}
        """
        let history = """
        {"messages":[],"hasLoadedOlder":false,"receipts":[{"id":"\(id)","hostId":"local","threadId":"\(destination.thread.id)","createdAt":0,"updatedAt":0,"state":"failed","message":{"id":"client:\(id)","clientMessageId":"\(id)","role":"user","text":"Legacy message","phase":"user","state":"failed","attachments":[]}}]}
        """
        try Data(state.utf8).write(to: directory.appendingPathComponent("state.json"))
        try Data(history.utf8).write(to: directory.appendingPathComponent("history.json"))
        let restored = CodexConversationStore(network: ConversationNetworkFixture(), storageRoot: root)
        let session = restored.session(for: destination)
        XCTAssertNil(session.draftError)
        XCTAssertEqual(session.draft.text, "Legacy draft")
        XCTAssertNil(session.draft.modelSelection)
        XCTAssertEqual(session.outgoing.first?.text, "Legacy message")
        XCTAssertNil(session.outgoing.first?.selection)
        let receipt = try XCTUnwrap(restored.receipt(id, for: destination))
        XCTAssertNil(receipt.selection)
        XCTAssertNil(receipt.modelEvidence)
        XCTAssertNil(receipt.modelVerification)
    }

    @MainActor
    func testCreationReceiptMetadataPersistsFromOlderPageWithoutLocalOutgoing() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = target()
        let network = ConversationNetworkFixture()
        let id = UUID().uuidString.lowercased()
        let message = CodexConversationMessage(id: "created-message", turnId: "created-turn", clientMessageId: id,
            role: "user", text: "Start here", phase: "user", createdAt: Date(), state: .completed, attachments: [])
        let receipt = CodexMessageReceipt(id: id, hostId: destination.host.id, threadId: destination.thread.id,
            createdAt: Date(), updatedAt: Date(), state: .completed, turnId: "created-turn", message: message, error: nil, notice: nil,
            selection: CodexModelSelection(model: "requested-model", reasoningEffort: "high"),
            modelEvidence: CodexModelEvidence(model: "actual-model", reasoningEffort: nil,
                reroutes: [CodexModelReroute(fromModel: "requested-model", toModel: "actual-model", reason: "capacity")]),
            modelVerification: "different")
        await network.setPages(latest: numberedMessages(2...2), before: "older", older: [message], olderBefore: nil, olderReceipts: [receipt])
        let store = CodexConversationStore(network: network, storageRoot: root)
        await store.refresh(for: destination)
        XCTAssertNil(store.receipt(message.clientMessageId, for: destination))
        await store.loadOlder(for: destination)
        XCTAssertTrue(store.session(for: destination).outgoing.isEmpty)
        XCTAssertEqual(store.receipt(message.clientMessageId, for: destination), receipt)
        let restored = CodexConversationStore(network: network, storageRoot: root)
        XCTAssertEqual(restored.receipt(message.clientMessageId, for: destination), receipt)
        XCTAssertTrue(restored.session(for: destination).outgoing.isEmpty)
    }

    @MainActor
    func testRefreshAcrossAPageGapResetsTheWindowAndOlderMessagesStayOrdered() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ConversationNetworkFixture()
        let destination = target()
        let store = CodexConversationStore(network: network, storageRoot: root)
        await network.setPages(latest: numberedMessages(51...100), before: "50", older: numberedMessages(1...50), olderBefore: nil)
        await store.refresh(for: destination)
        await store.loadOlder(for: destination)
        XCTAssertEqual(store.session(for: destination).history.map(\.id), (1...100).map { "message-\($0)" })
        XCTAssertNil(store.session(for: destination).beforeCursor)

        await network.setPages(latest: numberedMessages(151...200), before: "150", older: numberedMessages(101...150), olderBefore: "100")
        await store.refresh(for: destination)
        XCTAssertEqual(store.session(for: destination).history.map(\.id), (151...200).map { "message-\($0)" })
        XCTAssertEqual(store.session(for: destination).beforeCursor, "150", "A gap must remain reachable through pagination.")
        await store.loadOlder(for: destination)
        XCTAssertEqual(store.session(for: destination).history.map(\.id), (101...200).map { "message-\($0)" })

        await network.setPages(latest: numberedMessages(176...225), before: "175", older: [], olderBefore: nil)
        await store.refresh(for: destination)
        XCTAssertEqual(store.session(for: destination).history.map(\.id), (101...225).map { "message-\($0)" })
        XCTAssertEqual(store.session(for: destination).beforeCursor, "100", "An overlapping refresh must preserve the oldest loaded cursor.")
    }

    @MainActor
    func testCorruptOrFutureStateSurvivesReadOnlyRefreshAndBlockedSend() async throws {
        for bytes in [Data("broken {".utf8), Data(#"{"version":999,"draft":{"text":"future","attachments":[]},"outgoing":[],"isAtBottom":true}"#.utf8)] {
            let root = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let destination = target()
            let directory = root.appendingPathComponent(CodexConversationKey(destination).storageID)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let path = directory.appendingPathComponent("state.json")
            try bytes.write(to: path)
            let network = ConversationNetworkFixture()
            let store = CodexConversationStore(network: network, storageRoot: root)
            await store.refresh(for: destination)
            XCTAssertEqual(try Data(contentsOf: path), bytes)
            store.setDraftText("New local input", for: destination)
            await store.sendDraft(to: destination)
            XCTAssertEqual(try Data(contentsOf: path), bytes)
            let requests = await network.requests
            XCTAssertTrue(requests.isEmpty, "Unrestored request IDs must stay protected before another send.")
            XCTAssertNotNil(store.session(for: destination).draftError)
            try store.preserveUnreadableState(for: destination)
            let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix("state.json.recovery-") }
            XCTAssertEqual(backups.count, 1)
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), bytes)
            let reopened = CodexConversationStore(network: network, storageRoot: root)
            XCTAssertEqual(reopened.session(for: destination).draft.text, "New local input")
        }
    }

    @MainActor
    func testCorruptHistoryDoesNotPreventIndependentDraftRecoveryOrSaving() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = target()
        let store = CodexConversationStore(network: ConversationNetworkFixture(), storageRoot: root)
        store.setDraftText("Original draft", for: destination)
        let history = root.appendingPathComponent(CodexConversationKey(destination).storageID).appendingPathComponent("history.json")
        try Data("broken history".utf8).write(to: history)
        let restored = CodexConversationStore(network: ConversationNetworkFixture(), storageRoot: root)
        XCTAssertEqual(restored.session(for: destination).draft.text, "Original draft")
        XCTAssertNil(restored.session(for: destination).draftError)
        XCTAssertNotNil(restored.session(for: destination).error)
        restored.setDraftText("Continued editing", for: destination)
        let reopened = CodexConversationStore(network: ConversationNetworkFixture(), storageRoot: root)
        XCTAssertEqual(reopened.session(for: destination).draft.text, "Continued editing")
    }

    @MainActor
    func testInvalidStateVersionsAndDuplicateOutgoingIDsProtectOriginalRequests() async throws {
        let id = "00000000-0000-4000-8000-000000000002"
        let outgoing = #"{"id":"\#(id)","text":"Original request","attachments":[],"createdAt":0,"state":"unknown","canRetry":false,"appearedInHistory":false}"#
        let fixtures = [
            #"{"version":0,"draft":{"text":"Original draft","attachments":[]},"outgoing":[\#(outgoing)],"isAtBottom":true}"#,
            #"{"version":-1,"draft":{"text":"Original draft","attachments":[]},"outgoing":[\#(outgoing)],"isAtBottom":true}"#,
            #"{"version":2,"draft":{"text":"Original draft","attachments":[]},"outgoing":[\#(outgoing),\#(outgoing)],"isAtBottom":true}"#
        ]
        for fixture in fixtures {
            let root = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let destination = target()
            let directory = root.appendingPathComponent(CodexConversationKey(destination).storageID)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let path = directory.appendingPathComponent("state.json")
            let bytes = Data(fixture.utf8)
            try bytes.write(to: path)
            let network = ConversationNetworkFixture()
            let store = CodexConversationStore(network: network, storageRoot: root)
            let session = store.session(for: destination)
            XCTAssertTrue(session.stateRestorationFailed)
            XCTAssertTrue(session.draft.isEmpty)
            XCTAssertTrue(session.outgoing.isEmpty)
            // Do not invoke the pre-fix duplicate-key trap after a failed protection assertion.
            if session.stateRestorationFailed { XCTAssertTrue(session.messages.isEmpty) }
            store.setDraftText("Continue after preserving evidence", for: destination)
            await store.refresh(for: destination)
            await store.sendDraft(to: destination)
            XCTAssertEqual(try Data(contentsOf: path), bytes)
            let requests = await network.requests
            XCTAssertTrue(requests.isEmpty)
            try store.preserveUnreadableState(for: destination)
            let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("state.json.recovery-") }
            XCTAssertEqual(backups.count, 1)
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), bytes)
        }
    }

    @MainActor
    func testInvalidHistoryVersionsAndDuplicateReceiptsLeaveDraftRecoveryIndependent() async throws {
        let destination = target()
        let id = "00000000-0000-4000-8000-000000000002"
        let receipt = #"{"id":"\#(id)","hostId":"local","threadId":"\#(destination.thread.id)","createdAt":0,"updatedAt":0,"state":"unknown","message":{"id":"client:\#(id)","clientMessageId":"\#(id)","role":"user","text":"Original request","phase":"user","state":"unknown","attachments":[]}}"#
        let fixtures = [
            #"{"version":0,"messages":[],"hasLoadedOlder":false,"receipts":[\#(receipt)]}"#,
            #"{"version":-1,"messages":[],"hasLoadedOlder":false,"receipts":[\#(receipt)]}"#,
            #"{"version":2,"messages":[],"hasLoadedOlder":false,"receipts":[\#(receipt),\#(receipt)]}"#
        ]
        for fixture in fixtures {
            let root = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let network = ConversationNetworkFixture()
            let store = CodexConversationStore(network: network, storageRoot: root)
            store.setDraftText("Independent draft", for: destination)
            let directory = root.appendingPathComponent(CodexConversationKey(destination).storageID)
            let path = directory.appendingPathComponent("history.json")
            let bytes = Data(fixture.utf8)
            try bytes.write(to: path)
            let restored = CodexConversationStore(network: network, storageRoot: root)
            let session = restored.session(for: destination)
            XCTAssertTrue(session.historyRestorationFailed)
            XCTAssertFalse(session.hasLoaded)
            XCTAssertTrue(session.receipts.isEmpty)
            XCTAssertEqual(session.draft.text, "Independent draft")
            XCTAssertNil(session.draftError)
            restored.setDraftText("Continued editing", for: destination)
            XCTAssertEqual(try Data(contentsOf: path), bytes)
            await restored.refresh(for: destination)
            let backups = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("history.json.recovery-") }
            XCTAssertEqual(backups.count, 1)
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(backups.first)), bytes)
            let reopened = CodexConversationStore(network: network, storageRoot: root)
            XCTAssertEqual(reopened.session(for: destination).draft.text, "Continued editing")
            XCTAssertFalse(reopened.session(for: destination).historyRestorationFailed)
        }
    }

    private func numberedMessages(_ numbers: ClosedRange<Int>) -> [CodexConversationMessage] {
        numbers.map { index in
            CodexConversationMessage(id: "message-\(index)", turnId: nil, clientMessageId: nil, role: "assistant", text: "Message \(index)", phase: "final_answer", createdAt: Date(timeIntervalSince1970: Double(index)), state: .completed, attachments: [])
        }
    }

    func testAssetURLPreservesPairingPrefixAndRejectsCrossTargetReferences() throws {
        let key = CodexConversationKey(target())
        let digest = String(repeating: "a", count: 64)
        let path = "/api/codex/assets/\(digest)?hostId=local&threadId=\(key.threadId)"
        let resolved = try NetworkService.conversationAssetURL(path, key: key)
        XCTAssertEqual(resolved.path, "/device/test-pair/api/codex/assets/\(digest)")
        XCTAssertEqual(resolved.host, "test.invalid")
        XCTAssertThrowsError(try NetworkService.conversationAssetURL("https://another.invalid" + path, key: key))
        XCTAssertThrowsError(try NetworkService.conversationAssetURL(path.replacingOccurrences(of: "hostId=local", with: "hostId=remote"), key: key))
        XCTAssertThrowsError(try NetworkService.conversationAssetURL("/api/codex/assets/../config?hostId=local&threadId=\(key.threadId)", key: key))
    }

    private func target(host: String = "local", base: String = "http://test.invalid/device/test-pair") -> CodexChatTarget {
        CodexChatTarget(thread: CodexThread(id: "00000000-0000-4000-8000-000000000001", title: "Test", cwd: "/tmp", updatedAt: 0),
                        serverURL: URL(string: base)!,
                        host: CodexHost(id: host, name: host, kind: host == "local" ? "local" : "remote", configured: true, available: true, reason: nil))
    }
    private func temporaryDirectory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("conversation-\(UUID().uuidString)") }
    @MainActor private func imageBytes() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).pngData { context in
            UIColor.black.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 12, height: 12))
        }
    }
}

private actor ConversationNetworkFixture: CodexConversationNetworking, CodexModelSettingsNetworking {
    static let modelObservedAt = Date(timeIntervalSince1970: 1_800_000_000)
    enum PostMode { case accepted, timeout, suspended }
    enum ReceiptMode { case accepted, missing }
    var requests: [CodexMessageRequest] = []
    var receiptReadCount = 0
    private var postMode = PostMode.accepted
    private var receiptMode = ReceiptMode.accepted
    private var pageMessages: [CodexConversationMessage] = []
    private var pageReceipts: [CodexMessageReceipt] = []
    private var pageHost: String?
    private var pageCursor: String?
    private var olderMessages: [CodexConversationMessage] = []
    private var olderReceipts: [CodexMessageReceipt] = []
    private var olderCursor: String?
    private var requestWaiter: CheckedContinuation<Void, Never>?
    private var postWaiter: CheckedContinuation<Void, Never>?
    private var modelInputModalities = ["text", "image"]

    func configure(post: PostMode, receipt: ReceiptMode) { postMode = post; receiptMode = receipt }
    func setModelInputModalities(_ value: [String]) { modelInputModalities = value }
    func setPage(messages: [CodexConversationMessage], host: String, receipts: [CodexMessageReceipt] = []) {
        pageMessages = messages; pageHost = host; pageReceipts = receipts
    }
    func setPages(latest: [CodexConversationMessage], before: String?, older: [CodexConversationMessage], olderBefore: String?, olderReceipts: [CodexMessageReceipt] = []) {
        pageMessages = latest; pageCursor = before; olderMessages = older; olderCursor = olderBefore
        self.olderReceipts = olderReceipts
    }
    func waitForRequest() async {
        if !requests.isEmpty { return }
        await withCheckedContinuation { requestWaiter = $0 }
    }
    func finishSuspendedPost() { postWaiter?.resume(); postWaiter = nil }

    func conversation(for key: CodexConversationKey, before: String?) async throws -> CodexConversationPage {
        CodexConversationPage(hostId: pageHost ?? key.hostId, threadId: key.threadId, messages: before == nil ? pageMessages : olderMessages,
                              beforeCursor: before == nil ? pageCursor : olderCursor, runState: "idle",
                              receipts: before == nil ? pageReceipts : olderReceipts, updatedAt: Date())
    }
    func sendMessage(_ body: CodexMessageRequest, for key: CodexConversationKey) async throws -> CodexMessageReceipt {
        requests.append(body)
        switch postMode {
        case .timeout: throw URLError(.timedOut)
        case .accepted: break
        case .suspended:
            await withCheckedContinuation { continuation in
                postWaiter = continuation
                requestWaiter?.resume()
                requestWaiter = nil
            }
        }
        return receipt(body, key: key)
    }
    func messageReceipt(_ id: String, for key: CodexConversationKey) async throws -> CodexMessageReceipt {
        receiptReadCount += 1
        if receiptMode == .missing { throw NetworkService.NetworkError.server(statusCode: 404, message: "Not accepted") }
        guard let request = requests.first(where: { $0.id == id }) else { throw URLError(.unknown) }
        return receipt(request, key: key)
    }
    func conversationImage(at path: String, for key: CodexConversationKey) async throws -> Data { throw URLError(.fileDoesNotExist) }
    func codexModels(from serverURL: URL, hostId: String) async throws -> CodexModelCatalog {
        let formatter = ISO8601DateFormatter()
        return CodexModelCatalog(hostId: hostId, status: "available", source: "local-app-server",
            observedAt: formatter.string(from: Self.modelObservedAt), expiresAt: formatter.string(from: Self.modelObservedAt.addingTimeInterval(300)),
            models: [CodexAvailableModel(id: "model-a-id", model: "model-a", displayName: "Model A", description: "Test model",
                supportedReasoningEfforts: [CodexReasoningOption(reasoningEffort: "high", description: "High reasoning")],
                defaultReasoningEffort: "high", inputModalities: modelInputModalities, isDefault: true)], reason: nil)
    }
    func codexModelSettings(from serverURL: URL, hostId: String, threadId: String) async throws -> CodexThreadModelSettings {
        CodexThreadModelSettings(hostId: hostId, threadId: threadId, model: "model-a", reasoningEffort: "high",
            observedAt: ISO8601DateFormatter().string(from: Self.modelObservedAt))
    }
    private func receipt(_ body: CodexMessageRequest, key: CodexConversationKey) -> CodexMessageReceipt {
        let message = CodexConversationMessage(id: "client:\(body.id)", turnId: nil, clientMessageId: body.id,
                                               role: "user", text: body.text, phase: "user", createdAt: Date(), state: .queued, attachments: [])
        return CodexMessageReceipt(id: body.id, hostId: key.hostId, threadId: key.threadId,
                                   createdAt: Date(), updatedAt: Date(), state: .queued, turnId: nil, message: message, error: nil, notice: nil)
    }
}
