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

    @MainActor
    func testReceiptCompletesWhileHistoryRemainsUnavailableWithoutAnotherPost() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ConversationNetworkFixture()
        let destination = target()
        let store = CodexConversationStore(network: network, storageRoot: root)
        store.setDraftText("One request", for: destination)
        await store.sendDraft(to: destination)
        await network.failHistoryAndCompleteReceipt()
        await store.refresh(for: destination)
        XCTAssertEqual(store.session(for: destination).outgoing.first?.state, .completed)
        XCTAssertNotNil(store.session(for: destination).error)
        let restored = CodexConversationStore(network: network, storageRoot: root)
        XCTAssertEqual(restored.session(for: destination).outgoing.first?.state, .completed)
        let requests = await network.requests
        XCTAssertEqual(requests.count, 1)
    }

    @MainActor
    func testReleaseUnknownWaitKeepsOriginalRequestAndLateReceiptAcrossRestart() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ConversationNetworkFixture()
        let destination = target()
        let store = CodexConversationStore(network: network, storageRoot: root)
        await network.setReceiptState(.unknown)
        store.setDraftText("Uncertain A", for: destination)
        await store.sendDraft(to: destination)
        let original = try XCTUnwrap(store.session(for: destination).outgoing.first)
        await store.releaseWait(original.id, for: destination)
        await store.releaseWait(original.id, for: destination)
        XCTAssertEqual(store.receipt(original.id, for: destination)?.state, .unknown)
        XCTAssertEqual(store.receipt(original.id, for: destination)?.queueBlocking, false)
        let restored = CodexConversationStore(network: network, storageRoot: root)
        XCTAssertEqual(restored.receipt(original.id, for: destination)?.queueBlocking, false)
        await restored.cancelPending(original.id, for: destination)
        await network.setReceiptState(.completed)
        await restored.refresh(for: destination)
        XCTAssertEqual(restored.localMessage(original.id, for: destination)?.state, .completed)
        let requests = await network.requests
        let releases = await network.releaseCount
        let cancels = await network.cancelCount
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(releases, 1)
        XCTAssertEqual(cancels, 0, "An unknown request already crossed the send boundary.")
    }

    @MainActor
    func testReleaseUnknownWithoutCachedReceiptUsesBackendAndPreservesRequest() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ConversationNetworkFixture()
        await network.configure(post: .timeout, receipt: .unavailable)
        await network.setReceiptState(.unknown)
        let destination = target()
        let store = CodexConversationStore(network: network, storageRoot: root)
        store.setDraftText("Uncertain original request", for: destination)
        let selection = CodexDraftModelSelection(model: "model-a", reasoningEffort: "high")
        store.setDraftModelSelection(selection, for: destination)
        try store.addImage(CodexImportedImage(data: imageBytes(), name: "Original.png", mimeType: "image/png"), for: destination)
        await store.sendDraft(to: destination)
        let original = try XCTUnwrap(store.session(for: destination).outgoing.first)
        XCTAssertEqual(original.state, .unknown)
        XCTAssertNil(store.receipt(original.id, for: destination))
        store.setDraftText("Separate next draft", for: destination)

        await store.releaseWait(original.id, for: destination)
        await store.releaseWait(original.id, for: destination)
        let released = try XCTUnwrap(store.localMessage(original.id, for: destination))
        XCTAssertEqual(released.id, original.id)
        XCTAssertEqual(released.text, original.text)
        XCTAssertEqual(released.attachments, original.attachments)
        XCTAssertEqual(released.selection, original.selection)
        XCTAssertEqual(released.state, .unknown)
        XCTAssertFalse(released.canRetry)
        XCTAssertEqual(store.receipt(original.id, for: destination)?.queueBlocking, false)
        XCTAssertEqual(store.session(for: destination).draft.text, "Separate next draft")
        let restored = CodexConversationStore(network: network, storageRoot: root)
        XCTAssertEqual(restored.receipt(original.id, for: destination)?.queueBlocking, false)
        await network.configure(post: .accepted, receipt: .accepted)
        await network.setReceiptState(.completed)
        await restored.refresh(for: destination)
        XCTAssertEqual(restored.localMessage(original.id, for: destination)?.state, .completed)
        let requests = await network.requests
        let releases = await network.releaseCount
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(releases, 1)
    }

    @MainActor
    func testRejectedReleaseWithoutCachedReceiptKeepsUnknownEvidenceAndReportsError() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ConversationNetworkFixture()
        await network.configure(post: .timeout, receipt: .unavailable)
        await network.failRelease(statusCode: 404)
        let destination = target()
        let store = CodexConversationStore(network: network, storageRoot: root)
        store.setDraftText("Keep uncertain evidence", for: destination)
        await store.sendDraft(to: destination)
        let original = try XCTUnwrap(store.session(for: destination).outgoing.first)
        await store.releaseWait(original.id, for: destination)
        XCTAssertNil(store.receipt(original.id, for: destination))
        XCTAssertEqual(store.localMessage(original.id, for: destination)?.message, original.message)
        XCTAssertEqual(store.localMessage(original.id, for: destination)?.canRetry, false)
        XCTAssertNotNil(store.session(for: destination).receiptError)
        XCTAssertNil(store.session(for: destination).queueActionID)
        let requests = await network.requests
        let releases = await network.releaseCount
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(releases, 1)
        let restored = CodexConversationStore(network: network, storageRoot: root)
        XCTAssertEqual(restored.localMessage(original.id, for: destination)?.state, .unknown)
        XCTAssertEqual(restored.localMessage(original.id, for: destination)?.canRetry, false)
    }

    @MainActor
    func testStalePaginationCannotBridgeAGapAndCorrectCursorLoadsAllMessages() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = target()
        let network = ConversationNetworkFixture()
        let store = CodexConversationStore(network: network, storageRoot: root)
        await network.setPages(latest: numberedMessages(51...100), before: "50", older: numberedMessages(1...50), olderBefore: nil)
        await store.refresh(for: destination)
        await network.suspendOlderPage()
        let oldPage = Task { await store.loadOlder(for: destination) }
        await network.waitForOlderPage()
        await network.setPages(latest: numberedMessages(101...150), before: "100", older: numberedMessages(51...100), olderBefore: "50")
        await store.refresh(for: destination)
        await network.finishOlderPage()
        await oldPage.value
        XCTAssertEqual(store.session(for: destination).history.map(\.id), (101...150).map { "message-\($0)" })
        XCTAssertEqual(store.session(for: destination).beforeCursor, "100")
        await store.loadOlder(for: destination)
        await network.setPages(latest: numberedMessages(101...150), before: "100", older: numberedMessages(1...50), olderBefore: nil)
        await store.loadOlder(for: destination)
        XCTAssertEqual(store.session(for: destination).history.map(\.id), (1...150).map { "message-\($0)" })
        let restored = CodexConversationStore(network: network, storageRoot: root)
        XCTAssertEqual(restored.session(for: destination).history.map(\.id), (1...150).map { "message-\($0)" })
    }

    @MainActor
    func testOverlappingRefreshDoesNotInvalidateUsefulPagination() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = target()
        let network = ConversationNetworkFixture()
        let store = CodexConversationStore(network: network, storageRoot: root)
        await network.setPages(latest: numberedMessages(51...100), before: "50", older: numberedMessages(1...50), olderBefore: nil)
        await store.refresh(for: destination)
        await network.suspendOlderPage()
        let older = Task { await store.loadOlder(for: destination) }
        await network.waitForOlderPage()
        await network.setPages(latest: numberedMessages(76...125), before: "75", older: [], olderBefore: nil)
        await store.refresh(for: destination)
        await network.finishOlderPage()
        await older.value
        XCTAssertEqual(store.session(for: destination).history.map(\.id), (1...125).map { "message-\($0)" })
        XCTAssertNil(store.session(for: destination).beforeCursor)
    }

    @MainActor
    func testUnsentCreationHandoffPreservesExistingDraftAndIsIdempotentAcrossRestart() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = target()
        let bytes = imageBytes()
        var request = CodexCreateChatRequest(id: UUID().uuidString.lowercased(), hostId: destination.host.id,
            projectId: "project", prompt: "Original first requirement", title: "New chat")
        request.attachments = [CodexCreateChatAttachment(id: "source-image", name: "Canvas.png", mimeType: "image/png", dataBase64: bytes.base64EncodedString())]
        var receipt = CodexChatCreationReceipt(id: request.id, hostId: request.hostId, projectId: request.projectId,
            state: .unknown, thread: destination.thread, error: nil, notice: nil)
        receipt.firstMessageState = "not_sent"
        let store = CodexConversationStore(network: ConversationNetworkFixture(), storageRoot: root)
        store.setDraftText("Existing draft", for: destination)
        try store.handoffCreation(request, receipt: receipt, to: destination)
        let restored = CodexConversationStore(network: ConversationNetworkFixture(), storageRoot: root)
        try restored.handoffCreation(request, receipt: receipt, to: destination)
        XCTAssertEqual(restored.session(for: destination).draft.text, "Existing draft")
        XCTAssertEqual(restored.session(for: destination).recoveredDrafts.count, 1)
        try restored.restoreRecoveredDraft(request.id, for: destination)
        XCTAssertEqual(restored.session(for: destination).draft.text, request.prompt)
        let attachment = try XCTUnwrap(restored.session(for: destination).draft.attachments.first)
        let transferred = try await restored.imageData(attachment.messageAttachment, for: destination)
        XCTAssertEqual(transferred, bytes)
        XCTAssertEqual(restored.session(for: destination).recoveredDrafts.first?.draft.text, "Existing draft")
        XCTAssertTrue(restored.session(for: destination).outgoing.isEmpty)
    }

    @MainActor
    func testKnownCreationHandoffNeverResendsOrPermitsRetryFromMissingLegacyReceipt() async throws {
        for firstState in ["unknown", "sent"] {
            let root = temporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let destination = target()
            let request = CodexCreateChatRequest(id: UUID().uuidString.lowercased(), hostId: destination.host.id,
                projectId: "project", prompt: "Original request", title: nil)
            var receipt = CodexChatCreationReceipt(id: request.id, hostId: request.hostId, projectId: request.projectId,
                state: .unknown, thread: destination.thread, error: nil, notice: nil)
            receipt.firstMessageState = firstState
            receipt.firstMessageRequestId = request.id
            let network = ConversationNetworkFixture()
            await network.configure(post: .accepted, receipt: .missing)
            let store = CodexConversationStore(network: network, storageRoot: root)
            try store.handoffCreation(request, receipt: receipt, to: destination)
            let restored = CodexConversationStore(network: network, storageRoot: root)
            try restored.handoffCreation(request, receipt: receipt, to: destination)
            await restored.refresh(for: destination)
            await restored.retryUnaccepted(request.id, for: destination)
            XCTAssertEqual(restored.session(for: destination).outgoing.count, 1)
            XCTAssertEqual(restored.session(for: destination).outgoing.first?.id, request.id)
            XCTAssertFalse(restored.session(for: destination).outgoing[0].canRetry)
            let posts = await network.requests
            XCTAssertTrue(posts.isEmpty)
        }
    }

    @MainActor
    func testCreationHandoffFailureLeavesNoPartialDestinationAssociation() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = target()
        let directory = root.appendingPathComponent(CodexConversationKey(destination).storageID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let bytes = Data("unreadable previous state".utf8)
        try bytes.write(to: directory.appendingPathComponent("state.json"))
        let request = CodexCreateChatRequest(id: UUID().uuidString.lowercased(), hostId: destination.host.id,
            projectId: "project", prompt: "Keep at source", title: nil)
        var receipt = CodexChatCreationReceipt(id: request.id, hostId: request.hostId, projectId: request.projectId,
            state: .unknown, thread: destination.thread, error: nil, notice: nil)
        receipt.firstMessageState = "not_sent"
        let store = CodexConversationStore(network: ConversationNetworkFixture(), storageRoot: root)
        XCTAssertThrowsError(try store.handoffCreation(request, receipt: receipt, to: destination))
        XCTAssertTrue(store.session(for: destination).handedOffCreationIDs.isEmpty)
        XCTAssertTrue(store.session(for: destination).draft.isEmpty)
        XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("state.json")), bytes)
        try store.preserveUnreadableState(for: destination)
        try store.handoffCreation(request, receipt: receipt, to: destination)
        XCTAssertEqual(store.session(for: destination).draft.text, request.prompt)
    }

    @MainActor
    func testReadingBlockAndLocalFractionSurviveRestartAndClearAtLatest() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = target()
        let store = CodexConversationStore(network: ConversationNetworkFixture(), storageRoot: root)
        store.setReadingPosition("message", atBottom: false, for: destination, blockID: "message:paragraph:7", blockFraction: 0.42)
        let restored = CodexConversationStore(network: ConversationNetworkFixture(), storageRoot: root)
        XCTAssertEqual(restored.session(for: destination).readingBlockID, "message:paragraph:7")
        XCTAssertEqual(restored.session(for: destination).readingBlockFraction, 0.42)
        XCTAssertFalse(restored.session(for: destination).isAtBottom)
        restored.setReadingPosition(nil, atBottom: true, for: destination)
        let latest = CodexConversationStore(network: ConversationNetworkFixture(), storageRoot: root)
        XCTAssertNil(latest.session(for: destination).readingBlockID)
        XCTAssertNil(latest.session(for: destination).readingBlockFraction)
        XCTAssertTrue(latest.session(for: destination).isAtBottom)
    }

    @MainActor
    func testSubmissionReferenceIsAvailableBeforeResponseAndRemainsBoundToOriginalTarget() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ConversationNetworkFixture()
        await network.configure(post: .suspended, receipt: .missing)
        let original = target()
        let other = target(host: "remote-control:mini")
        let store = CodexConversationStore(network: network, storageRoot: root)
        store.setDraftText("Keep original destination", for: original)
        let send = Task { await store.sendDraft(to: original) }
        await network.waitForRequest()
        let reference = try XCTUnwrap(store.lastSubmission)
        XCTAssertEqual(reference.target, original)
        XCTAssertEqual(store.localMessage(reference.id, for: reference.target)?.state, .dispatching)
        store.setDraftText("Independent work", for: other)
        let reopened = CodexConversationStore(network: network, storageRoot: root)
        XCTAssertEqual(reopened.lastSubmission, reference)
        await network.finishSuspendedPost()
        let returned = await send.value
        XCTAssertEqual(returned, reference)
        XCTAssertEqual(store.lastSubmission?.target, original)
        XCTAssertEqual(store.session(for: other).draft.text, "Independent work")
    }

    @MainActor
    func testObserversSharePollingAndCancellingOneKeepsTheOtherAlive() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ConversationNetworkFixture()
        let clock = ConversationPollingClock()
        let destination = target()
        let key = CodexConversationKey(destination)
        let store = CodexConversationStore(network: network, storageRoot: root, pollingSleep: clock.sleep)
        let first = Task { await store.observe(target: destination) }
        defer { first.cancel() }
        await waitUntil { clock.pendingCount == 1 }
        var secondStarted = false
        let second = Task {
            secondStarted = true
            await store.observe(target: destination)
        }
        await waitUntil { secondStarted }
        second.cancel()
        await second.value
        let readsAfterSecondObserver = await network.historyReadCount(for: key)
        XCTAssertEqual(readsAfterSecondObserver, 1, "Joining the same chat must reuse its poller rather than refresh again.")
        XCTAssertEqual(clock.pendingCount, 1)

        clock.advance()
        await waitUntil { await network.historyReadCount(for: key) == 2 && clock.pendingCount == 1 }
        first.cancel()
        await first.value
        await waitUntil { clock.pendingCount == 0 }
        let readsAfterCancellation = await network.historyReadCount(for: key)
        XCTAssertEqual(readsAfterCancellation, 2)

        // A new observer starts one fresh poller after the old subscribers leave.
        let reopened = Task { await store.observe(target: destination) }
        defer { reopened.cancel() }
        await waitUntil { await network.historyReadCount(for: key) == 3 && clock.pendingCount == 1 }
        reopened.cancel()
        await reopened.value
        await waitUntil { clock.pendingCount == 0 }
        let cancelled = Task { await store.observe(target: destination) }
        cancelled.cancel()
        await cancelled.value
        let finalReads = await network.historyReadCount(for: key)
        XCTAssertEqual(finalReads, 3, "An already-cancelled view task must not start another poller.")
    }

    @MainActor
    func testOriginalRequestSubscriberKeepsReconcilingAfterSelectedChatChanges() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ConversationNetworkFixture()
        await network.configure(post: .timeout, receipt: .unavailable)
        let clock = ConversationPollingClock()
        let original = target()
        let other = target(host: "remote-control:mini")
        let store = CodexConversationStore(network: network, storageRoot: root, pollingSleep: clock.sleep)
        store.setDraftText("Keep original target and request", for: original)
        await store.sendDraft(to: original)
        let reference = try XCTUnwrap(store.lastSubmission)
        XCTAssertEqual(store.localMessage(reference.id, for: original)?.state, .unknown)
        let selectedOriginal = Task { await store.observe(target: original) }
        let requestCard = Task { await store.observe(target: reference.target) }
        defer { selectedOriginal.cancel(); requestCard.cancel() }
        await waitUntil { clock.pendingCount == 1 }
        selectedOriginal.cancel()
        await selectedOriginal.value
        store.setDraftText("Independent second chat", for: other)
        let selectedOther = Task { await store.observe(target: other) }
        defer { selectedOther.cancel() }
        await waitUntil { clock.pendingCount == 2 }

        await network.configure(post: .accepted, receipt: .accepted)
        await network.setReceiptState(.completed)
        clock.advance()
        await waitUntil { store.localMessage(reference.id, for: original)?.state == .completed && clock.pendingCount == 2 }
        XCTAssertEqual(store.lastSubmission, reference)
        XCTAssertEqual(store.session(for: other).draft.text, "Independent second chat")
        XCTAssertTrue(store.session(for: other).outgoing.isEmpty)
        let requests = await network.requests
        let receiptKeys = await network.receiptReadKeys
        XCTAssertEqual(requests.count, 1, "Reconciliation must never replay an unknown send.")
        XCTAssertTrue(receiptKeys.allSatisfy { $0 == CodexConversationKey(original) })

        requestCard.cancel()
        selectedOther.cancel()
        await requestCard.value
        await selectedOther.value
        await waitUntil { clock.pendingCount == 0 }
    }

    @MainActor
    func testRestoredSubmissionObserverUsesSavedOriginalTargetWithoutPosting() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let network = ConversationNetworkFixture()
        let original = target()
        let other = target(host: "remote-control:mini")
        let store = CodexConversationStore(network: network, storageRoot: root)
        store.setDraftText("Persist original request", for: original)
        await store.sendDraft(to: original)
        let reference = try XCTUnwrap(store.lastSubmission)
        let clock = ConversationPollingClock()
        let restored = CodexConversationStore(network: network, storageRoot: root, pollingSleep: clock.sleep)
        let restoredReference = try XCTUnwrap(restored.lastSubmission)
        XCTAssertEqual(restoredReference, reference)
        await network.setReceiptState(.completed)
        let requestCard = Task { await restored.observe(target: restoredReference.target) }
        let selectedOther = Task { await restored.observe(target: other) }
        defer { requestCard.cancel(); selectedOther.cancel() }
        await waitUntil { restored.localMessage(reference.id, for: original)?.state == .completed && clock.pendingCount == 2 }
        let requests = await network.requests
        let receiptKeys = await network.receiptReadKeys
        XCTAssertEqual(requests.count, 1)
        XCTAssertTrue(receiptKeys.allSatisfy { $0 == CodexConversationKey(original) })
        XCTAssertTrue(restored.session(for: other).outgoing.isEmpty)
        requestCard.cancel()
        selectedOther.cancel()
        await requestCard.value
        await selectedOther.value
        await waitUntil { clock.pendingCount == 0 }
    }

    @MainActor
    private func waitUntil(_ condition: @MainActor () async -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<200 {
            if await condition() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        XCTFail("Timed out waiting for the polling fixture", file: file, line: line)
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

@MainActor
private final class ConversationPollingClock {
    private var sleepers: [UUID: CheckedContinuation<Void, Error>] = [:]
    var pendingCount: Int { sleepers.count }

    func sleep(_ interval: TimeInterval) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else { continuation.resume(throwing: CancellationError()); return }
                sleepers[id] = continuation
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.sleepers.removeValue(forKey: id)?.resume(throwing: CancellationError())
            }
        }
    }

    func advance() {
        let pending = Array(sleepers.values)
        sleepers.removeAll()
        for sleeper in pending { sleeper.resume() }
    }
}

