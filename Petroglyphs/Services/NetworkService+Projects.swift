import Foundation

protocol CodexThreadListNetworking {
    func codexThreads(from serverURL: URL, hostId: String, search: String, cursor: String?) async throws -> CodexThreadPage
    func codexProjectThreads(from serverURL: URL, hostId: String, projectId: String, search: String, cursor: String?) async throws -> CodexThreadPage
}

protocol CodexProjectNetworking {
    func codexProjects(from serverURL: URL, hostId: String) async throws -> CodexProjectList
    func createCodexChat(_ body: CodexCreateChatRequest, from serverURL: URL) async throws -> CodexChatCreationReceipt
    func codexChatCreation(_ body: CodexCreateChatRequest, from serverURL: URL) async throws -> CodexChatCreationReceipt
}

extension NetworkService: CodexThreadListNetworking, CodexProjectNetworking {
    func codexProjects(from serverURL: URL, hostId: String) async throws -> CodexProjectList {
        let request = try projectRequest("api/codex/projects", from: serverURL, query: [URLQueryItem(name: "hostId", value: hostId)])
        return try await readProjectJSON(request)
    }

    func codexProjectThreads(from serverURL: URL, hostId: String, projectId: String, search: String, cursor: String? = nil) async throws -> CodexThreadPage {
        var query = [URLQueryItem(name: "hostId", value: hostId), URLQueryItem(name: "projectId", value: projectId), URLQueryItem(name: "search", value: search)]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        return try await readProjectJSON(projectRequest("api/codex/threads", from: serverURL, query: query))
    }

    func createCodexChat(_ body: CodexCreateChatRequest, from serverURL: URL) async throws -> CodexChatCreationReceipt {
        var request = try projectRequest("api/codex/chats", from: serverURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await readProjectJSON(request)
    }

    func codexChatCreation(_ body: CodexCreateChatRequest, from serverURL: URL) async throws -> CodexChatCreationReceipt {
        guard UUID(uuidString: body.id) != nil else { throw NetworkError.badResponse }
        let query = [URLQueryItem(name: "hostId", value: body.hostId), URLQueryItem(name: "projectId", value: body.projectId)]
        return try await readProjectJSON(projectRequest("api/codex/chats/\(body.id)", from: serverURL, query: query))
    }

    private func projectRequest(_ path: String, from serverURL: URL, query: [URLQueryItem] = []) throws -> URLRequest {
        guard var components = URLComponents(url: serverURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw NetworkError.badResponse
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw NetworkError.badResponse }
        return URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
    }

    private func readProjectJSON<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await BridgeTransport.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let failure = try? JSONDecoder().decode(ProjectServerFailure.self, from: data)
            throw NetworkError.server(statusCode: http.statusCode, message: failure?.error ?? "The project connection returned an error (\(http.statusCode)).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct ProjectServerFailure: Decodable { let error: String }
