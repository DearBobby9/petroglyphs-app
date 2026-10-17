import Foundation

protocol CodexDiagnosticsNetworking {
    func bridgeDiagnostics(for key: CodexConversationKey) async throws -> CodexBridgeDiagnostics
}

extension NetworkService: CodexDiagnosticsNetworking {
    func bridgeDiagnostics(for key: CodexConversationKey) async throws -> CodexBridgeDiagnostics {
        var components = URLComponents(url: key.serverURL.appendingPathComponent("api/codex/diagnostics"), resolvingAgainstBaseURL: false)
        var items = [URLQueryItem(name: "hostId", value: key.hostId), URLQueryItem(name: "threadId", value: key.threadId)]
        for (query, infoKey) in [("appVersion", "CFBundleShortVersionString"), ("appBuild", "CFBundleVersion"), ("appCommit", "PetroglyphsSourceCommit")] {
            guard let value = Bundle.main.object(forInfoDictionaryKey: infoKey) as? String else { continue }
            let pattern = query == "appCommit" ? "^[a-f0-9]{40}$" : "^[A-Za-z0-9.+_-]{1,64}$"
            if value.range(of: pattern, options: .regularExpression) != nil { items.append(URLQueryItem(name: query, value: value)) }
        }
        components?.queryItems = items
        guard let url = components?.url else { throw NetworkError.badResponse }
        let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        let (data, response) = try await BridgeTransport.shared.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw NetworkError.badResponse }
        guard (200..<300).contains(response.statusCode) else {
            throw NetworkError.server(statusCode: response.statusCode, message: "Diagnostics are unavailable from this bridge. Check the connection and bridge version.")
        }
        return try JSONDecoder().decode(CodexBridgeDiagnostics.self, from: data)
    }
}
