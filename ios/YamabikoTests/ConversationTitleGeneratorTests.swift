import XCTest
@testable import YamabikoChat

final class ConversationTitleGeneratorTests: XCTestCase {
    func testShortPromptIsKeptInFull() {
        let prompt = String(repeating: "あ", count: 300)
        XCTAssertEqual(ConversationTitlePrompt.limitedPrompt(prompt), prompt)
    }

    func testLongPromptUsesFirstTwoHundredAndLastOneHundredCharacters() {
        let prefix = String(repeating: "前", count: 200)
        let omitted = String(repeating: "中", count: 50)
        let suffix = String(repeating: "後", count: 100)

        let result = ConversationTitlePrompt.limitedPrompt(prefix + omitted + suffix)

        XCTAssertEqual(result, prefix + suffix)
        XCTAssertEqual(result.count, 300)
    }

    func testContentLimitsAssistantAnswerToTwoThousandCharacters() {
        let answer = String(repeating: "a", count: 2_100)

        let content = ConversationTitlePrompt.content(firstPrompt: "question", firstResponse: answer)

        XCTAssertTrue(content.contains(String(repeating: "a", count: 2_000)))
        XCTAssertFalse(content.contains(String(repeating: "a", count: 2_001)))
    }

    func testGeneratedTitleIsUnquotedSingleLineAndLimited() {
        let generated = "「" + String(repeating: "題", count: 60) + "」\nexplanation"

        let title = ConversationTitlePrompt.normalizedTitle(generated)

        XCTAssertEqual(title, String(repeating: "題", count: 50))
    }
}
