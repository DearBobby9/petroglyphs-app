import CryptoKit
import Foundation
import Observation

@MainActor
@Observable
final class CodexProjectCreationModel {
    let project: CodexProject
    let host: CodexHost
    var title = "" { didSet { saveDraftChange() } }
    var prompt = "" { didSet { saveDraftChange() } }
    var modelSelection: CodexDraftModelSelection? { didSet { saveDraftChange() } }
    private(set) var request: CodexCreateChatRequest?
    private(set) var receipt: CodexChatCreationReceipt?
    private(set) var isSubmitting = false
    private(set) var isChecking = false
    private(set) var isRetrying = false
    private(set) var retryPendingAttemptId: String?
    private(set) var error: String?
    private(set) var isConfirmedMissing = false
    private(set) var storageError: String?
    private(set) var isObservingCreation = false
    private(set) var statusChecksPaused = false
    private var statusObservationGeneration = 0

    @ObservationIgnored let serverURL: URL
    @ObservationIgnored private let network: any CodexProjectNetworking
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var restorationFailed = false
    @ObservationIgnored private var isRestoring = false
    @ObservationIgnored private var activeStatusObserver: UUID?
    @ObservationIgnored private var localValidationRejection = false
    @ObservationIgnored private var hasOpenedChat = false

    init(project: CodexProject, host: CodexHost, serverURL: URL,
         network: any CodexProjectNetworking = NetworkService(), storageRoot: URL? = nil) {
        self.project = project
        self.host = host
        self.serverURL = serverURL
        self.network = network
        let root = storageRoot ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CodexProjectCreations", isDirectory: true)
        let key = Data("\(serverURL.absoluteString)\n\(host.id)\n\(project.id)".utf8)
        let name = SHA256.hash(data: key).map { String(format: "%02x", $0) }.joined()
        fileURL = root.appendingPathComponent(name).appendingPathExtension("json")
        restore()
    }

