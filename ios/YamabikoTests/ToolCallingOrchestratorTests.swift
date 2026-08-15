import XCTest
@testable import YamabikoChat

private enum TestToolError: LocalizedError {
    case failed

    var errorDescription: String? { "tool failed" }
}

private actor TestToolCounter {
    private(set) var count = 0

    func increment() {
        count += 1
    }
}

private struct TestToolExecutor: LocalToolExecutor {
    let definition: ToolDefinition
    let counter: TestToolCounter
    let shouldThrow: Bool

    init(counter: TestToolCounter, shouldThrow: Bool = false, name: String = "test_tool") {
        self.counter = counter
        self.shouldThrow = shouldThrow
        definition = ToolDefinition(
            name: name,
            description: "Test tool",
            parametersJSON: #"{"type":"object"}"#
        )
    }

    func execute(call: ToolCall) async throws -> ToolResult {
        await counter.increment()
        if shouldThrow {
            throw TestToolError.failed
        }
        return ToolResult(
            callId: call.id,
            name: call.name,
            content: #"{"ok":true}"#
        )
    }
}

private actor TestInvocationRecorder {
    private(set) var requests: [ProviderRequest] = []

    func append(_ request: ProviderRequest) -> Int {
        requests.append(request)
        return requests.count
    }
}

