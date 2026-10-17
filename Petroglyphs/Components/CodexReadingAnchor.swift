import Foundation
import CoreGraphics

/// Scroll measurements and pending work do not render UI. Keep them in a
/// stable, non-observable owner so preference callbacks do not invalidate the
/// view that emitted the preference.
@MainActor
final class CodexReadingCoordinator {
    var restoredPosition = false
    var userIsScrolling = false
    var readingViewport: CodexReadingViewport?
    var rowPositions: [String: CGRect] = [:]
    var blockPositions: [String: CodexReadingBlock] = [:]
    var pendingRestore: CodexReadingAnchor?
    var savePositionTask: Task<Void, Never>?
    var viewportHeight: CGFloat = 0

    // A nil result is a repeated or transient measurement. Callers must not
    // schedule a save or update rendered state for it.
    func updateMetrics(_ viewport: CodexReadingViewport, wasFollowingLatest: Bool) -> Bool? {
        guard viewport.isUsable else { return nil }
        if let previous = readingViewport, viewport.hasSameMetrics(as: previous) { return nil }
        let followsLatest = viewport.followingLatest(after: readingViewport, wasFollowingLatest: wasFollowingLatest,
                                                     isRestoring: !restoredPosition || pendingRestore != nil)
        readingViewport = viewport
        return followsLatest
    }
}

struct CodexReadingViewport: Equatable {
    let contentFrame: CGRect
    let viewportHeight: CGFloat
    private static let measurementTolerance: CGFloat = 0.5

    // Layout can alternate between values such as 384 and 384.nextUp. Compare
    // against the accepted baseline so tiny steps can still accumulate into a scroll.
    func hasSameMetrics(as previous: Self) -> Bool {
        abs(contentFrame.minX - previous.contentFrame.minX) <= Self.measurementTolerance
            && abs(contentFrame.minY - previous.contentFrame.minY) <= Self.measurementTolerance
            && abs(contentFrame.width - previous.contentFrame.width) <= Self.measurementTolerance
            && abs(contentFrame.height - previous.contentFrame.height) <= Self.measurementTolerance
            && abs(viewportHeight - previous.viewportHeight) <= Self.measurementTolerance
    }

    var isUsable: Bool {
        contentFrame.origin.x.isFinite && contentFrame.origin.y.isFinite
            && contentFrame.width.isFinite && contentFrame.height.isFinite
            && contentFrame.width > 0 && contentFrame.height > 0
            && viewportHeight.isFinite && viewportHeight > 0
    }

    var isAtBottom: Bool { contentFrame.maxY <= viewportHeight + 60 }

    func followingLatest(after previous: Self?, wasFollowingLatest: Bool, isRestoring: Bool) -> Bool {
        guard !isRestoring, let previous, viewportHeight > 0 else { return wasFollowingLatest }
        // A resized viewport or newly appended content is not a reading gesture.
        guard abs(viewportHeight - previous.viewportHeight) <= Self.measurementTolerance,
              abs(contentFrame.width - previous.contentFrame.width) <= Self.measurementTolerance,
              abs(contentFrame.minY - previous.contentFrame.minY) > Self.measurementTolerance else { return wasFollowingLatest }
        return isAtBottom
    }
}

struct CodexReadingBlock: Equatable {
    let messageID: String
    let frame: CGRect
}

struct CodexReadingAnchor: Equatable {
    let messageID: String
    let blockID: String
    let fraction: Double

    func restoration(in blocks: [String: CodexReadingBlock], messageFrame: CGRect?, existingBlockIDs: Set<String>) -> CodexReadingRestoration? {
        if blockID == messageID {
            return messageFrame.map { CodexReadingRestoration(frame: $0, fraction: fraction) }
        }
        if existingBlockIDs.contains(blockID) {
            // The row can be measured before its Markdown blocks. Wait for the
            // requested block instead of applying its fraction to the whole row.
            return blocks[blockID].map { CodexReadingRestoration(frame: $0.frame, fraction: fraction) }
        }
        return messageFrame.map { CodexReadingRestoration(frame: $0, fraction: 0) }
    }

    static func visible(in blocks: [String: CodexReadingBlock], viewportHeight: CGFloat) -> Self? {
        guard let first = blocks.filter({ $0.value.frame.maxY > 0 && $0.value.frame.minY < viewportHeight })
            .min(by: { $0.value.frame.minY < $1.value.frame.minY }) else { return nil }
        return Self(messageID: first.value.messageID, blockID: first.key,
                    fraction: min(1, max(0, Double(-first.value.frame.minY / max(1, first.value.frame.height)))))
    }
}

struct CodexReadingRestoration: Equatable {
    let frame: CGRect
    let fraction: Double
}
