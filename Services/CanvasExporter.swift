import PencilKit
import Foundation

struct CanvasExport {
    let imageBase64: String
    let strokeMetadata: StrokeMetadata
}

struct CanvasExporter {
    func export(drawing: PKDrawing, duration: Double) throws -> CanvasExport {
        guard let pngData = drawing.exportPNG(scale: 1.0) else {
            throw ExportError.pngFailed
        }
        let base64 = pngData.base64EncodedString()
        let metadata = drawing.extractStrokeMetadata(duration: duration)
        return CanvasExport(imageBase64: base64, strokeMetadata: metadata)
    }

    enum ExportError: Error {
        case pngFailed
    }
}