final class ToolCallingOrchestratorTests: XCTestCase {
    func testToolResultIsReturnedToModelBeforeFinalResponse() async throws {
        let counter = TestToolCounter()
        let recorder = TestInvocationRecorder()
        let orchestrator = ToolCallingOrchestrator(
            registry: LocalToolRegistry(executors: [TestToolExecutor(counter: counter)])
        )
        let request = ProviderRequest(
            model: "test",
            messages: [ProviderRequestMessage(role: "user", content: "search")]
        )

        let outcome = try await orchestrator.run(request: request) { request, _ in
            let invocation = await recorder.append(request)
            if invocation == 1 {
                return ProviderResponse(
                    text: "",
                    toolCalls: [
                        ToolCall(
                            id: "call-1",
                            name: "test_tool",
                            argumentsJSON: #"{"query":"swift"}"#,
                            providerMetadata: nil
                        )
                    ]
                )
            }
            return ProviderResponse(text: "final answer")
        }

        XCTAssertEqual(outcome.response.text, "final answer")
        XCTAssertEqual(outcome.rounds, 2)
        XCTAssertEqual(outcome.activities.map(\.status), [.completed])
        let requests = await recorder.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].messages.suffix(2).first?.role, "assistant")
        XCTAssertEqual(requests[1].messages.last?.role, "tool")
        XCTAssertEqual(requests[1].messages.last?.toolCallId, "call-1")
        XCTAssertEqual(outcome.replayMessages.count, 2)
        XCTAssertEqual(outcome.replayMessages[0].toolCalls?.first?.argumentsJSON, #"{"query":"swift"}"#)
        XCTAssertEqual(outcome.replayMessages[1].content, requests[1].messages.last?.content)
        XCTAssertEqual(outcome.replayMessages[1].toolCallId, "call-1")
    }

    func testToolFailureBecomesErrorResultAndTurnContinues() async throws {
        let counter = TestToolCounter()
        let recorder = TestInvocationRecorder()
        let orchestrator = ToolCallingOrchestrator(
            registry: LocalToolRegistry(
                executors: [TestToolExecutor(counter: counter, shouldThrow: true)]
            )
        )

        let outcome = try await orchestrator.run(
            request: ProviderRequest(
                model: "test",
                messages: [ProviderRequestMessage(role: "user", content: "search")]
            )
        ) { request, _ in
            let invocation = await recorder.append(request)
            if invocation == 1 {
                return ProviderResponse(
                    text: "",
                    toolCalls: [
                        ToolCall(
                            id: "call-1",
                            name: "test_tool",
                            argumentsJSON: "{}",
                            providerMetadata: nil
                        )
                    ]
                )
            }
            XCTAssertEqual(request.messages.last?.toolResultIsError, true)
            return ProviderResponse(text: "continued")
        }

        XCTAssertEqual(outcome.response.text, "continued")
        XCTAssertEqual(outcome.activities.first?.status, .failed)
        let executionCount = await counter.count
        XCTAssertEqual(executionCount, 1)
    }

    func testDuplicateToolCallIsSuppressed() async throws {
        let counter = TestToolCounter()
        let recorder = TestInvocationRecorder()
        let orchestrator = ToolCallingOrchestrator(
            registry: LocalToolRegistry(executors: [TestToolExecutor(counter: counter)])
        )
        let repeatedCall = ToolCall(
            id: "call-1",
            name: "test_tool",
            argumentsJSON: #"{"a":1}"#,
            providerMetadata: nil
        )

        let outcome = try await orchestrator.run(
            request: ProviderRequest(
                model: "test",
                messages: [ProviderRequestMessage(role: "user", content: "search")]
            )
        ) { request, _ in
            let invocation = await recorder.append(request)
            if invocation <= 2 {
                return ProviderResponse(text: "", toolCalls: [repeatedCall])
            }
            return ProviderResponse(text: "done")
        }

        XCTAssertEqual(outcome.response.text, "done")
        XCTAssertEqual(outcome.activities.map(\.status), [.completed, .failed])
        let executionCount = await counter.count
        XCTAssertEqual(executionCount, 1)
    }

    func testNormalizedEquivalentWebSearchQueriesAreSuppressed() async throws {
        let counter = TestToolCounter()
        let recorder = TestInvocationRecorder()
        let orchestrator = ToolCallingOrchestrator(
            registry: LocalToolRegistry(
                executors: [TestToolExecutor(counter: counter, name: WebSearchTool.name)]
            )
        )

        let outcome = try await orchestrator.run(
            request: ProviderRequest(
                model: "test",
                messages: [ProviderRequestMessage(role: "user", content: "search")]
            )
        ) { request, _ in
            let invocation = await recorder.append(request)
            switch invocation {
            case 1:
                return ProviderResponse(
                    text: "",
                    toolCalls: [
                        ToolCall(
                            id: "call-1",
                            name: WebSearchTool.name,
                            argumentsJSON: #"{"query":"ＳＷＩＦＴ、   Search","max_results":8}"#,
                            providerMetadata: nil
                        )
                    ]
                )
            case 2:
                return ProviderResponse(
                    text: "",
                    toolCalls: [
                        ToolCall(
                            id: "call-2",
                            name: WebSearchTool.name,
                            argumentsJSON: #"{"max_results":8,"query":"swift search"}"#,
                            providerMetadata: nil
                        )
                    ]
                )
            default:
                return ProviderResponse(text: "done")
            }
        }

        XCTAssertEqual(outcome.activities.map(\.status), [.completed, .failed])
        let executionCount = await counter.count
        XCTAssertEqual(executionCount, 1)
    }

    func testWebSearchWithLargerResultLimitIsNotSuppressed() async throws {
        let counter = TestToolCounter()
        let recorder = TestInvocationRecorder()
        let orchestrator = ToolCallingOrchestrator(
            registry: LocalToolRegistry(
                executors: [TestToolExecutor(counter: counter, name: WebSearchTool.name)]
            )
        )

        let outcome = try await orchestrator.run(
            request: ProviderRequest(
                model: "test",
                messages: [ProviderRequestMessage(role: "user", content: "search")]
            )
        ) { request, _ in
            let invocation = await recorder.append(request)
            if invocation <= 2 {
                let limit = invocation == 1 ? 3 : 8
                return ProviderResponse(
                    text: "",
                    toolCalls: [
                        ToolCall(
                            id: "call-\(invocation)",
                            name: WebSearchTool.name,
                            argumentsJSON: #"{"query":"swift search","max_results":\#(limit)}"#,
                            providerMetadata: nil
                        )
                    ]
                )
            }
            return ProviderResponse(text: "done")
        }

        XCTAssertEqual(outcome.activities.map(\.status), [.completed, .completed])
        let executionCount = await counter.count
        XCTAssertEqual(executionCount, 2)
    }

    func testDefaultMaxRoundsIsFifteen() {
        XCTAssertEqual(ToolCallingOrchestrator.defaultMaxRounds, 15)
    }

    func testMaximumRoundLimitStopsAdditionalInvocations() async throws {
        let counter = TestToolCounter()
        let recorder = TestInvocationRecorder()
        let orchestrator = ToolCallingOrchestrator(
            registry: LocalToolRegistry(executors: [TestToolExecutor(counter: counter)]),
            maxRounds: 15
        )

        let outcome = try await orchestrator.run(
            request: ProviderRequest(
                model: "test",
                messages: [ProviderRequestMessage(role: "user", content: "search")]
            )
        ) { request, round in
            _ = await recorder.append(request)
            return ProviderResponse(
                text: "",
                toolCalls: [
                    ToolCall(
                        id: "call-\(round)",
                        name: "test_tool",
                        argumentsJSON: #"{"round":\#(round)}"#,
                        providerMetadata: nil
                    )
                ]
            )
        }

        XCTAssertEqual(outcome.rounds, 15)
        let requestCount = await recorder.requests.count
        let executionCount = await counter.count
        XCTAssertEqual(requestCount, 15)
        XCTAssertEqual(executionCount, 15)
        XCTAssertTrue(outcome.response.toolCalls.isEmpty)
        XCTAssertFalse(outcome.response.text.isEmpty)
    }
}
