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
    var beforeCursor: String?
    var runState = "unknown"
    var receipts: [String: CodexMessageReceipt] = [:]
    var failedRefreshes = 0
    var isLoading = false
    var isRefreshing = false
    var isLoadingOlder = false
    var hasLoaded = false
    var hasLoadedOlder = false
    var error: String?
    var draftError: String?
    var importingCount = 0
    var isAtBottom = true
    var readingMessageID: String?

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
    private var sessions: [CodexConversationKey: CodexConversationSession] = [:]
    @ObservationIgnored private let network: any CodexConversationNetworking
    @ObservationIgnored private let storageRoot: URL

    init(network: any CodexConversationNetworking = NetworkService(), storageRoot: URL? = nil) {
        self.network = network
        self.storageRoot = storageRoot ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexConversations", isDirectory: true)
    }

    func session(for target: CodexChatTarget) -> CodexConversationSession {
        let key = CodexConversationKey(target)
        if let session = sessions[key] { return session }
        let session = CodexConversationSession(key: key)
        do {
            let path = directory(for: key).appendingPathComponent("state.json")
            if FileManager.default.fileExists(atPath: path.path) {
                let stored = try JSONDecoder().decode(SavedConversation.self, from: Data(contentsOf: path))
                session.draft = stored.draft
                session.outgoing = stored.outgoing.map { item in
                    var item = item
                    if !item.state.isTerminal && !item.canRetry { item.state = .unknown }
                    return item
                }
                session.readingMessageID = stored.readingMessageID
                session.isAtBottom = stored.isAtBottom
            }
            let historyPath = directory(for: key).appendingPathComponent("history.json")
            if FileManager.default.fileExists(atPath: historyPath.path) {
                let saved = try JSONDecoder().decode(SavedHistory.self, from: Data(contentsOf: historyPath))
                session.history = saved.messages
                session.beforeCursor = saved.beforeCursor
                session.hasLoadedOlder = saved.hasLoadedOlder
                session.hasLoaded = true
                session.receipts = Dictionary(uniqueKeysWithValues: (saved.receipts ?? []).map { ($0.id, $0) })
            }
        } catch {
            session.draftError = "Could not restore this chat’s draft. The saved file has been kept."
        }
        sessions[key] = session
        return session
    }

    func setDraftText(_ text: String, for target: CodexChatTarget) {
        let session = session(for: target)
        session.draft.text = text
        saveReportingFailure(session)
    }

    func setReadingPosition(_ id: String?, atBottom: Bool, for target: CodexChatTarget) {
        let session = session(for: target)
        guard session.readingMessageID != id || session.isAtBottom != atBottom else { return }
        session.readingMessageID = id
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
        while !Task.isCancelled {
            await refresh(for: target)
            let session = session(for: target)
            let interval = min(24.0, (session.isBusy || session.activeCount > 0 ? 3.0 : 8.0) * pow(2, Double(min(session.failedRefreshes, 3))))
            do { try await Task.sleep(for: .seconds(interval)) }
            catch { return }
        }
    }

    func refresh(for target: CodexChatTarget) async {
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
                session.history = Array(session.history[..<overlap]) + page.messages
            } else {
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
            // A lost POST response is reconciled by its original ID. Reads never resend it.
            let included = Set(page.receipts.map(\.id))
            for item in session.outgoing where !item.state.isTerminal && item.state != .dispatching && !item.canRetry && !included.contains(item.id) {
                await reconcile(item.id, session: session)
                if Task.isCancelled { break }
            }
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
        session.isLoadingOlder = true
        defer { session.isLoadingOlder = false }
        do {
            let page = try await network.conversation(for: session.key, before: cursor)
            guard !Task.isCancelled else { return }
            try validate(page, for: session.key)
            let known = Set(session.history.map(\.displayID))
            session.history = page.messages.filter { !known.contains($0.displayID) } + session.history
            session.beforeCursor = page.beforeCursor
            session.hasLoadedOlder = true
            session.error = nil
            try saveHistory(session)
        } catch {
            guard !Task.isCancelled else { return }
            if case NetworkService.NetworkError.server(let code, _) = error, code == 409 {
                session.history = []
                session.hasLoadedOlder = false
                session.beforeCursor = nil
                await refresh(for: target)
            } else { session.error = error.localizedDescription }
        }
    }

    func sendDraft(to target: CodexChatTarget) async {
        let session = session(for: target)
        guard !session.draft.isEmpty, session.importingCount == 0 else { return }
        let draft = session.draft
        do {
            let local = try enqueue(text: draft.text, attachments: draft.attachments, session: session, clearDraft: true)
            await dispatch(local.id, session: session)
        } catch { session.draftError = error.localizedDescription }
    }

    // Canvas sends have their own immutable submission and leave the text draft intact.
    func sendDrawing(_ pngData: Data, to target: CodexChatTarget) async throws -> Bool {
        let session = session(for: target)
        let image = CodexImportedImage(data: pngData, name: "Canvas.png", mimeType: "image/png")
        let attachment = try persistImage(image, for: session.key)
        let local = try enqueue(text: "", attachments: [attachment], session: session, clearDraft: false)
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

    private func enqueue(text: String, attachments: [CodexDraftAttachment], session: CodexConversationSession, clearDraft: Bool) throws -> CodexLocalMessage {
        guard text.utf16.count <= 20_000 else { throw ConversationError.textTooLong }
        let local = CodexLocalMessage(id: UUID().uuidString.lowercased(), text: text, attachments: attachments,
                                      createdAt: Date(), state: .dispatching)
        let previousDraft = session.draft
        session.outgoing.append(local)
        if clearDraft { session.draft = CodexMessageDraft() }
        do { try save(session) }
        catch {
            session.outgoing.removeAll { $0.id == local.id }
            session.draft = previousDraft
            throw error
        }
        session.draftError = nil
        return local
    }

    private func dispatch(_ id: String, session: CodexConversationSession) async {
        guard let local = session.outgoing.first(where: { $0.id == id }) else { return }
        do {
            let attachments = try local.attachments.map { image in
                let bytes = try Data(contentsOf: localURL(image.filename, key: session.key))
                return CodexMessageRequest.Attachment(id: image.id, name: image.name, mimeType: image.mimeType, dataBase64: bytes.base64EncodedString())
            }
            let body = CodexMessageRequest(id: id, hostId: session.key.hostId, threadId: session.key.threadId,
                                          text: local.text, attachments: attachments)
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

    private func reconcile(_ id: String, session: CodexConversationSession) async {
        do {
            let receipt = try await network.messageReceipt(id, for: session.key)
            guard receipt.id == id else { throw ConversationError.wrongDestination }
            try apply(receipt, to: session)
        } catch {
            guard let index = session.outgoing.firstIndex(where: { $0.id == id }) else { return }
            if case NetworkService.NetworkError.server(let code, _) = error, code == 404 {
                session.outgoing[index].state = .failed
                session.outgoing[index].canRetry = true
                session.outgoing[index].notice = nil
                session.outgoing[index].error = "The server has not accepted this message. You can try sending it again."
            }
        }
    }

    private func apply(_ receipt: CodexMessageReceipt, to session: CodexConversationSession) throws {
        guard receipt.hostId == session.key.hostId, receipt.threadId == session.key.threadId else { throw ConversationError.wrongDestination }
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

    private func save(_ session: CodexConversationSession) throws {
        let directory = directory(for: session.key)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let saved = SavedConversation(draft: session.draft, outgoing: session.outgoing,
                                      readingMessageID: session.readingMessageID, isAtBottom: session.isAtBottom)
        try JSONEncoder().encode(saved).write(to: directory.appendingPathComponent("state.json"), options: .atomic)
    }

    private func saveReportingFailure(_ session: CodexConversationSession) {
        do { try save(session) }
        catch { session.draftError = "Could not save this chat on the iPad. Keep the app open and free some storage before sending." }
    }

    private func saveHistory(_ session: CodexConversationSession) throws {
        let directory = directory(for: session.key)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let saved = SavedHistory(messages: session.history, beforeCursor: session.beforeCursor, hasLoadedOlder: session.hasLoadedOlder, receipts: Array(session.receipts.values))
        try JSONEncoder().encode(saved).write(to: directory.appendingPathComponent("history.json"), options: .atomic)
    }

    private struct SavedHistory: Codable {
        let messages: [CodexConversationMessage]
        let beforeCursor: String?
        let hasLoadedOlder: Bool
        let receipts: [CodexMessageReceipt]?
    }

    private struct SavedConversation: Codable {
        let draft: CodexMessageDraft
        let outgoing: [CodexLocalMessage]
        let readingMessageID: String?
        let isAtBottom: Bool
    }

    enum ConversationError: LocalizedError {
        case wrongDestination, textTooLong, imageUnavailable
        var errorDescription: String? {
            switch self {
            case .wrongDestination: "The server returned data for a different chat. No message was moved."
            case .textTooLong: "Keep each message under 20,000 characters."
            case .imageUnavailable: "This image is no longer available."
            }
        }
    }
}
