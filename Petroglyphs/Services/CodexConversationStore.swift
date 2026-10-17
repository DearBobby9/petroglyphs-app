import Foundation
import Observation
import CryptoKit

@MainActor
@Observable
final class CodexConversationSession {
    let key: CodexConversationKey
    var draft = CodexMessageDraft()
    var history: [CodexConversationMessage] = []
    var outgoing: [CodexLocalMessage] = []
    var recoveredDrafts: [CodexRecoveredDraft] = []
    var handedOffCreationIDs: Set<String> = []
    var beforeCursor: String?
    var runState = "unknown"
    var receipts: [String: CodexMessageReceipt] = [:]
    var failedRefreshes = 0
    var isLoading = false
    var isRefreshing = false
    var isLoadingOlder = false
    var queueActionID: String?
    var hasLoaded = false
    var hasLoadedOlder = false
    var historyGeneration = 0
    var error: String?
    var receiptError: String?
    var draftError: String?
    var stateRestorationFailed = false
    var historyRestorationFailed = false
    var importingCount = 0
    var isAtBottom = true
    var readingMessageID: String?
    var readingBlockID: String?
    var readingBlockFraction: Double?

    init(key: CodexConversationKey) { self.key = key }

    var messages: [CodexConversationMessage] {
        let localByID = Dictionary(uniqueKeysWithValues: outgoing.map { ($0.id, $0) })
        let recordedIDs = Set(history.compactMap(\.clientMessageId))
        let recordedMessageIDs = Set(history.map(\.id))
        var result = history.map { message in
            var result = message
            if let clientID = message.clientMessageId, let local = localByID[clientID], message.role == "user" {
                result.state = local.state
                if result.attachments.isEmpty { result.attachments = local.attachments.map(\.messageAttachment) }
            }
            return result
        }
        result.append(contentsOf: outgoing.filter { !$0.appearedInHistory && !recordedIDs.contains($0.id) && !recordedMessageIDs.contains($0.id) }.map(\.message))
        return result
    }

    var isBusy: Bool {
        runState == "running" || runState == "waiting" || outgoing.contains { [.pending, .dispatching, .queued, .running].contains($0.state) } || receipts.values.contains { [.pending, .dispatching, .queued, .running].contains($0.state) }
    }
    var activeCount: Int { outgoing.filter { !$0.state.isTerminal }.count }
}

@MainActor
@Observable
final class CodexConversationStore {
    private(set) var lastSubmission: CodexSubmissionReference?
    private var sessions: [CodexConversationKey: CodexConversationSession] = [:]
    @ObservationIgnored private let network: any CodexConversationNetworking
    @ObservationIgnored private let storageRoot: URL
    @ObservationIgnored private let pollingSleep: @MainActor (TimeInterval) async throws -> Void
    @ObservationIgnored private var receiptReads: Set<String> = []
    @ObservationIgnored private var pollingTasks: [CodexConversationKey: PollingTask] = [:]
    @ObservationIgnored private var observers: [CodexConversationKey: [UUID: CheckedContinuation<Void, Never>]] = [:]

    init(network: any CodexConversationNetworking = NetworkService(), storageRoot: URL? = nil,
         pollingSleep: @escaping @MainActor (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }) {
        self.network = network
        self.pollingSleep = pollingSleep
        self.storageRoot = storageRoot ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexConversations", isDirectory: true)
        lastSubmission = (try? Data(contentsOf: self.storageRoot.appendingPathComponent("last-submission.json")))
            .flatMap { try? JSONDecoder().decode(CodexSubmissionReference.self, from: $0) }
    }

