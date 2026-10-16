import Foundation
import Observation

@MainActor
@Observable
final class CodexProjectListModel {
    private(set) var projects: [CodexProject] = []
    private(set) var hostId: String?
    private(set) var isLoading = true
    private(set) var error: String?

    @ObservationIgnored private let network: any CodexProjectNetworking
    @ObservationIgnored private var requestID = UUID()

    init(network: any CodexProjectNetworking = NetworkService()) { self.network = network }

    func load(from serverURL: URL, hostId: String) async {
        let id = UUID()
        requestID = id
        self.hostId = hostId
        projects = []
        error = nil
        isLoading = true
        defer { if requestID == id { isLoading = false } }
        do {
            let result = try await network.codexProjects(from: serverURL, hostId: hostId)
            guard requestID == id, !Task.isCancelled else { return }
            guard result.hostId == hostId else { throw NetworkService.NetworkError.badResponse }
            projects = result.projects
        } catch {
            guard requestID == id, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }

    func matching(_ search: String) -> [CodexProject] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return projects }
        return projects.filter { $0.displayName.localizedStandardContains(query) || $0.path.localizedStandardContains(query) }
    }
}
