import Foundation
import Observation

@MainActor
@Observable
final class CodexThreadListModel {
    private(set) var threads: [CodexThread] = []
    private(set) var nextCursor: String?
    private(set) var isLoading = true
    private(set) var isLoadingMore = false
    private(set) var error: String?
    private(set) var paginationError: String?

    @ObservationIgnored private let network: any CodexThreadListNetworking
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var serverURL: URL?
    private(set) var hostId: String?
    private(set) var projectId: String?
    @ObservationIgnored private var search = ""

    init(network: any CodexThreadListNetworking = NetworkService()) { self.network = network }

    func load(from serverURL: URL, hostId: String, projectId: String? = nil, search: String, debounce: Bool = true) async {
        let id = UUID()
        requestID = id
        self.serverURL = serverURL
        self.hostId = hostId
        self.projectId = projectId
        self.search = search
        threads = []
        nextCursor = nil
        error = nil
        paginationError = nil
        isLoading = true
        isLoadingMore = false
        defer {
            if requestID == id { isLoading = false }
        }

        do {
            if debounce && !search.isEmpty {
                try await Task.sleep(for: .milliseconds(250))
            }
            try Task.checkCancellation()
            let page = try await page(from: serverURL, hostId: hostId, projectId: projectId, search: search)
            guard requestID == id, !Task.isCancelled else { return }
            threads = page.threads
            nextCursor = page.nextCursor
        } catch {
            guard requestID == id, !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }

    func loadMore() async {
        guard !isLoading, !isLoadingMore, let serverURL, let hostId, let cursor = nextCursor else { return }
        let id = requestID
        let query = search
        let project = projectId
        isLoadingMore = true
        paginationError = nil
        defer {
            if requestID == id { isLoadingMore = false }
        }

        do {
            let page = try await page(from: serverURL, hostId: hostId, projectId: project, search: query, cursor: cursor)
            guard requestID == id, !Task.isCancelled else { return }
            var knownIDs = Set(threads.map(\.id))
            threads.append(contentsOf: page.threads.filter { knownIDs.insert($0.id).inserted })
            nextCursor = page.nextCursor
        } catch {
            guard requestID == id, !Task.isCancelled else { return }
            paginationError = error.localizedDescription
        }
    }

    private func page(from serverURL: URL, hostId: String, projectId: String?, search: String, cursor: String? = nil) async throws -> CodexThreadPage {
        if let projectId {
            return try await network.codexProjectThreads(from: serverURL, hostId: hostId, projectId: projectId, search: search, cursor: cursor)
        }
        return try await network.codexThreads(from: serverURL, hostId: hostId, search: search, cursor: cursor)
    }
}
