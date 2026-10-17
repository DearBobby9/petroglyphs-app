import Foundation
import UIKit

struct CanvasDocumentReference: Codable {
    let id: UUID
    let data: Data
    let name: String
    let sourceID: String
    let bounds: CGRect

    init(data: Data, name: String, sourceID: String) throws {
        let imported = try CodexAttachmentImporter.normalize(data, name: name)
        guard let image = UIImage(data: imported.data), image.size.width > 0, image.size.height > 0 else {
            throw CodexAttachmentImporter.ImportError.unsupported
        }
        id = UUID()
        self.data = imported.data
        self.name = imported.name
        self.sourceID = sourceID
        let scale = min(1, 1_024 / max(image.size.width, image.size.height))
        bounds = CGRect(x: 0, y: 0, width: image.size.width * scale, height: image.size.height * scale)
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        data = try values.decode(Data.self, forKey: .data)
        name = try values.decode(String.self, forKey: .name)
        sourceID = try values.decode(String.self, forKey: .sourceID)
        bounds = try values.decode(CGRect.self, forKey: .bounds)
        guard data.count <= CodexAttachmentImporter.maximumImageBytes,
              let image = UIImage(data: data), image.size.width > 0, image.size.height > 0,
              CanvasDocument.isValid(bounds) else {
            throw CodexAttachmentImporter.ImportError.unsupported
        }
    }

    private enum CodingKeys: String, CodingKey { case id, data, name, sourceID, bounds }
}
