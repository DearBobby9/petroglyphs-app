import XCTest
import SwiftUI

final class CanvasChatLayoutTests: XCTestCase {
    func testStackedLayoutRequiresRoomForMeasuredComposerAndReadableHistory() {
        XCTAssertFalse(CanvasChatFrames.supportsStacked(in: 476, chatMinimumHeight: 420))
        XCTAssertTrue(CanvasChatFrames.supportsStacked(in: 800, chatMinimumHeight: 420))
        XCTAssertFalse(CanvasChatFrames.supportsStacked(in: 800, chatMinimumHeight: 700))
        XCTAssertEqual(CanvasChatFrames.stackedHeight(in: 800, chatMinimumHeight: 510), 510)
        XCTAssertLessThanOrEqual(CanvasChatFrames.stackedHeight(in: 800, chatMinimumHeight: 700), 628)
    }
    func testSidebarUsesANarrowVisualGapAndCollapsesWithoutAnEmptyRail() {
        for side in CanvasChatSide.allCases {
            let open = CanvasChatFrames(size: CGSize(width: 1_334, height: 900), mode: .sideBySide,
                                        side: side, chatExtent: CanvasChatFrames.chatExtent(fraction: 0.36, availableWidth: 1_334))
            let gap = side == .left ? open.canvas.minX - open.chat.maxX : open.chat.minX - open.canvas.maxX
            XCTAssertEqual(gap, 8, accuracy: 0.001)
            let closed = CanvasChatFrames(size: CGSize(width: 1_334, height: 900), mode: .sideBySide,
                                          side: side, chatExtent: 0)
            XCTAssertEqual(closed.canvas.width, 1_334, accuracy: 0.001)
            XCTAssertEqual(closed.chat.width, 0)
            XCTAssertEqual(closed.divider.width, 0)
        }
    }

    func testResizingAndSwappingAlwaysPartitionTheWorkspaceWithinMinimumWidths() {
        for width in [CGFloat(1_008), 1_334, 1_968] {
            for fraction in [-2.0, 0.01, 0.36, 0.75, 2.0, .nan] {
                for side in CanvasChatSide.allCases {
                    let frames = CanvasChatFrames(size: CGSize(width: width, height: 900), mode: .sideBySide,
                                                  side: side, chatExtent: CanvasChatFrames.chatExtent(fraction: fraction, availableWidth: width))
                    XCTAssertGreaterThanOrEqual(frames.canvas.width, CanvasChatFrames.minimumCanvasWidth - 0.001)
                    XCTAssertGreaterThanOrEqual(frames.chat.width, CanvasChatFrames.minimumChatWidth - 0.001)
                    XCTAssertEqual(frames.canvas.width + CanvasChatFrames.dividerWidth + frames.chat.width, width, accuracy: 0.001)
                    XCTAssertEqual(frames.divider.width, 44)
                    XCTAssertFalse(frames.canvas.intersects(frames.chat))
                    let ordered = [frames.canvas, frames.chat].sorted { $0.minX < $1.minX }
                    XCTAssertEqual(ordered[0].minX, 0, accuracy: 0.001)
                    XCTAssertEqual(ordered[1].minX - ordered[0].maxX, CanvasChatFrames.dividerWidth, accuracy: 0.001)
                    XCTAssertEqual(frames.divider.midX, (ordered[0].maxX + ordered[1].minX) / 2, accuracy: 0.001)
                    XCTAssertEqual(ordered[1].maxX, width, accuracy: 0.001)
                }
            }
        }
    }

    func testDraggingTracksBothEdgesContinuouslyAndLeavesNoCollapsedCanvas() {
        let width: CGFloat = 1_334
        for side in CanvasChatSide.allCases {
            for extent in [CGFloat(0), 2, 80, 320, 630, 1_250, 1_332, width] {
                let frames = CanvasChatFrames(size: CGSize(width: width, height: 900), mode: .sideBySide,
                                              side: side, chatExtent: extent)
                XCTAssertTrue(frames.canvas.isEmpty || frames.chat.isEmpty || !frames.canvas.intersects(frames.chat))
                XCTAssertGreaterThanOrEqual(frames.canvas.width, 0)
                XCTAssertGreaterThanOrEqual(frames.chat.width, 0)
                if extent > 0 && extent < width {
                    let presented = CanvasChatFrames.chatExtent(dividerCenter: frames.divider.midX, side: side, availableWidth: width)
                    XCTAssertEqual(presented, extent, accuracy: 0.001)
                }
                if extent == width {
                    XCTAssertEqual(frames.canvas.width, 0)
                    XCTAssertEqual(frames.chat.width, width)
                    XCTAssertEqual(frames.divider, .zero)
                }
            }
        }
    }

