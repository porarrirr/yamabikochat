import XCTest
@testable import YamabikoChat

final class ReasoningExtractionTests: XCTestCase {
    func testDisplayContentExtractsMultipleReasoningFormats() {
        let message = ChatMessage(
            id: 1,
            conversationId: 1,
            role: "model",
            text: "Answer body\n<thinking>step one</thinking>\n```analysis\nstep two\n```"
        )
        let full = FullChatMessage(id: 1, message: message, thinkingStream: nil, variants: [])

        XCTAssertEqual(full.displayText, "Answer body")
        XCTAssertEqual(full.displayThinkingStream, "step one\nstep two")
    }

    func testDisplayContentExtractsReasoningTag() {
        let message = ChatMessage(
            id: 2,
            conversationId: 1,
            role: "model",
            text: "Final\n<reasoning>hidden plan</reasoning>"
        )
        let full = FullChatMessage(id: 2, message: message, thinkingStream: nil, variants: [])

        XCTAssertEqual(full.displayText, "Final")
        XCTAssertEqual(full.displayThinkingStream, "hidden plan")
    }

    func testDisplayContentDeduplicatesPersistedAndInlineReasoning() {
        let message = ChatMessage(
            id: 3,
            conversationId: 1,
            role: "model",
            text: "<think>same thought</think>\nResult"
        )
        let full = FullChatMessage(id: 3, message: message, thinkingStream: "same thought", variants: [])

        XCTAssertEqual(full.displayText, "Result")
        XCTAssertEqual(full.displayThinkingStream, "same thought")
    }
}
