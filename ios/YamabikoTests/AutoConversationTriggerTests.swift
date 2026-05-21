import XCTest
@testable import YamabikoChat

final class AutoConversationTriggerTests: XCTestCase {
    func testRejectsEmptyAndTestPatterns() {
        XCTAssertFalse(AutoConversationTrigger.matches(""))
        XCTAssertFalse(AutoConversationTrigger.matches("a"))
        XCTAssertFalse(AutoConversationTrigger.matches("テスト"))
    }

    func testMatchesStrongTriggers() {
        XCTAssertTrue(AutoConversationTrigger.matches("こんにちは。AIについて話しましょう"))
        XCTAssertTrue(AutoConversationTrigger.matches("この件について質問があります"))
    }

    func testMatchesPunctuationAndLongerMessages() {
        XCTAssertTrue(AutoConversationTrigger.matches("どう思う？"))
        XCTAssertTrue(AutoConversationTrigger.matches("hello world"))
    }
}
