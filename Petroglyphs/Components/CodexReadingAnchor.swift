import Foundation
import CoreGraphics

struct CodexReadingViewport: Equatable {
    let contentFrame: CGRect
    let viewportHeight: CGFloat

    var isAtBottom: Bool { contentFrame.maxY <= viewportHeight + 60 }

    func followingLatest(after previous: Self?, wasFollowingLatest: Bool, isRestoring: Bool) -> Bool {
        guard !isRestoring, let previous, viewportHeight > 0 else { return wasFollowingLatest }
        // A resized viewport or newly appended content is not a reading gesture.
        guard viewportHeight == previous.viewportHeight,
              contentFrame.width == previous.contentFrame.width,
              abs(contentFrame.minY - previous.contentFrame.minY) > 0.5 else { return wasFollowingLatest }
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