    func session(for target: CodexChatTarget) -> CodexConversationSession {
        let key = CodexConversationKey(target)
        if let session = sessions[key] { return session }
        let session = CodexConversationSession(key: key)
        do {
            let path = directory(for: key).appendingPathComponent("state.json")
            if FileManager.default.fileExists(atPath: path.path) {
                let stored = try JSONDecoder().decode(SavedConversation.self, from: Data(contentsOf: path))
                guard (1...2).contains(stored.version ?? 1) else { throw ConversationError.unsupportedStorageVersion }
                guard Set(stored.outgoing.map(\.id)).count == stored.outgoing.count else { throw ConversationError.duplicateStoredID }
                session.draft = stored.draft
                session.outgoing = stored.outgoing.map { item in
                    var item = item
                    if !item.state.isTerminal && !item.canRetry { item.state = .unknown }
                    return item
                }
                session.recoveredDrafts = stored.recoveredDrafts ?? []
                session.handedOffCreationIDs = Set(stored.handedOffCreationIDs ?? [])
                session.readingMessageID = stored.readingMessageID
                session.readingBlockID = stored.readingBlockID
                session.readingBlockFraction = stored.readingBlockFraction
                session.isAtBottom = stored.isAtBottom
            }
        } catch {
            session.stateRestorationFailed = true
            session.draftError = "Could not restore this chat’s draft and requests. The original file is protected. Preserve it before starting a new draft."
        }
        do {
            let historyPath = directory(for: key).appendingPathComponent("history.json")
            if FileManager.default.fileExists(atPath: historyPath.path) {
                let saved = try JSONDecoder().decode(SavedHistory.self, from: Data(contentsOf: historyPath))
                guard (1...2).contains(saved.version ?? 1) else { throw ConversationError.unsupportedStorageVersion }
                let receipts = saved.receipts ?? []
                guard Set(receipts.map(\.id)).count == receipts.count else { throw ConversationError.duplicateStoredID }
                session.history = saved.messages
                session.beforeCursor = saved.beforeCursor
                session.hasLoadedOlder = saved.hasLoadedOlder
                session.hasLoaded = true
                session.receipts = Dictionary(uniqueKeysWithValues: receipts.map { ($0.id, $0) })
            }
        } catch {
            session.historyRestorationFailed = true
            session.error = "Could not restore cached history. Drafts and requests are stored separately."
        }
        sessions[key] = session
        return session
    }

    func handoffCreation(_ request: CodexCreateChatRequest, receipt: CodexChatCreationReceipt, to target: CodexChatTarget) throws {
        let session = session(for: target)
        guard request.id == receipt.id, request.hostId == target.host.id,
              receipt.hostId == target.host.id, request.projectId == receipt.projectId,
              receipt.thread?.id == target.thread.id else { throw ConversationError.wrongDestination }
        if session.handedOffCreationIDs.contains(request.id) { return }
        let previous = (session.draft, session.outgoing, session.recoveredDrafts, session.handedOffCreationIDs)
        let selection = request.selection.map { CodexDraftModelSelection(model: $0.model, reasoningEffort: $0.reasoningEffort) }
        let attachments = try request.attachments.map { image -> CodexDraftAttachment in
            guard let bytes = image.imageData else { throw ConversationError.imageUnavailable }
            return try persistImage(CodexImportedImage(data: bytes, name: image.name, mimeType: image.mimeType), for: session.key)
        }
        let draft = CodexMessageDraft(text: request.prompt, attachments: attachments, modelSelection: selection)
        if receipt.firstMessageState == "not_sent" {
            if session.draft.isEmpty { session.draft = draft }
            else { session.recoveredDrafts.append(CodexRecoveredDraft(id: request.id, draft: draft, createdAt: Date())) }
        } else {
            let id = receipt.firstMessageRequestId ?? request.id
            if !session.outgoing.contains(where: { $0.id == id }) {
                var local = CodexLocalMessage(id: id, text: request.prompt, attachments: attachments, createdAt: Date(),
                    state: receipt.firstMessageState == "sent" || receipt.state == .completed ? .queued : .unknown,
                    notice: "This is the original first message. Check its receipt before sending it again.", selection: request.selection)
                local.sourceCreationID = request.id
                session.outgoing.append(local)
            }
            if session.draft.modelSelection == nil { session.draft.modelSelection = selection }
        }
        session.handedOffCreationIDs.insert(request.id)
        do { try save(session); session.draftError = nil }
        catch {
            (session.draft, session.outgoing, session.recoveredDrafts, session.handedOffCreationIDs) = previous
            throw error
        }
    }

