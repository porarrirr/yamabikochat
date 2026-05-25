import XCTest
@testable import YamabikoChat

final class ProviderStreamEventTests: XCTestCase {
    func testIncludesNonEmptyAnswerTextIgnoresWhitespaceTextDelta() {
        XCTAssertFalse(ProviderStreamEvent.textDelta("   \n").includesNonEmptyAnswerText)
    }

    func testIncludesNonEmptyAnswerTextAcceptsNonEmptyTextDelta() {
        XCTAssertTrue(ProviderStreamEvent.textDelta("hello").includesNonEmptyAnswerText)
    }

    func testIncludesNonEmptyAnswerTextIgnoresReasoningDelta() {
        XCTAssertFalse(ProviderStreamEvent.reasoningDelta("thinking").includesNonEmptyAnswerText)
    }

    func testIncludesNonEmptyAnswerTextUsesCompletedResponseText() {
        let empty = ProviderStreamEvent.completed(ProviderResponse(text: "  ", reasoningSummary: nil, raw: nil, usage: nil))
        XCTAssertFalse(empty.includesNonEmptyAnswerText)

        let filled = ProviderStreamEvent.completed(ProviderResponse(text: "answer", reasoningSummary: nil, raw: nil, usage: nil))
        XCTAssertTrue(filled.includesNonEmptyAnswerText)
    }
}
