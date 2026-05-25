import XCTest
@testable import YamabikoChat

final class StreamParserTests: XCTestCase {
    func testAnthropicThinkingDeltaDedupesCumulativePayload() {
        var fullText = ""
        var fullReasoning = ""
        let root: [String: Any] = [
            "type": "content_block_delta",
            "delta": [
                "type": "thinking_delta",
                "thinking": "full reasoning so far"
            ]
        ]

        let first = AnthropicMessagesStreamParser.event(from: root, fullText: &fullText, fullReasoning: &fullReasoning)
        guard case let .reasoningDelta(firstDelta)? = first else {
            return XCTFail("Expected reasoning delta")
        }
        XCTAssertEqual(firstDelta, "full reasoning so far")
        XCTAssertEqual(fullReasoning, "full reasoning so far")

        let second = AnthropicMessagesStreamParser.event(from: root, fullText: &fullText, fullReasoning: &fullReasoning)
        XCTAssertNil(second)
        XCTAssertEqual(fullReasoning, "full reasoning so far")
    }
}
