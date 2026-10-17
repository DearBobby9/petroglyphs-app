import Foundation
import Observation

protocol CodexTargetAvailabilityNetworking {
    func codexHosts(from serverURL: URL) async throws -> [CodexHost]
    func codexModelSettings(from serverURL: URL, hostId: String, threadId: String) async throws -> CodexThreadModelSettings
}

extension NetworkService: CodexTargetAvailabilityNetworking {}

@MainActor
@Observable
final class CodexTargetAvailabilityModel {
    private(set) var target: CodexChatTarget?
    private(set) var error: String?
    private(set) var isLoading = false
    @ObservationIgnored private let network: any CodexTargetAvailabilityNetworking
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var context: Context?

    init(network: any CodexTargetAvailabilityNetworking = NetworkService()) { self.network = network }

    func matches(_ target: CodexChatTarget?) -> Bool { target.map { context == Context($0) } ?? false }

    func refresh(for original: CodexChatTarget) async -> CodexChatTarget? {
        let id = UUID()
        requestID = id
        context = Context(original)
        target = nil
        error = nil
        isLoading = true
        defer { if requestID == id { isLoading = false } }
        let hosts: [CodexHost]
        do { hosts = try await network.codexHosts(from: original.serverURL) }
        catch {
            guard requestID == id, !Task.isCancelled else { return nil }
            self.error = "The bridge Mac could not be reached. \(error.localizedDescription)"
            return nil
        }
        guard requestID == id, !Task.isCancelled else { return nil }
        guard let host = hosts.first(where: { $0.id == original.host.id }) else {
            error = "The selected execution host is no longer available from this bridge."
            return nil
        }
        let updated = CodexChatTarget(thread: original.thread, serverURL: original.serverURL, host: host,
            projectId: original.projectId, projectName: original.projectName)
        guard host.canSelect else {
            target = updated
            error = "Execution host \(host.name): \(host.unavailabilityReason ?? "Unavailable")"
            return updated
        }
        do {
            let settings = try await network.codexModelSettings(from: original.serverURL, hostId: host.id, threadId: original.thread.id)
            guard requestID == id, !Task.isCancelled else { return nil }
            guard settings.hostId == host.id, settings.threadId == original.thread.id else { throw NetworkService.NetworkError.badResponse }
            target = updated
            return updated
        } catch {
            guard requestID == id, !Task.isCancelled else { return nil }
            target = updated
            if case NetworkService.NetworkError.server(let status, _) = error, status == 404 {
                self.error = "This chat is unavailable on \(host.name). Choose another chat or open Codex in ChatGPT Desktop."
            } else {
                self.error = "The chat on \(host.name) could not be verified. \(error.localizedDescription)"
            }
            return updated
        }
    }

    private struct Context: Equatable {
        let serverURL: URL
        let hostID: String
        let threadID: String
        init(_ target: CodexChatTarget) {
            serverURL = target.serverURL
            hostID = target.host.id
            threadID = target.thread.id
        }
    }
}
