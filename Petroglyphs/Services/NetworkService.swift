import Foundation

struct NetworkService {
    nonisolated init() {}

    @discardableResult
    func submit(_ payload: SubmissionPayload, to serverURL: URL) async throws -> SubmissionResponse {
        let url = serverURL.appendingPathComponent("api/submit")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        request.timeoutInterval = 20

        let (data, response) = try await BridgeTransport.shared.data(for: request)
        try validate(response, data: data)
        return try JSONDecoder().decode(SubmissionResponse.self, from: data)
    }

    func codexSubmission(_ id: String, hostId: String, from serverURL: URL) async throws -> CodexSubmissionStatus {
        let endpoint = serverURL.appendingPathComponent("api/codex/submissions").appendingPathComponent(id)
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw NetworkError.badResponse
        }
        components.queryItems = [URLQueryItem(name: "hostId", value: hostId)]
        guard let url = components.url else { throw NetworkError.badResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 20
        let (data, response) = try await BridgeTransport.shared.data(for: request)
        try validate(response, data: data)
        return try JSONDecoder().decode(CodexSubmissionStatus.self, from: data)
    }

    func recentCodexSubmissions(threadId: String, hostId: String, from serverURL: URL) async throws -> [CodexRecentSubmission] {
        let endpoint = serverURL.appendingPathComponent("api/codex/submissions")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw NetworkError.badResponse
        }
        components.queryItems = [
            URLQueryItem(name: "threadId", value: threadId),
            URLQueryItem(name: "hostId", value: hostId)
        ]
        guard let url = components.url else { throw NetworkError.badResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 20
        let (data, response) = try await BridgeTransport.shared.data(for: request)
        try validate(response, data: data)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid submission timestamp.")
        }
        return try decoder.decode(CodexRecentSubmissions.self, from: data).submissions
    }

    func codexHosts(from serverURL: URL) async throws -> [CodexHost] {
        let url = serverURL.appendingPathComponent("api/codex/hosts")
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 10
        let (data, response) = try await BridgeTransport.shared.data(for: request)
        try validate(response, data: data)
        return try JSONDecoder().decode(CodexHostList.self, from: data).hosts
    }

    func codexThreads(from serverURL: URL, hostId: String, search: String, cursor: String? = nil) async throws -> CodexThreadPage {
        let endpoint = serverURL.appendingPathComponent("api/codex/threads")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else {
            throw NetworkError.badResponse
        }
        var items = [URLQueryItem(name: "hostId", value: hostId), URLQueryItem(name: "search", value: search)]
        if let cursor {
            items.append(URLQueryItem(name: "cursor", value: cursor))
        }
        components.queryItems = items
        guard let url = components.url else { throw NetworkError.badResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 20
        let (data, response) = try await BridgeTransport.shared.data(for: request)
        try validate(response, data: data)
        return try JSONDecoder().decode(CodexThreadPage.self, from: data)
    }

    func healthCheck(_ serverURL: URL) async throws -> HealthResponse {
        try await BridgeTransport.shared.connect(to: serverURL, force: true).health
    }

    func validateCode(_ code: String, serverURL: URL) async throws {
        let base = serverURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/api/validate-code?code=\(code)") else {
            throw NetworkError.badResponse
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        let (_, response) = try await BridgeTransport.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NetworkError.invalidCode
        }
    }

    private func validate(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw NetworkError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let failure = try? JSONDecoder().decode(ServerFailure.self, from: data)
            throw NetworkError.server(
                statusCode: http.statusCode,
                message: failure?.error ?? "Server returned an error (\(http.statusCode))."
            )
        }
    }

    private struct ServerFailure: Decodable {
        let error: String
    }

    enum NetworkError: LocalizedError {
        case badResponse
        case invalidCode
        case server(statusCode: Int, message: String)
        var errorDescription: String? {
            switch self {
            case .badResponse: "Server returned an error."
            case .invalidCode: "Invalid pairing code."
            case .server(_, let message): message
            }
        }
    }
}
