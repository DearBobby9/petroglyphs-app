import PencilKit
import Foundation

struct CanvasExport {
    let imageBase64: String
    let strokeMetadata: StrokeMetadata
}

struct CanvasExporter {
    func export(document: CanvasDocument, duration: Double) throws -> CanvasExport {
        guard let pngData = pngData(document: document) else { throw ExportError.pngFailed }
        return CanvasExport(imageBase64: pngData.base64EncodedString(), strokeMetadata: document.drawing.extractStrokeMetadata(duration: duration))
    }

    func pngData(document: CanvasDocument) -> Data? {
        // Limit raster allocation without changing the document coordinate system.
        let scale = min(1, 2_048 / max(document.exportBounds.width, document.exportBounds.height))
        return document.drawing.exportPNG(
            scale: scale,
            backgroundColor: document.background.uiColor,
            exportBounds: document.exportBounds,
            referenceImage: document.referenceImage.flatMap { UIImage(data: $0.data) },
            referenceBounds: document.referenceImage?.bounds
        )
    }

    func export(drawing: PKDrawing, duration: Double, backgroundColor: UIColor = .white) throws -> CanvasExport {
        guard let pngData = drawing.exportPNG(scale: 1.0, backgroundColor: backgroundColor) else {
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
