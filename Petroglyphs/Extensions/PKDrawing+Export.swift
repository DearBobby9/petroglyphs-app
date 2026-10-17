import PencilKit
import Foundation
import UIKit

extension PKDrawing {
    func extractStrokeMetadata(duration: Double) -> StrokeMetadata {
        let bounds = self.bounds

        let strokeData: [StrokeMetadata.Stroke] = strokes.map { stroke in
            let creationTime = stroke.path.creationDate.timeIntervalSince1970
            let points: [StrokePoint] = stroke.path.map { point in
                StrokePoint(
                    x: Double(point.location.x),
                    y: Double(point.location.y),
                    pressure: Double(point.force),
                    timestamp: creationTime + point.timeOffset
                )
            }
            return StrokeMetadata.Stroke(points: points)
        }

        return StrokeMetadata(
            strokeCount: strokes.count,
            bounds: StrokeMetadata.Bounds(
                x: Double(bounds.origin.x),
                y: Double(bounds.origin.y),
                width: Double(bounds.size.width),
                height: Double(bounds.size.height)
            ),
            duration: duration,
            strokes: strokeData
        )
    }

    func exportPNG(
        scale: CGFloat = 1.0,
        backgroundColor: UIColor = .white,
        exportBounds: CGRect? = nil,
        referenceImage: UIImage? = nil,
        referenceBounds: CGRect? = nil
    ) -> Data? {
        let rect = exportBounds ?? (bounds.isEmpty ? CGRect(x: 0, y: 0, width: 100, height: 100) : bounds)
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.width.isFinite, rect.height.isFinite, rect.width > 0, rect.height > 0,
              scale.isFinite, scale > 0 else { return nil }
        var pngData: Data?
        UITraitCollection(userInterfaceStyle: .light).performAsCurrent {
            let image = self.image(from: rect, scale: scale)
            let format = UIGraphicsImageRendererFormat()
            format.scale = image.scale
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: image.size, format: format)
            // Keep ink interpretation fixed while matching the selected, opaque canvas background.
            pngData = renderer.pngData { context in
                backgroundColor.withAlphaComponent(1).setFill()
                context.fill(CGRect(origin: .zero, size: image.size))
                if let referenceImage, let referenceBounds {
                    referenceImage.draw(in: referenceBounds.offsetBy(dx: -rect.minX, dy: -rect.minY))
                }
                image.draw(at: .zero)
            }
        }
        return pngData
    }
}
