import XCTest

final class CodexResultImageModelsTests: XCTestCase {
    func testBridgeOmittedAttachmentCountSurvivesCacheRoundTrip() throws {
        let data = Data(#"{"id":"result","role":"assistant","text":"Preview","phase":"final","state":"completed","attachments":[],"omittedAttachmentCount":3}"#.utf8)
        let message = try JSONDecoder().decode(CodexConversationMessage.self, from: data)
        XCTAssertEqual(message.omittedResultImageCount, 3)
        let cached = try JSONEncoder().encode(message)
        XCTAssertEqual(try JSONDecoder().decode(CodexConversationMessage.self, from: cached).omittedResultImageCount, 3)
    }

    func testEarlierCachedResultCountAndUnavailableReasonRemainReadable() throws {
        let data = Data(#"{"id":"result","role":"assistant","text":"Preview","phase":"final","state":"completed","attachments":[{"id":"image","name":"Result.png","mimeType":"image/png","availability":"unavailable","unavailableReason":"remote_file_unsupported"}],"omittedResultImageCount":2}"#.utf8)
        let message = try JSONDecoder().decode(CodexConversationMessage.self, from: data)
        XCTAssertEqual(message.omittedResultImageCount, 2)
        XCTAssertEqual(message.attachments.first?.unavailableReason, "remote_file_unsupported")
    }
}
