import XCTest
import UIKit

@MainActor
final class CodexComposerInputTests: XCTestCase {
    func testLayoutProbesDoNotChangeScrollingTextOrSelection() throws {
        let view = textView()
        view.text = "A short draft"
        view.selectedRange = NSRange(location: 3, length: 5)
        let selection = view.selectedRange
        for width: CGFloat in [248, 138, 320, 248] {
            let size = try XCTUnwrap(CodexComposerInput.measuredSize(proposedWidth: width, view: view))
            XCTAssertTrue(view.isScrollEnabled, "A layout probe must not change the live editor's scrolling behavior.")
            XCTAssertEqual(view.text, "A short draft")
            XCTAssertEqual(view.selectedRange, selection)
            XCTAssertEqual(size.width, width)
            XCTAssertGreaterThanOrEqual(size.height, 44)
        }
    }

    func testLongDraftHasBoundedHeightAndKeepsItsFullContentsScrollable() throws {
        let view = textView()
        let text = String(repeating: "A complete image request remains editable. ", count: 80)
        view.text = text
        let first = try XCTUnwrap(CodexComposerInput.measuredSize(proposedWidth: 248, view: view))
        XCTAssertLessThanOrEqual(first.height, 140)
        XCTAssertGreaterThan(view.sizeThatFits(CGSize(width: 248, height: CGFloat.greatestFiniteMagnitude)).height, first.height)
        XCTAssertTrue(view.isScrollEnabled)
        XCTAssertEqual(view.text, text)
        XCTAssertEqual(CodexComposerInput.measuredSize(proposedWidth: 248, view: view), first)
        XCTAssertNil(CodexComposerInput.measuredSize(proposedWidth: 0, view: view))
        XCTAssertNil(CodexComposerInput.measuredSize(proposedWidth: .infinity, view: view))
        XCTAssertEqual(view.text, text)
        XCTAssertTrue(view.isScrollEnabled)
    }

    private func textView() -> ImagePastingTextView {
        let view = ImagePastingTextView()
        view.font = .preferredFont(forTextStyle: .body)
        view.textContainerInset = UIEdgeInsets(top: 10, left: 3, bottom: 10, right: 3)
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = true
        return view
    }
}
