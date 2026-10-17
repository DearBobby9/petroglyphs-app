import XCTest

final class CodexMarkdownTests: XCTestCase {
    func testCommonMarkStructurePreservesHeadingsListsQuotesAndLinks() {
        let document = CodexMarkdownDocument("# Title\n\n1. First **bold** item\n2. Second [link](https://example.com)\n\n> Quoted text")
        XCTAssertEqual(document.blocks.first?.kind, .heading(1))
        XCTAssertEqual(document.blocks.filter { $0.marker != nil }.map(\.marker), ["1.", "2."])
        XCTAssertEqual(document.blocks.last?.quoteDepth, 1)
        XCTAssertTrue(document.blocks.flatMap { Array($0.text.runs) }.contains { $0.link?.absoluteString == "https://example.com" })
    }

    func testTableAndFencedCodeUseStructuredBlocks() {
        let source = "| Item | Value |\n| --- | --- |\n| A | `1` |\n\n```swift\nlet x = \"a|b\"\n```"
        let document = CodexMarkdownDocument(source)
        let table = document.blocks.first
        XCTAssertEqual(table?.kind, .table)
        XCTAssertEqual(table?.rows.count, 2)
        XCTAssertEqual(table?.rows[1].map { String($0.characters) }, ["A", "1"])
        XCTAssertEqual(document.blocks.last?.kind, .code("swift"))
        XCTAssertEqual(String(document.blocks.last!.text.characters), "let x = \"a|b\"\n")
        XCTAssertEqual(document.source, source, "Copying the raw reply must preserve all original syntax.")
    }

    func testAppendingStreamingContentKeepsEarlierBlockIdentities() {
        let first = CodexMarkdownDocument("## Result\n\nFirst paragraph.\n\nSecond paragraph.")
        let next = CodexMarkdownDocument(first.source + "\n\nThird paragraph.")
        XCTAssertEqual(first.blocks.map(\.id), Array(next.blocks.prefix(first.blocks.count)).map(\.id))
    }

    func testInlineFormattingDoesNotSplitAParagraphIntoReadingAnchors() {
        let document = CodexMarkdownDocument("A **bold** word and an *emphasis* with `code`.")
        XCTAssertEqual(document.blocks.count, 1)
        XCTAssertEqual(String(document.blocks[0].text.characters), "A bold word and an emphasis with code.")
    }
}