    func restoreRecoveredDraft(_ id: String, for target: CodexChatTarget) throws {
        let session = session(for: target)
        guard let item = session.recoveredDrafts.first(where: { $0.id == id }) else { return }
        let previous = (session.draft, session.recoveredDrafts)
        session.recoveredDrafts.removeAll { $0.id == id }
        if !session.draft.isEmpty {
            session.recoveredDrafts.append(CodexRecoveredDraft(id: UUID().uuidString.lowercased(), draft: session.draft, createdAt: Date()))
        }
        session.draft = item.draft
        do { try save(session) }
        catch { (session.draft, session.recoveredDrafts) = previous; throw error }
    }

    func setDraftText(_ text: String, for target: CodexChatTarget) {
        let session = session(for: target)
        session.draft.text = text
        saveReportingFailure(session)
    }

    func setDraftModelSelection(_ value: CodexDraftModelSelection?, for target: CodexChatTarget) {
        let session = session(for: target)
        session.draft.modelSelection = value
        saveReportingFailure(session)
    }

    func setReadingPosition(_ id: String?, atBottom: Bool, for target: CodexChatTarget, blockID: String? = nil, blockFraction: Double? = nil) {
        let session = session(for: target)
        let fraction = blockFraction.flatMap { $0.isFinite ? min(1, max(0, $0)) : nil }
        guard session.readingMessageID != id || session.isAtBottom != atBottom
                || session.readingBlockID != blockID || session.readingBlockFraction != fraction else { return }
        session.readingMessageID = id
        session.readingBlockID = atBottom ? nil : blockID
        session.readingBlockFraction = atBottom ? nil : fraction
        session.isAtBottom = atBottom
        saveReportingFailure(session)
    }

    func addImage(_ image: CodexImportedImage, for target: CodexChatTarget) throws {
        let session = session(for: target)
        guard session.draft.attachments.count < CodexAttachmentImporter.maximumCount else { throw CodexAttachmentImporter.ImportError.tooMany }
        guard session.draft.attachments.reduce(image.data.count, { $0 + $1.byteCount }) <= CodexAttachmentImporter.maximumTotalBytes else {
            throw CodexAttachmentImporter.ImportError.totalTooLarge
        }
        let attachment = try persistImage(image, for: session.key)
        let previous = session.draft
        session.draft.attachments.append(attachment)
        do { try save(session); session.draftError = nil }
        catch { session.draft = previous; throw error }
    }

    func removeAttachment(_ id: String, for target: CodexChatTarget) {
        let session = session(for: target)
        session.draft.attachments.removeAll { $0.id == id }
        saveReportingFailure(session)
    }