private actor ConversationNetworkFixture: CodexConversationNetworking, CodexModelSettingsNetworking {
    static let modelObservedAt = Date(timeIntervalSince1970: 1_800_000_000)
    enum PostMode { case accepted, timeout, suspended }
    enum ReceiptMode { case accepted, missing, unavailable }
    var requests: [CodexMessageRequest] = []
    var receiptReadCount = 0
    var receiptReadKeys: [CodexConversationKey] = []
    var releaseCount = 0
    var cancelCount = 0
    private var postMode = PostMode.accepted
    private var receiptMode = ReceiptMode.accepted
    private var historyUnavailable = false
    private var receiptState = CodexMessageState.queued
    private var releaseStatusCode: Int?
    private var pageMessages: [CodexConversationMessage] = []
    private var pageReceipts: [CodexMessageReceipt] = []
    private var pageHost: String?
    private var pageCursor: String?
    private var olderMessages: [CodexConversationMessage] = []
    private var olderReceipts: [CodexMessageReceipt] = []
    private var olderCursor: String?
    private var requestWaiter: CheckedContinuation<Void, Never>?
    private var suspendOlder = false
    private var olderEntered: CheckedContinuation<Void, Never>?
    private var olderGate: CheckedContinuation<Void, Never>?
    private var postWaiter: CheckedContinuation<Void, Never>?
    private var modelInputModalities = ["text", "image"]
    private var historyReadCounts: [CodexConversationKey: Int] = [:]

    func historyReadCount(for key: CodexConversationKey) -> Int { historyReadCounts[key, default: 0] }
    func configure(post: PostMode, receipt: ReceiptMode) { postMode = post; receiptMode = receipt }
    func setReceiptState(_ state: CodexMessageState) { receiptState = state }
    func failRelease(statusCode: Int) { releaseStatusCode = statusCode }
    func failHistoryAndCompleteReceipt() { historyUnavailable = true; receiptState = .completed }
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

    func suspendOlderPage() { suspendOlder = true }
    func waitForOlderPage() async {
        if olderGate != nil { return }
        await withCheckedContinuation { olderEntered = $0 }
    }
    func finishOlderPage() { suspendOlder = false; olderGate?.resume(); olderGate = nil }

    func conversation(for key: CodexConversationKey, before: String?) async throws -> CodexConversationPage {
        historyReadCounts[key, default: 0] += 1
        if historyUnavailable { throw NetworkService.NetworkError.server(statusCode: 503, message: "Desktop is offline") }
        let result = CodexConversationPage(hostId: pageHost ?? key.hostId, threadId: key.threadId, messages: before == nil ? pageMessages : olderMessages,
                              beforeCursor: before == nil ? pageCursor : olderCursor, runState: "idle",
                              receipts: before == nil ? pageReceipts : olderReceipts, updatedAt: Date())
        if before != nil && suspendOlder {
            await withCheckedContinuation { continuation in
                olderGate = continuation
                olderEntered?.resume()
                olderEntered = nil
            }
        }
        return result
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
        receiptReadKeys.append(key)
        if receiptMode == .missing { throw NetworkService.NetworkError.server(statusCode: 404, message: "Not accepted") }
        if receiptMode == .unavailable { throw NetworkService.NetworkError.server(statusCode: 503, message: "Receipts are unavailable") }
        guard let request = requests.first(where: { $0.id == id }) else { throw URLError(.unknown) }
        return receipt(request, key: key)
    }
    func releaseMessageWait(_ id: String, for key: CodexConversationKey) async throws -> CodexMessageReceipt {
        releaseCount += 1
        if let releaseStatusCode { throw NetworkService.NetworkError.server(statusCode: releaseStatusCode, message: "Could not release this request") }
        guard let body = requests.first(where: { $0.id == id }) else { throw URLError(.unknown) }
        var result = receipt(body, key: key)
        result.queueBlocking = false
        result.waitReleasedAt = Date()
        return result
    }
    func cancelPendingMessage(_ id: String, for key: CodexConversationKey) async throws -> CodexMessageReceipt {
        cancelCount += 1
        throw NetworkService.NetworkError.server(statusCode: 409, message: "Cannot cancel")
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
                                   createdAt: Date(), updatedAt: Date(), state: receiptState, turnId: nil, message: message, error: nil, notice: nil)
    }
}
