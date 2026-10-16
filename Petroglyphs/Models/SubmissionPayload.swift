import Foundation

struct SubmissionPayload: Codable {
    let image: String
    let strokeMetadata: StrokeMetadata
    let combo: Combo?
    let pairingCode: String?
    let threadId: String?
    let hostId: String?

    enum CodingKeys: String, CodingKey {
        case image, strokeMetadata, combo, threadId, hostId
        case pairingCode = "pairing_code"
    }
}

struct SubmissionResponse: Codable {
    let id: String
    let status: String
    let threadId: String?
    let hostId: String?
}