    var isBusy: Bool { isSubmitting || isChecking || isRetrying }
    var statusObservationID: String? { request.map { "\($0.id):\(statusObservationGeneration)" } }
    var createdThread: CodexThread? { receipt?.state == .completed ? receipt?.thread : nil }
    var recoverableThread: CodexThread? { receipt?.state == .unknown ? receipt?.thread : nil }
    var canSubmit: Bool {
        project.canCreate && host.canSelect && request == nil && !isBusy && !restorationFailed
            && (modelSelection == nil || modelSelection?.selection != nil)
            && title.utf16.count <= 120 && prompt.utf16.count <= 20_000
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var canRetryOriginal: Bool { project.canCreate && host.canSelect && isConfirmedMissing && request != nil && receipt?.state != .failed && receipt?.attemptId == nil && retryPendingAttemptId == nil && !isBusy && storageError == nil }
    var canRetryCreation: Bool {
        request != nil && host.canSelect && project.canCreate && !isBusy && !restorationFailed && storageError == nil
            && retryPendingAttemptId == nil && receipt?.state == .failed
            && receipt?.failureCode == "approval_review_timeout" && receipt?.canRetry == true
            && receipt?.attemptNumber == 1 && receipt?.attemptId?.isEmpty == false
    }
    var canEditFailedAttempt: Bool {
        receipt?.state == .failed && !isBusy && retryPendingAttemptId == nil
            && receipt?.failureCode != "approval_review_timeout"
    }
    var canStartNewRequest: Bool {
        request != nil && !isBusy && !restorationFailed && retryPendingAttemptId == nil
            && receipt?.state == .failed && receipt?.failureCode == "approval_review_timeout"
            && receipt?.attemptNumber == 2 && receipt?.canRetry == false
            && receipt?.attemptId?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
    private var shouldObserveCreation: Bool {
        !hasOpenedChat && createdThread == nil && !localValidationRejection && (receipt?.state != .failed || retryPendingAttemptId != nil)
    }

    var status: String? {
        if isSubmitting { return "Creating chat…" }
        if isRetrying { return "Retrying creation with the original message and model…" }
        if isChecking { return "Checking creation status…" }
        if retryPendingAttemptId != nil {
            return statusChecksPaused ? "The retry result is not confirmed. Use Check status to recover this request."
                : "The retry result is not confirmed yet. Checking the original request…"
        }
        if receipt?.state == .failed && receipt?.failureCode == "approval_review_timeout" {
            if receipt?.attemptNumber == 2 { return "Approval timed out again. This request has no retries remaining." }
            return receipt?.canRetry == true ? "Approval timed out before creation ran. You can retry this request once."
                : "Approval timed out. This request cannot be retried."
        }
        if isConfirmedMissing { return "The bridge has no record of this request. You can retry the same request." }
        if recoverableThread != nil {
            return "Chat created. The first message is not confirmed. Open this chat to check it before sending again."
        }
        if statusChecksPaused { return "Creation is not confirmed. Automatic checks have paused. Use Check status to continue." }
        switch receipt?.state {
        case .pending, .creating: return "The chat is being created. Check its status before starting another request."
        case .completed: return "Chat created."
        case .failed: return "The chat could not be created."
        case .unknown: return isObservingCreation ? "Creation is not confirmed yet. Checking the original request…" : "Creation is not confirmed. Check its status to find the existing request."
        case nil: return request == nil ? nil : "Creation is not confirmed. Check its status to find the existing request."
        }
    }

    func submit() async {
        guard canSubmit else { return }
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        request = CodexCreateChatRequest(id: UUID().uuidString.lowercased(), hostId: host.id, projectId: project.id,
                                         prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                                         title: cleanedTitle.isEmpty ? nil : cleanedTitle,
                                         selection: modelSelection?.selection)
        // Save before issuing the POST so dismissing or relaunching never generates a
        // second request after an ambiguous network result.
        guard save() else { request = nil; return }
        await postOriginal()
    }

    func retryOriginal() async {
        guard canRetryOriginal else { return }
        await postOriginal()
    }

    func retryCreation() async {
        guard canRetryCreation, let request, let attemptID = receipt?.attemptId else { return }
        isRetrying = true
        retryPendingAttemptId = attemptID
        // Persist before the POST. Restart or a lost response must reconcile this
        // attempt, rather than treat the old receipt as fresh retry permission.
        guard save() else { retryPendingAttemptId = nil; isRetrying = false; return }
        statusObservationGeneration += 1
        statusChecksPaused = false
        isConfirmedMissing = false
        error = nil
        do {
            try apply(await network.retryCodexChatCreation(request, attemptId: attemptID, from: serverURL), for: request)
        } catch {
            self.error = error.localizedDescription
        }
        isRetrying = false
        if retryPendingAttemptId != nil { await checkStatus() }
    }

    func checkStatus() async {
        guard !Task.isCancelled, !isBusy, !localValidationRejection, let request else { return }
        isChecking = true
        isConfirmedMissing = false
        error = nil
        defer { isChecking = false }
        do {
            let result = try await network.codexChatCreation(request, from: serverURL)
            guard !Task.isCancelled else { return }
            try apply(result, for: request, fromStatusRead: true)
        } catch NetworkService.NetworkError.server(let code, let message) where code == 404 {
            guard !Task.isCancelled else { return }
            isConfirmedMissing = retryPendingAttemptId == nil && receipt?.attemptId == nil && receipt?.state != .failed
            error = message
        } catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }

    func observeCreation(
        now: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        sleep: @MainActor (TimeInterval) async throws -> Void = { try await Task.sleep(for: .seconds($0)) }
    ) async {
        guard !Task.isCancelled, let requestID = request?.id, createdThread == nil, !localValidationRejection else { return }
        if receipt?.state == .failed && retryPendingAttemptId == nil {
            await checkStatus()
            guard shouldObserveCreation else { return }
        }
        let observerID = UUID()
        activeStatusObserver = observerID
        isObservingCreation = true
        statusChecksPaused = false
        // Unknown can precede a late native result. Read only the original ID;
        // monotonic uptime bounds automatic recovery even if wall time changes.
        let deadline = now() + 300
        var checks = 0
        defer {
            if activeStatusObserver == observerID {
                isObservingCreation = false
                activeStatusObserver = nil
            }
        }
        while !Task.isCancelled, activeStatusObserver == observerID, request?.id == requestID,
              shouldObserveCreation {
            guard now() < deadline else { statusChecksPaused = true; return }
            if !isBusy {
                await checkStatus()
                checks += 1
            }
            guard !Task.isCancelled, activeStatusObserver == observerID, request?.id == requestID,
                  shouldObserveCreation else { return }
            let remaining = deadline - now()
            guard remaining > 0 else { statusChecksPaused = true; return }
            do { try await sleep(min(checks < 10 ? 2 : 10, remaining)) }
            catch { return }
        }
    }

    func acknowledgeOpenedChat() {
        guard createdThread != nil || recoverableThread != nil else { return }
        hasOpenedChat = true
        activeStatusObserver = nil
        isObservingCreation = false
        try? FileManager.default.removeItem(at: fileURL)
    }

    func editFailedAttempt() {
        guard canEditFailedAttempt else { return }
        clearFailedRequestAssociation()
    }

    func startNewRequest() {
        guard canStartNewRequest, let request else { return }
        title = request.title ?? ""
        prompt = request.prompt
        modelSelection = request.selection.map { CodexDraftModelSelection(model: $0.model, reasoningEffort: $0.reasoningEffort) }
        clearFailedRequestAssociation()
    }

    private func clearFailedRequestAssociation() {
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            // Only a confirmed safe failure can reach this explicit local action.
            // The server job is retained; Start chat must create a separate request.
            request = nil
            receipt = nil
            isConfirmedMissing = false
            error = nil
            storageError = nil
            statusChecksPaused = false
            retryPendingAttemptId = nil
            localValidationRejection = false
            _ = save()
        } catch {
            storageError = "The failed request could not be cleared. Its saved record has been kept."
        }
    }

    private func postOriginal() async {
        guard !isBusy, let request else { return }
        statusObservationGeneration += 1
        statusChecksPaused = false
        isSubmitting = true
        isConfirmedMissing = false
        receipt = nil
        error = nil
        do {
            try apply(await network.createCodexChat(request, from: serverURL), for: request)
        } catch let rejection as CodexCreationRejection {
            localValidationRejection = true
            receipt = CodexChatCreationReceipt(id: request.id, hostId: request.hostId, projectId: request.projectId,
                                                state: .failed, thread: nil, error: rejection.message,
                                                notice: "Edit this draft, then start a new request.", selection: request.selection)
            error = rejection.message
            _ = save()
        } catch {
            self.error = error.localizedDescription
        }
        isSubmitting = false
        if receipt == nil { await checkStatus() }
    }

    private func apply(_ result: CodexChatCreationReceipt, for request: CodexCreateChatRequest, fromStatusRead: Bool = false) throws {
        guard result.id == request.id, result.hostId == host.id, result.projectId == project.id,
              result.state != .completed || result.thread != nil else { throw NetworkService.NetworkError.badResponse }
        if let number = result.attemptNumber, !(1...2).contains(number) { throw NetworkService.NetworkError.badResponse }
        if let previousNumber = receipt?.attemptNumber {
            guard let nextNumber = result.attemptNumber, nextNumber >= previousNumber,
                  nextNumber != previousNumber || result.attemptId == receipt?.attemptId else { throw NetworkService.NetworkError.badResponse }
        }
        if let pendingAttempt = retryPendingAttemptId {
            let advanced = result.attemptNumber == 2 && result.attemptId != nil && result.attemptId != pendingAttempt
            let closed = result.state == .failed && result.canRetry == false && result.attemptId != nil
            // A fresh GET after the POST ends may confirm that admission never
            // advanced. Repeating this token is server-idempotent, but still
            // requires another explicit user action.
            let retryStillAvailable = fromStatusRead && !isRetrying
                && result.attemptId == pendingAttempt && result.attemptNumber == 1
                && result.state == .failed && result.failureCode == "approval_review_timeout" && result.canRetry == true
            if advanced || closed || retryStillAvailable || result.state == .completed { retryPendingAttemptId = nil }
        }
        receipt = result
        localValidationRejection = false
        if result.state == .completed || result.state == .failed { statusChecksPaused = false }
        isConfirmedMissing = false
        error = result.error
        _ = save()
    }

    private func restore() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        isRestoring = true
        defer { isRestoring = false }
        do {
            let saved = try JSONDecoder().decode(SavedCreation.self, from: Data(contentsOf: fileURL))
            guard saved.request == nil || (saved.request?.hostId == host.id && saved.request?.projectId == project.id) else {
                throw NetworkService.NetworkError.badResponse
            }
            request = saved.request
            receipt = saved.receipt
            retryPendingAttemptId = saved.retryPendingAttemptId
            localValidationRejection = saved.localValidationRejection ?? false
            title = saved.request?.title ?? saved.draft?.title ?? ""
            prompt = saved.request?.prompt ?? saved.draft?.prompt ?? ""
            if let selection = saved.request?.selection {
                modelSelection = CodexDraftModelSelection(model: selection.model, reasoningEffort: selection.reasoningEffort)
            } else {
                modelSelection = saved.request == nil ? saved.draft?.modelSelection : nil
            }
            error = saved.receipt?.error
        } catch {
            restorationFailed = true
            storageError = "The previous creation request could not be restored. Its saved record has been kept."
        }
    }

    @discardableResult
    private func save() -> Bool {
        // A status read already in flight must not restore the creation draft
        // after the user has opened its confirmed existing chat.
        if hasOpenedChat { return true }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let draft = CreationDraft(title: title, prompt: prompt, modelSelection: modelSelection)
            let data = try JSONEncoder().encode(SavedCreation(request: request, receipt: receipt, draft: draft,
                                                             retryPendingAttemptId: retryPendingAttemptId,
                                                             localValidationRejection: localValidationRejection))
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            storageError = nil
            return true
        } catch {
            storageError = "The creation request could not be saved on this iPad. Try again after freeing storage."
            return false
        }
    }

    private func saveDraftChange() {
        guard !isRestoring, !restorationFailed, request == nil else { return }
        _ = save()
    }

    private struct SavedCreation: Codable {
        let request: CodexCreateChatRequest?
        let receipt: CodexChatCreationReceipt?
        var draft: CreationDraft? = nil
        var retryPendingAttemptId: String? = nil
        var localValidationRejection: Bool? = nil
    }

    private struct CreationDraft: Codable {
        let title: String
        let prompt: String
        let modelSelection: CodexDraftModelSelection?
    }
}