    func observe(target: CodexChatTarget) async {
        guard !Task.isCancelled else { return }
        let key = CodexConversationKey(target)
        let observerID = UUID()
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                guard !Task.isCancelled else { continuation.resume(); return }
                observers[key, default: [:]][observerID] = continuation
                startPolling(target: target, key: key)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.removeObserver(observerID, for: key) }
        }
    }

    private func startPolling(target: CodexChatTarget, key: CodexConversationKey) {
        guard pollingTasks[key] == nil else { return }
        let generation = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.poll(target: target, key: key, generation: generation)
        }
        pollingTasks[key] = PollingTask(generation: generation, task: task)
    }

    private func removeObserver(_ id: UUID, for key: CodexConversationKey) {
        let continuation = observers[key]?.removeValue(forKey: id)
        if observers[key]?.isEmpty == true {
            observers.removeValue(forKey: key)
            pollingTasks.removeValue(forKey: key)?.task.cancel()
        }
        continuation?.resume()
    }

    private func poll(target: CodexChatTarget, key: CodexConversationKey, generation: UUID) async {
        defer {
            // A cancelled poller may finish after a new subscription has started.
            if pollingTasks[key]?.generation == generation { pollingTasks.removeValue(forKey: key) }
        }
        async let receipts: Void = pollReceipts(target: target)
        await pollHistory(target: target)
        _ = await receipts
    }

    private func pollReceipts(target: CodexChatTarget) async {
        while !Task.isCancelled {
            await refreshReceipts(session(for: target))
            do { try await pollingSleep(3) } catch { return }
        }
    }

    private func pollHistory(target: CodexChatTarget) async {
        while !Task.isCancelled {
            await refreshHistory(for: target)
            guard !Task.isCancelled else { return }
            let session = session(for: target)
            let interval = session.activeCount > 0 ? 3.0
                : min(24.0, (session.isBusy ? 3.0 : 8.0) * pow(2, Double(min(session.failedRefreshes, 3))))
            do { try await pollingSleep(interval) }
            catch { return }
        }
    }

    func refresh(for target: CodexChatTarget) async {
        async let receipts: Void = refreshReceipts(session(for: target))
        await refreshHistory(for: target)
        await receipts
    }

    private func refreshHistory(for target: CodexChatTarget) async {
        let session = session(for: target)
        guard !session.isRefreshing else { return }
        session.isRefreshing = true
        session.isLoading = !session.hasLoaded && session.history.isEmpty
        defer { session.isRefreshing = false; session.isLoading = false }
        do {
            let page = try await network.conversation(for: session.key, before: nil)
            guard !Task.isCancelled else { return }
            try validate(page, for: session.key)
            // Newest pages are contiguous windows. Only retain the cached prefix if the
            // new page starts inside it; disjoint windows must be paged again.
            if let firstID = page.messages.first?.displayID,
               let overlap = session.history.firstIndex(where: { $0.displayID == firstID }) {
                let currentIDs = Set(page.messages.map(\.displayID))
                let prefix = session.history[..<overlap].filter { !currentIDs.contains($0.displayID) }
                // A moved row invalidates the old opaque cursor and any in-flight older page.
                if prefix.count != overlap {
                    session.historyGeneration += 1
                    session.history = page.messages
                    session.beforeCursor = page.beforeCursor
                    session.hasLoadedOlder = false
                } else { session.history = prefix + page.messages }
            } else {
                session.historyGeneration += 1
                session.history = page.messages
                session.beforeCursor = page.beforeCursor
                session.hasLoadedOlder = false
            }
            let observedIDs = Set(page.messages.compactMap(\.clientMessageId))
            for index in session.outgoing.indices where observedIDs.contains(session.outgoing[index].id) {
                session.outgoing[index].appearedInHistory = true
            }
            session.hasLoaded = true
            session.runState = page.runState
            session.error = nil
            session.failedRefreshes = 0
            for receipt in page.receipts { try apply(receipt, to: session) }
            saveReportingFailure(session)
            try saveHistory(session)
        } catch {
            guard !Task.isCancelled else { return }
            session.error = error.localizedDescription
            session.failedRefreshes += 1
        }
    }

    func loadOlder(for target: CodexChatTarget) async {
        let session = session(for: target)
        guard let cursor = session.beforeCursor, !session.isLoadingOlder else { return }
        let generation = session.historyGeneration
        session.isLoadingOlder = true
        defer { session.isLoadingOlder = false }
        do {
            let page = try await network.conversation(for: session.key, before: cursor)
            guard !Task.isCancelled, session.historyGeneration == generation,
                  session.beforeCursor == cursor else { return }
            try validate(page, for: session.key)
            let known = Set(session.history.map(\.displayID))
            session.history = page.messages.filter { !known.contains($0.displayID) } + session.history
            session.beforeCursor = page.beforeCursor
            session.hasLoadedOlder = true
            session.error = nil
            for receipt in page.receipts { try apply(receipt, to: session) }
            saveReportingFailure(session)
            try saveHistory(session)
        } catch {
            guard !Task.isCancelled else { return }
            guard session.historyGeneration == generation, session.beforeCursor == cursor else { return }
            if case NetworkService.NetworkError.server(let code, _) = error, code == 409 {
                session.historyGeneration += 1
                session.history = []
                session.hasLoadedOlder = false
                session.beforeCursor = nil
                await refresh(for: target)
            } else { session.error = error.localizedDescription }
        }
    }

    @discardableResult
    func sendDraft(to target: CodexChatTarget, modelSettings: CodexModelSettingsModel? = nil) async -> CodexSubmissionReference? {
        let session = session(for: target)
        guard !session.draft.isEmpty, session.importingCount == 0 else { return nil }
        let draft = session.draft
        do {
            let selection = try validatedModelSelection(for: session, settings: modelSettings, hasImages: !draft.attachments.isEmpty)
            let local = try enqueue(text: draft.text, attachments: draft.attachments, selection: selection, session: session, clearDraft: true)
            let reference = recordSubmission(local.id, target: target, session: session)
            await dispatch(local.id, session: session)
            return reference
        } catch { session.draftError = error.localizedDescription; return nil }
    }

    // Canvas sends have their own immutable submission and leave the text draft intact.
    func sendDrawing(_ pngData: Data, to target: CodexChatTarget, modelSettings: CodexModelSettingsModel? = nil) async throws -> Bool {
        let session = session(for: target)
        let selection = try validatedModelSelection(for: session, settings: modelSettings, hasImages: true)
        let image = CodexImportedImage(data: pngData, name: "Canvas.png", mimeType: "image/png")
        let attachment = try persistImage(image, for: session.key)
        let local = try enqueue(text: "", attachments: [attachment], selection: selection, session: session, clearDraft: false)
        _ = recordSubmission(local.id, target: target, session: session)
        await dispatch(local.id, session: session)
        let state = session.outgoing.first { $0.id == local.id }?.state
        return state == .pending || state == .queued || state == .running || state == .completed
    }

    func retryUnaccepted(_ id: String, for target: CodexChatTarget) async {
        let session = session(for: target)
        guard let index = session.outgoing.firstIndex(where: { $0.id == id }), session.outgoing[index].canRetry else { return }
        session.outgoing[index].canRetry = false
        session.outgoing[index].state = .dispatching
        do { try save(session) }
        catch { session.outgoing[index].canRetry = true; session.draftError = error.localizedDescription; return }
        await dispatch(id, session: session)
    }

    func canReleaseWait(_ id: String, for target: CodexChatTarget) -> Bool {
        let session = session(for: target)
        guard session.queueActionID == nil else { return false }
        if let receipt = session.receipts[id] {
            return receipt.state == .unknown && receipt.queueBlocking != false
        }
        return session.outgoing.contains { $0.id == id && $0.state == .unknown && !$0.canRetry }
    }

    func releaseWait(_ id: String, for target: CodexChatTarget) async {
        let session = session(for: target)
        guard canReleaseWait(id, for: target) else { return }
        await changeQueueState(id, session: session, release: true)
    }

    func cancelPending(_ id: String, for target: CodexChatTarget) async {
        let session = session(for: target)
        guard session.queueActionID == nil, session.receipts[id]?.state == .pending else { return }
        await changeQueueState(id, session: session, release: false)
    }

    private func changeQueueState(_ id: String, session: CodexConversationSession, release: Bool) async {
        session.queueActionID = id
        defer { session.queueActionID = nil }
        do {
            let receipt = try await (release ? network.releaseMessageWait(id, for: session.key)
                : network.cancelPendingMessage(id, for: session.key))
            guard receipt.id == id else { throw ConversationError.wrongDestination }
            try apply(receipt, to: session)
            try save(session)
            try saveHistory(session)
            session.receiptError = nil
        } catch { session.receiptError = error.localizedDescription }
    }

    func localMessage(_ id: String?, for target: CodexChatTarget) -> CodexLocalMessage? {
        guard let id else { return nil }
        return session(for: target).outgoing.first { $0.id == id }
    }

    func receipt(_ id: String?, for target: CodexChatTarget) -> CodexMessageReceipt? {
        guard let id else { return nil }
        return session(for: target).receipts[id]
    }

    func imageData(_ attachment: CodexConversationAttachment, for target: CodexChatTarget) async throws -> Data {
        let key = CodexConversationKey(target)
        if let filename = attachment.localFilename { return try Data(contentsOf: localURL(filename, key: key)) }
        guard attachment.availability == "available", let path = attachment.assetPath else { throw ConversationError.imageUnavailable }
        let digest = SHA256.hash(data: Data(path.utf8)).map { String(format: "%02x", $0) }.joined()
        let file = directory(for: key).appendingPathComponent("asset-\(digest)")
        if FileManager.default.fileExists(atPath: file.path) { return try Data(contentsOf: file) }
        let data = try await network.conversationImage(at: path, for: key)
        try FileManager.default.createDirectory(at: directory(for: key), withIntermediateDirectories: true)
        try data.write(to: file, options: .atomic)
        return data
    }

    private func validatedModelSelection(for session: CodexConversationSession, settings: CodexModelSettingsModel?, hasImages: Bool) throws -> CodexModelSelection? {
        guard let draftSelection = session.draft.modelSelection else { return nil }
        guard let selection = draftSelection.selection else { throw ConversationError.incompleteModelSelection }
        if let settings {
            guard settings.matches(from: session.key.serverURL, hostId: session.key.hostId, threadId: session.key.threadId) else {
                throw ConversationError.invalidModelSelection("Load the model list for this chat before sending.")
            }
            if let reason = settings.validationMessage(for: draftSelection, hasImages: hasImages) {
                throw ConversationError.invalidModelSelection(reason)
            }
        }
        return selection
    }

    private func enqueue(text: String, attachments: [CodexDraftAttachment], selection: CodexModelSelection?, session: CodexConversationSession, clearDraft: Bool) throws -> CodexLocalMessage {
        guard text.utf16.count <= 20_000 else { throw ConversationError.textTooLong }
        let local = CodexLocalMessage(id: UUID().uuidString.lowercased(), text: text, attachments: attachments,
                                      createdAt: Date(), state: .dispatching, selection: selection)
        let previousDraft = session.draft
        session.outgoing.append(local)
        if clearDraft { session.draft = CodexMessageDraft(modelSelection: previousDraft.modelSelection) }
        do { try save(session) }
        catch {
            session.outgoing.removeAll { $0.id == local.id }
            session.draft = previousDraft
            throw error
        }
        session.draftError = nil
        return local
    }

    private func recordSubmission(_ id: String, target: CodexChatTarget, session: CodexConversationSession) -> CodexSubmissionReference {
        let reference = CodexSubmissionReference(id: id, target: target)
        lastSubmission = reference
        do { try JSONEncoder().encode(reference).write(to: storageRoot.appendingPathComponent("last-submission.json"), options: .atomic) }
        catch { session.draftError = "The request is saved in its chat, but the workspace status reference could not be saved." }
        return reference
    }

    private func dispatch(_ id: String, session: CodexConversationSession) async {
        guard let local = session.outgoing.first(where: { $0.id == id }) else { return }
        do {
            let attachments = try local.attachments.map { image in
                let bytes = try Data(contentsOf: localURL(image.filename, key: session.key))
                return CodexMessageRequest.Attachment(id: image.id, name: image.name, mimeType: image.mimeType, dataBase64: bytes.base64EncodedString())
            }
            let body = CodexMessageRequest(id: id, hostId: session.key.hostId, threadId: session.key.threadId,
                                          text: local.text, attachments: attachments, selection: local.selection)
            let receipt = try await network.sendMessage(body, for: session.key)
            guard receipt.id == id else { throw ConversationError.wrongDestination }
            try apply(receipt, to: session)
        } catch {
            guard let index = session.outgoing.firstIndex(where: { $0.id == id }) else { return }
            session.outgoing[index].state = .unknown
            session.outgoing[index].notice = "Delivery is being checked. This message will not be sent again automatically."
            session.outgoing[index].error = nil
            // Even a timeout or cancellation may follow successful admission. Only a
            // receipt lookup returning 404 enables an explicit retry with the same ID.
            await reconcile(id, session: session)
        }
        saveReportingFailure(session)
    }

    private func refreshReceipts(_ session: CodexConversationSession) async {
        // Receipt storage remains available while Desktop history is offline.
        // Skip a live POST because its receipt read could outrun admission.
        let ids = session.outgoing.filter { !$0.state.isTerminal && $0.state != .dispatching && !$0.canRetry }.map(\.id)
        guard !ids.isEmpty else { return }
        session.receiptError = nil
        await withTaskGroup(of: Void.self) { group in
            var pending = ids.makeIterator()
            for _ in 0..<min(4, ids.count) {
                if let id = pending.next() {
                    group.addTask { @MainActor in await self.reconcile(id, session: session) }
                }
            }
            while await group.next() != nil {
                saveReportingFailure(session)
                if !Task.isCancelled, let id = pending.next() {
                    group.addTask { @MainActor in await self.reconcile(id, session: session) }
                }
            }
        }
        do { try saveHistory(session) }
        catch { session.receiptError = "Could not save message receipts. \(error.localizedDescription)" }
    }

    private func reconcile(_ id: String, session: CodexConversationSession) async {
        let readKey = "\(session.key.storageID):\(id)"
        guard receiptReads.insert(readKey).inserted else { return }
        defer { receiptReads.remove(readKey) }
        do {
            let receipt = try await network.messageReceipt(id, for: session.key)
            guard !Task.isCancelled else { return }
            guard receipt.id == id else { throw ConversationError.wrongDestination }
            try apply(receipt, to: session)
        } catch {
            guard let index = session.outgoing.firstIndex(where: { $0.id == id }) else { return }
            if case NetworkService.NetworkError.server(let code, _) = error, code == 404 {
                if session.outgoing[index].sourceCreationID != nil {
                    session.outgoing[index].notice = "The original first-message receipt is unavailable. Check the creation record or this chat in Codex in ChatGPT Desktop before sending again."
                    return
                }
                session.outgoing[index].state = .failed
                session.outgoing[index].canRetry = true
                session.outgoing[index].notice = nil
                session.outgoing[index].error = "The server has not accepted this message. You can try sending it again."
            } else { session.receiptError = error.localizedDescription }
        }
    }

    private func apply(_ receipt: CodexMessageReceipt, to session: CodexConversationSession) throws {
        guard receipt.hostId == session.key.hostId, receipt.threadId == session.key.threadId else { throw ConversationError.wrongDestination }
        if let previous = session.receipts[receipt.id], previous.updatedAt > receipt.updatedAt { return }
        session.receipts[receipt.id] = receipt
        if let index = session.outgoing.firstIndex(where: { $0.id == receipt.id }) {
            session.outgoing[index].state = receipt.state
            session.outgoing[index].error = receipt.error
            session.outgoing[index].notice = receipt.notice
            session.outgoing[index].canRetry = false
        }
    }

    private func validate(_ page: CodexConversationPage, for key: CodexConversationKey) throws {
        guard page.hostId == key.hostId, page.threadId == key.threadId,
              page.receipts.allSatisfy({ $0.hostId == key.hostId && $0.threadId == key.threadId }),
              Set(page.messages.map(\.displayID)).count == page.messages.count else { throw ConversationError.wrongDestination }
    }

    private func persistImage(_ image: CodexImportedImage, for key: CodexConversationKey) throws -> CodexDraftAttachment {
        guard image.data.count <= CodexAttachmentImporter.maximumImageBytes else { throw CodexAttachmentImporter.ImportError.tooLarge }
        let id = UUID().uuidString.lowercased()
        let filename = id + (image.mimeType == "image/png" ? ".png" : ".jpg")
        try FileManager.default.createDirectory(at: directory(for: key), withIntermediateDirectories: true)
        try image.data.write(to: localURL(filename, key: key), options: .atomic)
        return CodexDraftAttachment(id: id, name: image.name, mimeType: image.mimeType, byteCount: image.data.count, filename: filename)
    }

    private func directory(for key: CodexConversationKey) -> URL { storageRoot.appendingPathComponent(key.storageID, isDirectory: true) }
    private func localURL(_ filename: String, key: CodexConversationKey) throws -> URL {
        guard filename == URL(fileURLWithPath: filename).lastPathComponent, !filename.contains("..") else { throw ConversationError.imageUnavailable }
        return directory(for: key).appendingPathComponent(filename)
    }

    // Explicit recovery preserves unreadable request IDs before replacing any bytes.
    // A failed copy leaves both the source file and the write protection intact.
    func preserveUnreadableState(for target: CodexChatTarget) throws {
        let session = session(for: target)
        guard session.stateRestorationFailed else { return }
        try preserveOriginal("state.json", for: session)
        session.stateRestorationFailed = false
        do { try save(session); session.draftError = nil }
        catch { session.stateRestorationFailed = true; throw error }
    }

    private func preserveOriginal(_ filename: String, for session: CodexConversationSession) throws {
        let source = directory(for: session.key).appendingPathComponent(filename)
        let backup = source.appendingPathExtension("recovery-\(UUID().uuidString)")
        try FileManager.default.copyItem(at: source, to: backup)
        guard try Data(contentsOf: source) == Data(contentsOf: backup) else { throw ConversationError.protectedState }
    }

    private func save(_ session: CodexConversationSession) throws {
        guard !session.stateRestorationFailed else { throw ConversationError.protectedState }
        let directory = directory(for: session.key)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let saved = SavedConversation(version: 2, draft: session.draft, outgoing: session.outgoing,
                                      readingMessageID: session.readingMessageID, isAtBottom: session.isAtBottom,
                                      recoveredDrafts: session.recoveredDrafts, handedOffCreationIDs: Array(session.handedOffCreationIDs),
                                      readingBlockID: session.readingBlockID, readingBlockFraction: session.readingBlockFraction)
        try JSONEncoder().encode(saved).write(to: directory.appendingPathComponent("state.json"), options: .atomic)
    }

    private func saveReportingFailure(_ session: CodexConversationSession) {
        do { try save(session) }
        catch { session.draftError = session.stateRestorationFailed ? error.localizedDescription : "Could not save this chat on the iPad. Keep the app open and free some storage before sending." }
    }

    private func saveHistory(_ session: CodexConversationSession) throws {
        let directory = directory(for: session.key)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if session.historyRestorationFailed {
            try preserveOriginal("history.json", for: session)
            session.historyRestorationFailed = false
        }
        let saved = SavedHistory(version: 2, messages: session.history, beforeCursor: session.beforeCursor, hasLoadedOlder: session.hasLoadedOlder, receipts: Array(session.receipts.values))
        try JSONEncoder().encode(saved).write(to: directory.appendingPathComponent("history.json"), options: .atomic)
    }

    private struct SavedHistory: Codable {
        let version: Int?
        let messages: [CodexConversationMessage]
        let beforeCursor: String?
        let hasLoadedOlder: Bool
        let receipts: [CodexMessageReceipt]?
    }

    private struct PollingTask {
        let generation: UUID
        let task: Task<Void, Never>
    }

    private struct SavedConversation: Codable {
        let version: Int?
        let draft: CodexMessageDraft
        let outgoing: [CodexLocalMessage]
        let readingMessageID: String?
        let isAtBottom: Bool
        var recoveredDrafts: [CodexRecoveredDraft]? = nil
        var handedOffCreationIDs: [String]? = nil
        var readingBlockID: String? = nil
        var readingBlockFraction: Double? = nil
    }

    enum ConversationError: LocalizedError {
        case wrongDestination, textTooLong, imageUnavailable, incompleteModelSelection, protectedState, unsupportedStorageVersion, duplicateStoredID
        case invalidModelSelection(String)
        var errorDescription: String? {
            switch self {
            case .protectedState: "The saved requests could not be restored. Preserve the original file before continuing."
            case .unsupportedStorageVersion: "This saved chat uses an unsupported storage version."
            case .duplicateStoredID: "This saved chat contains duplicate request IDs."
            case .wrongDestination: "The server returned data for a different chat. No message was moved."
            case .textTooLong: "Keep each message under 20,000 characters."
            case .imageUnavailable: "This image is no longer available."
            case .incompleteModelSelection: "Choose a model and reasoning effort before sending."
            case .invalidModelSelection(let reason): reason
            }
        }
    }
}
