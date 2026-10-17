import Foundation

nonisolated struct BridgeDiscoveryClient: Sendable {
    typealias Send = @Sendable (URLRequest) async throws -> (Data, URLResponse)
    var send: Send = { try await BridgeHTTPSession.data(for: $0) }

    func discover(at origin: URL, selfOnly: Bool = false) async throws -> BridgeDiscoveryResponse {
        guard DiscoveredBridge.allowedOrigin(origin) else { throw URLError(.badURL) }
        var url = origin.appendingPathComponent("api/bridge/discovery")
        if selfOnly { url.append(queryItems: [URLQueryItem(name: "self", value: "1")]) }
        let result: BridgeDiscoveryResponse = try await request(URLRequest(url: url, timeoutInterval: selfOnly ? 4 : 14))
        guard result.version == 1, result.bridge.isValid, result.bridges.count <= 33 else { throw URLError(.cannotParseResponse) }
        return result
    }

    func begin(bridge: DiscoveredBridge, clientName: String, key: WirelessPairingKey) async throws -> WirelessPairingChallenge {
        guard bridge.isValid else { throw URLError(.badURL) }
        var request = URLRequest(url: bridge.origin.appendingPathComponent("api/bridge/pairings"), timeoutInterval: 12)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(Start(clientName: String(clientName.prefix(80)), clientPublicKey: key.publicKey, origin: bridge.origin.absoluteString))
        let challenge: WirelessPairingChallenge = try await self.request(request)
        guard UUID(uuidString: challenge.id) != nil, challenge.pollToken.count <= 128,
              challenge.pollToken.count >= 32,
              challenge.pollToken.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }),
              challenge.code.count == 6, challenge.code.allSatisfy(\.isNumber) else {
            throw URLError(.cannotParseResponse)
        }
        return challenge
    }

    func poll(bridge: DiscoveredBridge, challenge: WirelessPairingChallenge) async throws -> WirelessPairingPoll {
        try await request(pairingRequest(bridge, challenge: challenge, method: "GET"))
    }

    func cancel(bridge: DiscoveredBridge, challenge: WirelessPairingChallenge) async {
        let _: WirelessPairingPoll? = try? await request(pairingRequest(bridge, challenge: challenge, method: "DELETE"))
    }

    private func pairingRequest(_ bridge: DiscoveredBridge, challenge: WirelessPairingChallenge, method: String) -> URLRequest {
        var request = URLRequest(url: bridge.origin.appendingPathComponent("api/bridge/pairings/\(challenge.id)"), timeoutInterval: 8)
        request.httpMethod = method
        request.setValue(challenge.pollToken, forHTTPHeaderField: "X-Pairing-Token")
        return request
    }

    private func request<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await send(request)
        guard let response = response as? HTTPURLResponse, data.count <= 32768 else {
            throw URLError(.cannotConnectToHost)
        }
        guard (200...299).contains(response.statusCode) else {
            let reply = try? JSONDecoder().decode(Failure.self, from: data)
            throw BridgePairingFailure(status: response.statusCode, code: reply?.code ?? "connection_failed")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private struct Start: Encodable { let clientName: String; let clientPublicKey: String; let origin: String }
    private struct Failure: Decodable { let code: String }
}

nonisolated struct BridgePairingFailure: Error {
    let status: Int
    let code: String
    var message: String {
        switch code {
        case "approval_unavailable": "The Mac could not open its approval window. Unlock the Mac and try again."
        case "pairing_busy", "pairing_rate_limited": "Too many pairing requests. Cancel pending requests or wait a minute."
        case "invalid_pairing", "origin_not_allowed": "The Mac rejected the pairing request. Refresh discovery and select the Mac again."
        default: "The Mac could not complete pairing (HTTP \(status)). Try again when the bridge is available."
        }
    }
}
