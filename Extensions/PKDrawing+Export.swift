import PencilKit
import Foundation

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

    func exportPNG(scale: CGFloat = 1.0) -> Data? {
        let rect = bounds.isEmpty ? CGRect(x: 0, y: 0, width: 100, height: 100) : bounds
        let image = self.image(from: rect, scale: scale)
        return image.pngData()
    }
}
