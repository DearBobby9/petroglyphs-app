import Foundation

protocol CodexModelSettingsNetworking {
    func codexModels(from serverURL: URL, hostId: String) async throws -> CodexModelCatalog
    func codexModelSettings(from serverURL: URL, hostId: String, threadId: String) async throws -> CodexThreadModelSettings
}

extension NetworkService: CodexModelSettingsNetworking {
    func codexModels(from serverURL: URL, hostId: String) async throws -> CodexModelCatalog {
        let request = try modelSettingsRequest("api/codex/models", from: serverURL,
            query: [URLQueryItem(name: "hostId", value: hostId)])
        return try await readModelSettingsJSON(request)
    }

    func codexModelSettings(from serverURL: URL, hostId: String, threadId: String) async throws -> CodexThreadModelSettings {
        let request = try modelSettingsRequest("api/codex/model-settings", from: serverURL,
            query: [URLQueryItem(name: "hostId", value: hostId), URLQueryItem(name: "threadId", value: threadId)])
        return try await readModelSettingsJSON(request)
    }

    private func modelSettingsRequest(_ path: String, from serverURL: URL, query: [URLQueryItem]) throws -> URLRequest {
        guard var components = URLComponents(url: serverURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
            throw NetworkError.badResponse
        }
        components.queryItems = query
        guard let url = components.url else { throw NetworkError.badResponse }
        return URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
    }

    private func readModelSettingsJSON<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await BridgeTransport.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw NetworkError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let failure = try? JSONDecoder().decode(ModelSettingsServerFailure.self, from: data)
            throw NetworkError.server(statusCode: http.statusCode,
                message: failure?.error ?? "The model settings connection returned an error (\(http.statusCode)).")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct ModelSettingsServerFailure: Decodable { let error: String }
