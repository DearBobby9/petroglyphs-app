import Foundation
import PencilKit

struct CanvasDocument: Codable {
    static let schemaVersion = 1
    static let emptyBounds = CGRect(x: 0, y: 0, width: 100, height: 100)

    let id: UUID
    var revision: Int
    var drawing: PKDrawing
    var background: CanvasBackground
    var exportBounds: CGRect

    init(background: CanvasBackground) {
        id = UUID()
        revision = 0
        drawing = PKDrawing()
        self.background = background
        exportBounds = Self.emptyBounds
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let version = try values.decode(Int.self, forKey: .version)
        guard version == Self.schemaVersion else { throw DocumentError.unsupportedVersion(version) }
        id = try values.decode(UUID.self, forKey: .id)
        revision = try values.decode(Int.self, forKey: .revision)
        drawing = try PKDrawing(data: values.decode(Data.self, forKey: .drawing))
        let backgroundHex = try values.decode(String.self, forKey: .background)
        guard let background = CanvasBackground(rawValue: backgroundHex) else { throw DocumentError.invalidBackground }
        self.background = background
        exportBounds = try values.decode(CGRect.self, forKey: .exportBounds)
        guard revision >= 0, Self.isValid(exportBounds) else { throw DocumentError.invalidBounds }
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(Self.schemaVersion, forKey: .version)
        try values.encode(id, forKey: .id)
        try values.encode(revision, forKey: .revision)
        try values.encode(drawing.dataRepresentation(), forKey: .drawing)
        try values.encode(background.rawValue, forKey: .background)
        try values.encode(exportBounds, forKey: .exportBounds)
    }

    static func isValid(_ bounds: CGRect) -> Bool {
        bounds.origin.x.isFinite && bounds.origin.y.isFinite
            && bounds.width.isFinite && bounds.height.isFinite
            && bounds.width > 0 && bounds.height > 0
    }

    private enum CodingKeys: String, CodingKey {
        case version, id, revision, drawing, background, exportBounds
    }

    enum DocumentError: LocalizedError {
        case unsupportedVersion(Int)
        case invalidBackground
        case invalidBounds

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version): "Canvas format version \(version) is not supported."
            case .invalidBackground: "The saved canvas background is invalid."
            case .invalidBounds: "The saved canvas export area is invalid."
            }
        }
    }
}
