import Foundation

protocol CodexConversationNetworking {
    func conversation(for key: CodexConversationKey, before: String?) async throws -> CodexConversationPage
    func sendMessage(_ body: CodexMessageRequest, for key: CodexConversationKey) async throws -> CodexMessageReceipt
    func messageReceipt(_ id: String, for key: CodexConversationKey) async throws -> CodexMessageReceipt
    func releaseMessageWait(_ id: String, for key: CodexConversationKey) async throws -> CodexMessageReceipt
    func cancelPendingMessage(_ id: String, for key: CodexConversationKey) async throws -> CodexMessageReceipt
    func conversationImage(at path: String, for key: CodexConversationKey) async throws -> Data
}

extension CodexConversationNetworking {
    func releaseMessageWait(_ id: String, for key: CodexConversationKey) async throws -> CodexMessageReceipt {
        throw NetworkService.NetworkError.server(statusCode: 501, message: "This bridge does not support releasing queue waits.")
    }
    func cancelPendingMessage(_ id: String, for key: CodexConversationKey) async throws -> CodexMessageReceipt {
        throw NetworkService.NetworkError.server(statusCode: 501, message: "This bridge does not support removing pending messages.")
    }
}

extension NetworkService: CodexConversationNetworking {
    func conversation(for key: CodexConversationKey, before: String? = nil) async throws -> CodexConversationPage {
        var query = targetQuery(key)
        query.append(URLQueryItem(name: "limit", value: "50"))
        if let before { query.append(URLQueryItem(name: "before", value: before)) }
        let request = try conversationRequest(path: "api/codex/conversation", key: key, query: query)
        return try await readConversationJSON(request)
    }

    func sendMessage(_ body: CodexMessageRequest, for key: CodexConversationKey) async throws -> CodexMessageReceipt {
        var request = try conversationRequest(path: "api/codex/messages", key: key)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await readConversationJSON(request)
    }

    func messageReceipt(_ id: String, for key: CodexConversationKey) async throws -> CodexMessageReceipt {
        guard UUID(uuidString: id) != nil else { throw NetworkError.badResponse }
        let request = try conversationRequest(path: "api/codex/messages/\(id)", key: key, query: targetQuery(key))
        return try await readConversationJSON(request)
    }

    func releaseMessageWait(_ id: String, for key: CodexConversationKey) async throws -> CodexMessageReceipt {
        try await changeQueueWait(id, action: "release-wait", key: key)
    }

    func cancelPendingMessage(_ id: String, for key: CodexConversationKey) async throws -> CodexMessageReceipt {
        try await changeQueueWait(id, action: "cancel", key: key)
    }

    private func changeQueueWait(_ id: String, action: String, key: CodexConversationKey) async throws -> CodexMessageReceipt {
        guard UUID(uuidString: id) != nil else { throw NetworkError.badResponse }
        var request = try conversationRequest(path: "api/codex/messages/\(id)/\(action)", key: key, query: targetQuery(key))
        request.httpMethod = "POST"
        return try await readConversationJSON(request)
    }

    func conversationImage(at path: String, for key: CodexConversationKey) async throws -> Data {
        let request = URLRequest(url: try Self.conversationAssetURL(path, key: key), cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        let (data, response) = try await BridgeTransport.shared.data(for: request)
        try validateConversationResponse(response, data: data)
        guard data.count <= CodexAttachmentImporter.maximumImageBytes,
              let mime = (response as? HTTPURLResponse)?.mimeType,
              ["image/png", "image/jpeg"].contains(mime) else { throw NetworkError.badResponse }
        return data
    }

    // Asset paths are supplied by the paired bridge. Keep its /device/<token> prefix and
    // reject cross-origin or cross-chat references before issuing a credentialed request.
    static func conversationAssetURL(_ path: String, key: CodexConversationKey) throws -> URL {
        guard let relative = URLComponents(string: path), relative.scheme == nil,
              relative.host == nil, relative.fragment == nil,
              relative.path.hasPrefix("/api/codex/assets/"),
              relative.path.split(separator: "/").count == 4,
              let digest = relative.path.split(separator: "/").last,
              digest.count == 64, digest.allSatisfy({ $0.isHexDigit }),
              relative.queryItems?.filter({ $0.name == "hostId" }).map(\.value) == [key.hostId],
              relative.queryItems?.filter({ $0.name == "threadId" }).map(\.value) == [key.threadId],
              relative.queryItems?.count == 2,
              var result = URLComponents(url: key.serverURL, resolvingAgainstBaseURL: false) else {
            throw NetworkError.badResponse
        }
        result.path = result.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .withLeadingSlash + relative.path
        result.queryItems = relative.queryItems
        result.fragment = nil
        guard let url = result.url else { throw NetworkError.badResponse }
        return url
    }

    private func targetQuery(_ key: CodexConversationKey) -> [URLQueryItem] {
        [URLQueryItem(name: "hostId", value: key.hostId), URLQueryItem(name: "threadId", value: key.threadId)]
    }

    private func conversationRequest(path: String, key: CodexConversationKey, query: [URLQueryItem] = []) throws -> URLRequest {
        let endpoint = key.serverURL.appendingPathComponent(path)
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { throw NetworkError.badResponse }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw NetworkError.badResponse }
        return URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
    }

    private func readConversationJSON<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await BridgeTransport.shared.data(for: request)
        try validateConversationResponse(response, data: data)
        return try Self.conversationDecoder().decode(T.self, from: data)
    }

    static func conversationDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) { return date }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid chat timestamp.")
        }
        return decoder
    }

    private func validateConversationResponse(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw NetworkError.badResponse }
        guard (200..<300).contains(http.statusCode) else {
            let failure = try? JSONDecoder().decode(ConversationServerFailure.self, from: data)
            throw NetworkError.server(statusCode: http.statusCode, message: failure?.error ?? "The chat connection returned an error (\(http.statusCode)).")
        }
    }
}

private struct ConversationServerFailure: Decodable { let error: String }
private extension String { var withLeadingSlash: String { isEmpty ? "" : "/" + self } }
