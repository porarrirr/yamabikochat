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

    func testOpenAIStreamToolCallFragmentsAccumulateIntoStructuredCall() {
        var fullText = ""
        var fullReasoning = ""
        let first: [String: Any] = [
            "choices": [[
                "delta": [
                    "tool_calls": [[
                        "index": 0,
                        "id": "call_1",
                        "function": [
                            "name": "web_search",
                            "arguments": #"{"que"#
                        ]
                    ]]
                ]
            ]]
        ]
        let second: [String: Any] = [
            "choices": [[
                "delta": [
                    "tool_calls": [[
                        "index": 0,
                        "function": [
                            "arguments": #"ry":"swift"}"#
                        ]
                    ]]
                ]
            ]]
        ]

        var accumulator = ToolCallAccumulator()
        for root in [first, second] {
            for event in OpenAICompatibleStreamParser.events(
                fromRoot: root,
                fullText: &fullText,
                fullReasoning: &fullReasoning
            ) {
                if case let .toolCallDelta(delta) = event {
                    accumulator.append(delta)
                }
            }
        }

        XCTAssertEqual(
            accumulator.toolCalls,
            [
                ToolCall(
                    id: "call_1",
                    name: "web_search",
                    argumentsJSON: #"{"query":"swift"}"#,
                    providerMetadata: nil
                )
            ]
        )
    }

    func testAnthropicToolUseStartAndJSONDeltaAccumulate() {
        var fullText = ""
        var fullReasoning = ""
        let start: [String: Any] = [
            "type": "content_block_start",
            "index": 1,
            "content_block": [
                "type": "tool_use",
                "id": "toolu_1",
                "name": "fetch_url",
                "input": [:]
            ]
        ]
        let delta: [String: Any] = [
            "type": "content_block_delta",
            "index": 1,
            "delta": [
                "type": "input_json_delta",
                "partial_json": #"{"url":"https://example.com"}"#
            ]
        ]
        var accumulator = ToolCallAccumulator()

        for root in [start, delta] {
            if case let .toolCallDelta(value)? = AnthropicMessagesStreamParser.event(
                from: root,
                fullText: &fullText,
                fullReasoning: &fullReasoning
            ) {
                accumulator.append(value)
            }
        }

        XCTAssertEqual(accumulator.toolCalls.first?.id, "toolu_1")
        XCTAssertEqual(accumulator.toolCalls.first?.name, "fetch_url")
        XCTAssertEqual(
            accumulator.toolCalls.first?.argumentsJSON,
            #"{"url":"https://example.com"}"#
        )
    }

    func testAnthropicMCPToolUseDoesNotBecomeLocalToolCall() {
        var fullText = ""
        var fullReasoning = ""
        let root: [String: Any] = [
            "type": "content_block_start",
            "index": 0,
            "content_block": [
                "type": "mcp_tool_use",
                "id": "mcpu_1",
                "name": "firecrawl_search",
                "input": ["query": "swift"]
            ]
        ]

        let event = AnthropicMessagesStreamParser.event(
            from: root,
            fullText: &fullText,
            fullReasoning: &fullReasoning
        )

        XCTAssertNil(event)
    }
}
