import Foundation

struct SubmissionPayload: Codable {
    let image: String
    let strokeMetadata: StrokeMetadata
    let combo: Combo?
    let pairingCode: String?

    enum CodingKeys: String, CodingKey {
        case image, strokeMetadata, combo
        case pairingCode = "pairing_code"
    }
}

struct SubmissionResponse: Codable {
    let id: String
    let status: String
}
