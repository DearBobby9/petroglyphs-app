import Foundation
import CryptoKit

nonisolated struct DiscoveredBridge: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let origin: URL

    var route: BridgeRoute { origin.host.map(PairedBridge.isTailscaleHost) == true ? .tailscale : .local }
    var isValid: Bool {
        id.count == 64 && id.allSatisfy { $0.isHexDigit && !$0.isUppercase } &&
        !name.isEmpty && name.count <= 100 && Self.allowedOrigin(origin)
    }

    static func allowedOrigin(_ url: URL) -> Bool {
        guard url.scheme == "http", url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil, url.path.isEmpty,
              let port = url.port, (1...65535).contains(port) else { return false }
        // Reuse the paired route policy without ever placing a real token on a probe.
        guard let bridge = PairedBridge(URL(string: "http://127.0.0.1:\(port)/device/" + String(repeating: "0", count: 64))!) else { return false }
        return bridge.accepts(url, route: .local) || bridge.accepts(url, route: .tailscale)
    }
}

nonisolated struct BridgeDiscoveryResponse: Decodable, Sendable {
    let version: Int
    let bridge: DiscoveredBridge
    let bridges: [DiscoveredBridge]
    let tailscale: Tailnet
    struct Tailnet: Decodable, Sendable { let state: String; let availablePeers: Int }
}

nonisolated struct WirelessPairingChallenge: Decodable, Sendable {
    let id: String
    let pollToken: String
    let code: String
    let expiresAt: String
    let serverPublicKey: String
    let salt: String
}

nonisolated struct WirelessPairingPoll: Decodable, Sendable {
    let state: String
    let encrypted: Envelope?
    struct Envelope: Decodable, Sendable { let nonce: String; let ciphertext: String; let tag: String }
}

nonisolated struct WirelessPairingCredentials: Codable, Sendable {
    let baseURL: URL
    let bridgeId: String
    let name: String
}

nonisolated struct WirelessPairingKey: Sendable {
    let privateKey: P256.KeyAgreement.PrivateKey
    init(privateKey: P256.KeyAgreement.PrivateKey = P256.KeyAgreement.PrivateKey()) { self.privateKey = privateKey }
    var publicKey: String { privateKey.publicKey.x963Representation.base64EncodedString() }

    func verifiedKey(_ challenge: WirelessPairingChallenge) throws -> SymmetricKey {
        guard UUID(uuidString: challenge.id) != nil,
              let publicData = Data(base64Encoded: challenge.serverPublicKey), publicData.count == 65,
              let salt = Data(base64Encoded: challenge.salt), salt.count == 32 else { throw URLError(.cannotParseResponse) }
        let serverKey = try P256.KeyAgreement.PublicKey(x963Representation: publicData)
        let secret = try privateKey.sharedSecretFromKeyAgreement(with: serverKey)
        let key = secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt,
            sharedInfo: Data("petroglyphs-wireless-pairing-v1".utf8), outputByteCount: 32)
        let digest = Array(HMAC<SHA256>.authenticationCode(for: Data("petroglyphs-pairing-code-v1\n\(challenge.id)".utf8), using: key))
        let number = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } % 1_000_000
        guard String(format: "%06u", number) == challenge.code else { throw URLError(.userAuthenticationRequired) }
        return key
    }

    func decrypt(_ envelope: WirelessPairingPoll.Envelope, challenge: WirelessPairingChallenge,
                 bridge: DiscoveredBridge) throws -> WirelessPairingCredentials {
        let key = try verifiedKey(challenge)
        guard let nonce = Data(base64Encoded: envelope.nonce), nonce.count == 12,
              let ciphertext = Data(base64Encoded: envelope.ciphertext), ciphertext.count <= 4096,
              let tag = Data(base64Encoded: envelope.tag), tag.count == 16 else { throw URLError(.cannotParseResponse) }
        let box = try AES.GCM.SealedBox(nonce: AES.GCM.Nonce(data: nonce), ciphertext: ciphertext, tag: tag)
        let plain = try AES.GCM.open(box, using: key, authenticating: Data(challenge.id.utf8))
        let credentials = try JSONDecoder().decode(WirelessPairingCredentials.self, from: plain)
        guard let paired = PairedBridge(credentials.baseURL), paired.identity == bridge.id,
              credentials.bridgeId == bridge.id, paired.origin == bridge.origin,
              paired.baseURL == credentials.baseURL else { throw URLError(.userAuthenticationRequired) }
        return credentials
    }
}

nonisolated struct SavedBridge: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let durableURL: URL
}

/// Retains each approved Mac's original URL, which also keys its chats and drafts.
@MainActor
struct SavedBridgeRegistry {
    private(set) var bridges: [SavedBridge]
    private let defaults: UserDefaults
    private static let key = "savedBridgePairings.v1"

    init(defaults: UserDefaults) {
        self.defaults = defaults
        bridges = (defaults.data(forKey: Self.key)
            .flatMap { try? JSONDecoder().decode([SavedBridge].self, from: $0) } ?? [])
            .filter { PairedBridge($0.durableURL)?.identity == $0.id }
        for key in ["localURLString", "serverURLString"] {
            guard let raw = defaults.string(forKey: key), let url = URL(string: raw), let paired = PairedBridge(url),
                  self[paired.identity] == nil else { continue }
            remember(url: paired.baseURL, name: defaults.string(forKey: "pairedBridgeName") ?? "Paired Mac")
        }
    }

    subscript(identity: String) -> SavedBridge? { bridges.first { $0.id == identity } }

    mutating func remember(url: URL, name: String) {
        guard let paired = PairedBridge(url) else { return }
        let saved = SavedBridge(id: paired.identity, name: String(name.prefix(100)),
                                durableURL: self[paired.identity]?.durableURL ?? paired.baseURL)
        bridges.removeAll { $0.id == saved.id }
        bridges.append(saved)
        if let data = try? JSONEncoder().encode(bridges) { defaults.set(data, forKey: Self.key) }
    }
}
