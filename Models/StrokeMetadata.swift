import Foundation

struct StrokePoint: Codable {
    let x: Double
    let y: Double
    let pressure: Double
    let timestamp: Double
}

struct StrokeMetadata: Codable {
    let strokeCount: Int
    let bounds: Bounds
    let duration: Double
    let strokes: [Stroke]?

    struct Bounds: Codable {
        let x: Double
        let y: Double
        let width: Double
        let height: Double
    }

    struct Stroke: Codable {
        let points: [StrokePoint]
    }
}
