import XCTest

final class CodexReadingPositionTests: XCTestCase {
    func testLongBlockCrossingViewportTopWinsOverNextMessage() throws {
        let anchor = try XCTUnwrap(CodexReadingAnchor.visible(in: [
            "long:block:2": CodexReadingBlock(messageID: "long", frame: CGRect(x: 0, y: -500, width: 300, height: 1_000)),
            "next": CodexReadingBlock(messageID: "next", frame: CGRect(x: 0, y: 520, width: 300, height: 200))
        ], viewportHeight: 600))
        XCTAssertEqual(anchor.blockID, "long:block:2")
        XCTAssertEqual(anchor.fraction, 0.5)
    }

    func testOffscreenBlocksCannotBecomeReadingAnchor() {
        let anchor = CodexReadingAnchor.visible(in: [
            "above": CodexReadingBlock(messageID: "a", frame: CGRect(x: 0, y: -250, width: 300, height: 200)),
            "visible": CodexReadingBlock(messageID: "b", frame: CGRect(x: 0, y: 20, width: 300, height: 100)),
            "below": CodexReadingBlock(messageID: "c", frame: CGRect(x: 0, y: 700, width: 300, height: 100))
        ], viewportHeight: 600)
        XCTAssertEqual(anchor?.messageID, "b")
        XCTAssertEqual(anchor?.fraction, 0)
    }

    func testNonTouchScrollLeavesLatestAndReturningToBottomResumesIt() {
        let bottom = CodexReadingViewport(contentFrame: CGRect(x: 0, y: -1_400, width: 400, height: 2_000), viewportHeight: 600)
        let history = CodexReadingViewport(contentFrame: CGRect(x: 0, y: -1_000, width: 400, height: 2_000), viewportHeight: 600)
        XCTAssertFalse(history.followingLatest(after: bottom, wasFollowingLatest: true, isRestoring: false))
        XCTAssertTrue(bottom.followingLatest(after: history, wasFollowingLatest: false, isRestoring: false))
    }

    func testAppendedReplyKeepsFollowingLatestUntilTheViewportScrolls() {
        let before = CodexReadingViewport(contentFrame: CGRect(x: 0, y: -1_400, width: 400, height: 2_000), viewportHeight: 600)
        let appended = CodexReadingViewport(contentFrame: CGRect(x: 0, y: -1_400, width: 400, height: 2_400), viewportHeight: 600)
        XCTAssertFalse(appended.isAtBottom)
        XCTAssertTrue(appended.followingLatest(after: before, wasFollowingLatest: true, isRestoring: false))
    }

    func testLazyContentMeasurementDoesNotHideNonTouchScroll() {
        let before = CodexReadingViewport(contentFrame: CGRect(x: 0, y: -1_400, width: 400, height: 2_000), viewportHeight: 600)
        let scrolled = CodexReadingViewport(contentFrame: CGRect(x: 0, y: -900, width: 400, height: 2_200), viewportHeight: 600)
        XCTAssertFalse(scrolled.followingLatest(after: before, wasFollowingLatest: true, isRestoring: false))
    }

    func testRestorationAndResizeKeepTheSavedReadingMode() {
        let history = CodexReadingViewport(contentFrame: CGRect(x: 0, y: -1_000, width: 400, height: 2_000), viewportHeight: 600)
        let bottom = CodexReadingViewport(contentFrame: CGRect(x: 0, y: -1_400, width: 400, height: 2_000), viewportHeight: 600)
        let resized = CodexReadingViewport(contentFrame: CGRect(x: 0, y: -1_000, width: 800, height: 1_200), viewportHeight: 800)
        XCTAssertFalse(bottom.followingLatest(after: history, wasFollowingLatest: false, isRestoring: true))
        XCTAssertFalse(bottom.followingLatest(after: bottom, wasFollowingLatest: false, isRestoring: false))
        XCTAssertFalse(resized.followingLatest(after: history, wasFollowingLatest: false, isRestoring: false))
    }

    func testRestorationWaitsForTheRequestedBlockEvenWhenItsRowIsMeasured() {
        let anchor = CodexReadingAnchor(messageID: "long", blockID: "long:block:2", fraction: 0.5)
        let row = CGRect(x: 0, y: 0, width: 400, height: 3_000)
        XCTAssertNil(anchor.restoration(in: [:], messageFrame: row, existingBlockIDs: [anchor.blockID]))
        let block = CGRect(x: 0, y: 1_000, width: 400, height: 500)
        let restored = anchor.restoration(in: [anchor.blockID: CodexReadingBlock(messageID: "long", frame: block)],
                                          messageFrame: row, existingBlockIDs: [anchor.blockID])
        XCTAssertEqual(restored?.frame, block)
        XCTAssertEqual(restored?.fraction, 0.5)
    }

    func testRemovedBlockFallsBackToMessageTopWhileLegacyRowKeepsItsFraction() {
        let row = CGRect(x: 0, y: 0, width: 400, height: 3_000)
        let removed = CodexReadingAnchor(messageID: "long", blockID: "long:block:removed", fraction: 0.5)
        XCTAssertEqual(removed.restoration(in: [:], messageFrame: row, existingBlockIDs: [])?.fraction, 0)
        let legacy = CodexReadingAnchor(messageID: "long", blockID: "long", fraction: 0.5)
        XCTAssertEqual(legacy.restoration(in: [:], messageFrame: row, existingBlockIDs: [])?.fraction, 0.5)
    }
}
