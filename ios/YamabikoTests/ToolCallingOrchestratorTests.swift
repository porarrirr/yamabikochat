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
    let definition = ToolDefinition(
        name: "test_tool",
        description: "Test tool",
        parametersJSON: #"{"type":"object"}"#
    )
    let counter: TestToolCounter
    var shouldThrow = false

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
    func testUnsupportedToolFallbackPolicyIsNarrowAndRemovesOnlyLocalFunctions() {
        let request = ProviderRequest(
            model: "test",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            tools: [
                ToolDefinition(
                    name: "web_search",
                    description: "Search",
                    parametersJSON: #"{"type":"object"}"#
                )
                .providerTool,
                ProviderTool(type: "google_search", payload: [:])
            ]
        )
        let error = ProviderClientError.httpStatus(
            400,
            "This model does not support function tools"
        )

        XCTAssertTrue(
            ClientToolFallbackPolicy.shouldRetryWithoutClientTools(
                error: error,
                request: request,
                round: 1
            )
        )
        XCTAssertFalse(
            ClientToolFallbackPolicy.shouldRetryWithoutClientTools(
                error: error,
                request: request,
                round: 2
            )
        )
        XCTAssertEqual(
            ClientToolFallbackPolicy.removingClientTools(from: request).tools,
            [ProviderTool(type: "google_search", payload: [:])]
        )
    }

    func testUnsupportedToolFallbackPolicyAlsoCoversCustomFunctionDeclarations() {
        let request = ProviderRequest(
            model: "test",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            tools: [
                ProviderTool(type: "function_declarations", payload: ["json": "[]"]),
                ProviderTool(type: "google_search", payload: [:])
            ]
        )
        let error = ProviderClientError.httpStatus(
            400,
            "Unknown name \"additionalProperties\": Cannot find field."
        )

        XCTAssertTrue(
            ClientToolFallbackPolicy.shouldRetryWithoutClientTools(
                error: error,
                request: request,
                round: 1
            )
        )
        XCTAssertEqual(
            ClientToolFallbackPolicy.removingClientTools(from: request).tools,
            [ProviderTool(type: "google_search", payload: [:])]
        )
    }

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
