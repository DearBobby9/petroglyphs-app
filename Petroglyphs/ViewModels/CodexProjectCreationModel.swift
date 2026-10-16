import CryptoKit
import Foundation
import Observation

@MainActor
@Observable
final class CodexProjectCreationModel {
    let project: CodexProject
    let host: CodexHost
    var title = ""
    var prompt = ""
    private(set) var request: CodexCreateChatRequest?
    private(set) var receipt: CodexChatCreationReceipt?
    private(set) var isSubmitting = false
    private(set) var isChecking = false
    private(set) var error: String?
    private(set) var isConfirmedMissing = false
    private(set) var storageError: String?

    @ObservationIgnored private let serverURL: URL
    @ObservationIgnored private let network: any CodexProjectNetworking
    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var restorationFailed = false

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

    var isBusy: Bool { isSubmitting || isChecking }
    var createdThread: CodexThread? { receipt?.state == .completed ? receipt?.thread : nil }
    var canSubmit: Bool {
        project.canCreate && host.canSelect && request == nil && !isBusy && !restorationFailed
            && title.utf16.count <= 120 && prompt.utf16.count <= 20_000
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    var canRetryOriginal: Bool { project.canCreate && host.canSelect && isConfirmedMissing && request != nil && !isBusy && storageError == nil }
    var canEditFailedAttempt: Bool { receipt?.state == .failed && !isBusy }

    var status: String? {
        if isSubmitting { return "Creating chat…" }
        if isChecking { return "Checking creation status…" }
        if isConfirmedMissing { return "The bridge has no record of this request. You can retry the same request." }
        switch receipt?.state {
        case .pending, .creating: return "The chat is being created. Check its status before starting another request."
        case .completed: return "Chat created."
        case .failed: return "The chat could not be created."
        case .unknown: return "Creation is not confirmed. Check its status to find the existing request."
        case nil: return request == nil ? nil : "Creation is not confirmed. Check its status to find the existing request."
        }
    }

    func submit() async {
        guard canSubmit else { return }
        let cleanedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        request = CodexCreateChatRequest(id: UUID().uuidString.lowercased(), hostId: host.id, projectId: project.id,
                                         prompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
                                         title: cleanedTitle.isEmpty ? nil : cleanedTitle)
        // Save before issuing the POST so dismissing or relaunching never generates a
        // second request after an ambiguous network result.
        guard save() else { request = nil; return }
        await postOriginal()
    }

    func retryOriginal() async {
        guard canRetryOriginal else { return }
        await postOriginal()
    }

    func checkStatus() async {
        guard !isBusy, let request else { return }
        isChecking = true
        isConfirmedMissing = false
        error = nil
        defer { isChecking = false }
        do {
            try apply(await network.codexChatCreation(request, from: serverURL), for: request)
        } catch NetworkService.NetworkError.server(let code, let message) where code == 404 {
            isConfirmedMissing = true
            error = message
        } catch {
            self.error = error.localizedDescription
        }
    }

    func acknowledgeCompletion() {
        guard createdThread != nil else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    func editFailedAttempt() {
        guard canEditFailedAttempt else { return }
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
            // The bridge reserves failed for requests that never crossed the native
            // creation boundary. A new attempt still requires an explicit Start chat.
            request = nil
            receipt = nil
            isConfirmedMissing = false
            error = nil
            storageError = nil
        } catch {
            storageError = "The failed request could not be cleared. Its saved record has been kept."
        }
    }

    private func postOriginal() async {
        guard !isBusy, let request else { return }
        isSubmitting = true
        isConfirmedMissing = false
        receipt = nil
        error = nil
        do {
            try apply(await network.createCodexChat(request, from: serverURL), for: request)
        } catch {
            self.error = error.localizedDescription
        }
        isSubmitting = false
        if receipt == nil { await checkStatus() }
    }

    private func apply(_ result: CodexChatCreationReceipt, for request: CodexCreateChatRequest) throws {
        guard result.id == request.id, result.hostId == host.id, result.projectId == project.id,
              result.state != .completed || result.thread != nil else { throw NetworkService.NetworkError.badResponse }
        receipt = result
        isConfirmedMissing = false
        error = result.error
        _ = save()
    }

    private func restore() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let saved = try JSONDecoder().decode(SavedCreation.self, from: Data(contentsOf: fileURL))
            guard saved.request.hostId == host.id, saved.request.projectId == project.id else {
                throw NetworkService.NetworkError.badResponse
            }
            request = saved.request
            receipt = saved.receipt
            title = saved.request.title ?? ""
            prompt = saved.request.prompt
            error = saved.receipt?.error
        } catch {
            restorationFailed = true
            storageError = "The previous creation request could not be restored. Its saved record has been kept."
        }
    }

    @discardableResult
    private func save() -> Bool {
        guard let request else { return false }
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(SavedCreation(request: request, receipt: receipt))
            try data.write(to: fileURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            storageError = nil
            return true
        } catch {
            storageError = "The creation request could not be saved on this iPad. Try again after freeing storage."
            return false
        }
    }

    private struct SavedCreation: Codable {
        let request: CodexCreateChatRequest
        let receipt: CodexChatCreationReceipt?
    }
}
