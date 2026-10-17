import Foundation
import CoreGraphics

/// The camera is independent of ink, reference images, and export bounds.
struct CanvasViewport: Codable, Equatable {
    static let minimumZoom: CGFloat = 0.25
    static let maximumZoom: CGFloat = 4
    // PencilKit uses finite coordinates. Keep navigation within a range where
    // translating stroke geometry retains useful sub-point precision.
    static let coordinateLimit: CGFloat = 1_000_000

    var center: CGPoint
    var zoom: CGFloat

    var isValid: Bool {
        center.x.isFinite && center.y.isFinite && zoom.isFinite
            && abs(center.x) <= Self.coordinateLimit && abs(center.y) <= Self.coordinateLimit
            && (Self.minimumZoom...Self.maximumZoom).contains(zoom)
    }

    func constrained(to viewportSize: CGSize) -> CanvasViewport {
        let scale = min(max(zoom, Self.minimumZoom), Self.maximumZoom)
        let xLimit = max(0, Self.coordinateLimit - viewportSize.width / (2 * scale))
        let yLimit = max(0, Self.coordinateLimit - viewportSize.height / (2 * scale))
        return CanvasViewport(center: CGPoint(x: min(max(center.x, -xLimit), xLimit),
                                              y: min(max(center.y, -yLimit), yLimit)), zoom: scale)
    }

    func isAtCoordinateLimit(in viewportSize: CGSize) -> Bool {
        let xLimit = max(0, Self.coordinateLimit - viewportSize.width / (2 * zoom))
        let yLimit = max(0, Self.coordinateLimit - viewportSize.height / (2 * zoom))
        return abs(center.x) >= xLimit - 1 || abs(center.y) >= yLimit - 1
    }

    static func fitting(_ content: CGRect, in size: CGSize) -> CanvasViewport {
        let zoom = min((max(size.width - 96, 1)) / content.width,
                       (max(size.height - 96, 1)) / content.height)
        return CanvasViewport(center: CGPoint(x: content.midX, y: content.midY), zoom: min(1, zoom))
            .constrained(to: size)
    }
}

enum CanvasViewportCommand {
    case fitContent, actualSize, zoomIn, zoomOut
}

/// A bounded UIKit drawing window that moves through document coordinates.
/// Recentring this window never translates the saved document or its undo history.
struct CanvasScrollWindow {
    private(set) var origin: CGPoint
    private(set) var size: CGSize

    init(center: CGPoint, viewportSize: CGSize) {
        size = Self.requiredSize(for: viewportSize)
        origin = CGPoint(x: floor(center.x - size.width / 2), y: floor(center.y - size.height / 2))
    }

    func canContain(_ viewportSize: CGSize) -> Bool {
        let required = Self.requiredSize(for: viewportSize)
        return size.width >= required.width && size.height >= required.height
    }

    func documentPoint(at point: CGPoint, contentOffset: CGPoint, zoom: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + (point.x + contentOffset.x) / zoom,
                y: origin.y + (point.y + contentOffset.y) / zoom)
    }

    func surfaceRect(for rect: CGRect, contentOffset: CGPoint, zoom: CGFloat) -> CGRect {
        CGRect(x: (rect.minX - origin.x) * zoom - contentOffset.x,
               y: (rect.minY - origin.y) * zoom - contentOffset.y,
               width: rect.width * zoom, height: rect.height * zoom)
    }

    func contentOffset(for viewport: CanvasViewport, viewportSize: CGSize) -> CGPoint {
        CGPoint(x: (viewport.center.x - origin.x) * viewport.zoom - viewportSize.width / 2,
                y: (viewport.center.y - origin.y) * viewport.zoom - viewportSize.height / 2)
    }

    func needsRecentering(contentOffset: CGPoint, viewportSize: CGSize, zoom: CGFloat) -> Bool {
        let visible = CGRect(x: contentOffset.x / zoom, y: contentOffset.y / zoom,
                             width: viewportSize.width / zoom, height: viewportSize.height / zoom)
        return visible.minX < size.width * 0.15 || visible.maxX > size.width * 0.85
            || visible.minY < size.height * 0.15 || visible.maxY > size.height * 0.85
    }

    private static func requiredSize(for viewportSize: CGSize) -> CGSize {
        // Reserve capacity in powers of two so animated pane resizing does not
        // cause a drawing transform for every one-point size change.
        func capacity(_ dimension: CGFloat) -> CGFloat {
            let required = max(4_096, dimension / CanvasViewport.minimumZoom * 4)
            return pow(2, ceil(log2(required)))
        }
        return CGSize(width: capacity(viewportSize.width), height: capacity(viewportSize.height))
    }
}
