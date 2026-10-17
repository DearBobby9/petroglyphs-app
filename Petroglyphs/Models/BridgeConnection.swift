import Foundation
import CryptoKit

struct BridgeConnectionMetadata: Codable, Equatable, Sendable {
    let version: Int
    let id: String
    let lanOrigins: [URL]
    let tailscaleOrigins: [URL]
}

enum BridgeRoute: String, Sendable {
    case local = "Local"
    case tailscale = "Tailscale"
    case direct = "Direct"
}

struct BridgeConnectionSnapshot: Sendable {
    let generation = UUID()
    let health: HealthResponse
    let origin: URL
    let route: BridgeRoute
    let backupReady: Bool
    let automaticRecoveryReady: Bool
}

struct BridgeConnectionFailure: Equatable, Sendable {
    let pairedKey: String
    let origin: URL
    let generation: UUID
}

nonisolated struct PairedBridge: Sendable {
    let baseURL: URL
    let origin: URL
    let token: String

    init?(_ url: URL) {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              components.user == nil, components.password == nil,
              let origin = Self.origin(url) else { return nil }
        let parts = components.path.split(separator: "/")
        guard parts.count >= 2, parts[0] == "device", parts[1].count >= 32,
              parts[1].allSatisfy({ $0.isNumber || ("a"..."f").contains(String($0)) }) else { return nil }
        token = String(parts[1])
        components.path = "/device/\(token)"
        components.query = nil
        components.fragment = nil
        guard let baseURL = components.url else { return nil }
        self.baseURL = baseURL
        self.origin = origin
    }

    var storageKey: String { SHA256.hash(data: Data(baseURL.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined() }
    var identity: String { hmac("petroglyphs-bridge-id-v1") }

    func hmac(_ message: String) -> String {
        HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: Data(token.utf8)))
            .map { String(format: "%02x", $0) }.joined()
    }

    static func origin(_ url: URL) -> URL? {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false), let host = parts.host else { return nil }
        parts.scheme = parts.scheme?.lowercased()
        parts.host = host.lowercased()
        if (parts.scheme == "http" && parts.port == 80) || (parts.scheme == "https" && parts.port == 443) { parts.port = nil }
        parts.path = ""; parts.query = nil; parts.fragment = nil; parts.user = nil; parts.password = nil
        return parts.url
    }

    func accepts(_ candidate: URL, route: BridgeRoute) -> Bool {
        guard let parts = URLComponents(url: candidate, resolvingAgainstBaseURL: false),
              parts.user == nil, parts.password == nil, parts.query == nil, parts.fragment == nil,
              parts.path.isEmpty, Self.origin(candidate) == candidate,
              candidate.scheme == origin.scheme, candidate.port == origin.port,
              let host = candidate.host else { return false }
        if route == .local, host.hasSuffix(".local"), host.count <= 69 {
            let name = host.dropLast(6)
            return !name.isEmpty && name.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
        let partsOfIP = host.split(separator: ".", omittingEmptySubsequences: false)
        guard partsOfIP.count == 4, partsOfIP.allSatisfy({ Int($0).map { (0...255).contains($0) } == true }),
              partsOfIP.allSatisfy({ $0 == "0" || !$0.hasPrefix("0") }) else { return false }
        let ip = partsOfIP.compactMap { Int($0) }
        if route == .tailscale { return ip[0] == 100 && (64...127).contains(ip[1]) }
        return ip[0] == 10 || (ip[0] == 172 && (16...31).contains(ip[1])) || (ip[0] == 192 && ip[1] == 168)
    }

    func replacingOrigin(of url: URL, with origin: URL) throws -> URL {
        guard var result = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let endpoint = URLComponents(url: origin, resolvingAgainstBaseURL: false) else { throw URLError(.badURL) }
        result.scheme = endpoint.scheme; result.host = endpoint.host; result.port = endpoint.port
        guard let url = result.url else { throw URLError(.badURL) }
        return url
    }
}
