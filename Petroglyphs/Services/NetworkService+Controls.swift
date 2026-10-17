import Foundation

protocol CodexExecutionControlNetworking {
    func executionControls(for key: CodexConversationKey) async throws -> CodexExecutionControls
    func stopTurn(_ turnID: String, for key: CodexConversationKey) async throws -> CodexStopTurnResult
}

extension NetworkService: CodexExecutionControlNetworking {
    func executionControls(for key: CodexConversationKey) async throws -> CodexExecutionControls {
        var components = URLComponents(url: key.serverURL.appendingPathComponent("api/codex/controls"), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "hostId", value: key.hostId), URLQueryItem(name: "threadId", value: key.threadId)]
        guard let url = components?.url else { throw NetworkError.badResponse }
        return try await readControl(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15))
    }

    func stopTurn(_ turnID: String, for key: CodexConversationKey) async throws -> CodexStopTurnResult {
        struct StopRequest: Encodable { let hostId: String; let threadId: String; let turnId: String }
        var request = URLRequest(url: key.serverURL.appendingPathComponent("api/codex/controls/stop"), timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(StopRequest(hostId: key.hostId, threadId: key.threadId, turnId: turnID))
        return try await readControl(request)
    }

    private func readControl<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await BridgeTransport.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw NetworkError.badResponse }
        guard (200..<300).contains(response.statusCode) else {
            let failure = try? JSONDecoder().decode(ControlFailure.self, from: data)
            throw NetworkError.server(statusCode: response.statusCode, message: failure?.error ?? failure?.code ?? "Execution controls are unavailable. Check this chat in Codex in ChatGPT Desktop.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

private struct ControlFailure: Decodable { let error: String?; let code: String? }