    func testEdgeReleaseThresholdAndVelocityProjectionAreBoundedAndReversible() {
        let width: CGFloat = 1_334
        let cases: [(CGFloat, CGFloat, CanvasChatResizeDestination?)] = [
            (95, 0, .hideChat), (97, 0, nil),
            (width - 95, 0, .hideCanvas), (width - 97, 0, nil),
            (148, -1_000, .hideChat), (width - 148, 1_000, .hideCanvas),
            (185, -10_000, nil), (width - 185, 10_000, nil),
            (95, 600, nil), (width - 95, -600, nil),
            (450, -100_000, nil), (450, 100_000, nil)
        ]
        for (extent, velocity, expected) in cases {
            for side in CanvasChatSide.allCases {
                let translation = side == .left ? extent - 480 : 480 - extent
                let screenVelocity = side == .left ? velocity : -velocity
                let dragExtent = 480 + CanvasChatFrames.extentChange(translation: translation, side: side)
                let decision = CanvasChatResizeDecision(extent: dragExtent,
                                                       velocity: CanvasChatFrames.extentChange(translation: screenVelocity, side: side),
                                                       availableWidth: width)
                if let expected { XCTAssertEqual(decision.destination, expected) }
                else {
                    guard case .split = decision.destination else { XCTFail("Unexpected collapse at \(extent), \(velocity)"); continue }
                    XCTAssertGreaterThanOrEqual(decision.extent - CanvasChatFrames.dividerWidth / 2, CanvasChatFrames.minimumChatWidth - 0.001)
                    XCTAssertGreaterThanOrEqual(width - decision.extent - CanvasChatFrames.dividerWidth / 2, CanvasChatFrames.minimumCanvasWidth - 0.001)
                }
            }
        }
    }

    func testStackedLayoutKeepsBothPanelsInsideShortAndTallWindows() {
        for height in [CGFloat(300), 476, 976, 1_342] {
            for expanded in [false, true] {
                let preferred = CanvasChatFrames.preferredStackedHeight(in: height)
                let extent = expanded ? preferred + CanvasChatFrames.stackedSpacing / 2 : 0
                let frames = CanvasChatFrames(size: CGSize(width: 700, height: height), mode: .stacked,
                                              side: .left, chatExtent: extent)
                XCTAssertGreaterThanOrEqual(frames.canvas.height, 160)
                XCTAssertGreaterThanOrEqual(frames.chat.height, 0)
                XCTAssertEqual(frames.canvas.minY, 0)
                XCTAssertEqual(frames.chat.maxY, height, accuracy: 0.001)
                XCTAssertEqual(frames.chat.minY - frames.canvas.maxY, expanded ? CanvasChatFrames.stackedSpacing : 0, accuracy: 0.001)
                XCTAssertEqual(frames.chat.width, frames.canvas.width)
                XCTAssertFalse(frames.canvas.intersects(frames.chat))
                if !expanded { XCTAssertEqual(frames.canvas.height, height, accuracy: 0.001) }
            }
        }
    }

    func testStackedMotionHonorsIntermediateExtentsAndReachesBothClosedEdges() {
        let height: CGFloat = 976
        for extent in [CGFloat(0), 2, 100, 260, 520, 974, height] {
            let frames = CanvasChatFrames(size: CGSize(width: 700, height: height), mode: .stacked,
                                          side: .right, chatExtent: extent)
            let gap = min(CanvasChatFrames.stackedSpacing, 2 * min(extent, height - extent))
            XCTAssertEqual(frames.chat.height, extent - gap / 2, accuracy: 0.001)
            XCTAssertEqual(frames.canvas.height, height - extent - gap / 2, accuracy: 0.001)
            XCTAssertEqual(frames.chat.maxY, height, accuracy: 0.001)
            XCTAssertEqual(frames.chat.minY - frames.canvas.maxY, gap, accuracy: 0.001)
        }
    }
}
