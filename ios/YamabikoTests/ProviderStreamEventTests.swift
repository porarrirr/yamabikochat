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

    func testToolActivityDoesNotCountAsAnswerText() {
        let call = ToolCall(id: "search-1", name: WebSearchTool.name, argumentsJSON: #"{"query":"SwiftUI"}"#)
        let event = ToolActivityEvent(phase: .started, call: call, result: nil, createdAtMs: 1)
        XCTAssertFalse(ProviderStreamEvent.toolActivity(event).includesNonEmptyAnswerText)
    }

    func testToolActivityPayloadUpdatesInPlaceAndBuildsTranscript() {
        let call = ToolCall(id: "search-1", name: WebSearchTool.name, argumentsJSON: #"{"query":"SwiftUI"}"#)
        var payload = ToolActivityPayload()
        payload.apply(ToolActivityEvent(phase: .started, call: call, result: nil, createdAtMs: 1))
        XCTAssertEqual(payload.steps.first?.status, .running)
        XCTAssertEqual(payload.steps.first?.detail, "SwiftUI")

        let result = ToolResult(
            callId: call.id,
            name: call.name,
            content: #"{"results":[{},{}]}"#,
            sources: [
                ToolSource(title: "A", url: "https://example.com"),
                ToolSource(title: "Duplicate", url: "https://example.com")
            ]
        )
        payload.apply(ToolActivityEvent(phase: .finished, call: call, result: result, createdAtMs: 1))

        XCTAssertEqual(payload.steps.count, 1)
        XCTAssertEqual(payload.steps.first?.status, .completed)
        XCTAssertEqual(payload.steps.first?.resultCount, 2)
        XCTAssertEqual(payload.steps.first?.sources.count, 1)
        XCTAssertEqual(payload.providerTranscript.map(\.role), ["assistant", "tool"])
    }

    func testToolActivityKeepsExecutionOrderAndFinalizesFailure() {
        let first = ToolCall(id: "search-1", name: WebSearchTool.name, argumentsJSON: #"{"query":"first"}"#)
        let second = ToolCall(id: "fetch-1", name: FetchUrlTool.name, argumentsJSON: #"{"url":"https://developer.apple.com"}"#)
        var payload = ToolActivityPayload()
        payload.apply(ToolActivityEvent(phase: .started, call: first, result: nil, createdAtMs: 1))
        payload.apply(ToolActivityEvent(phase: .started, call: second, result: nil, createdAtMs: 1))
        payload.apply(ToolActivityEvent(
            phase: .finished,
            call: first,
            result: ToolResult(callId: first.id, name: first.name, content: #"{"error":"offline"}"#, isError: true),
            createdAtMs: 2
        ))

        XCTAssertEqual(payload.steps.map(\.id), [first.id, second.id])
        XCTAssertEqual(payload.steps.map(\.round), [1, 2])
        XCTAssertEqual(payload.steps.first?.status, .failed)
        payload.failRunning(message: "cancelled")
        XCTAssertEqual(payload.steps.last?.status, .failed)
    }

    func testToolActivitySeparatesWebStepsAndCapturesPythonResultDetails() throws {
        let search = ToolCall(
            id: "search-1",
            name: WebSearchTool.name,
            argumentsJSON: #"{"query":"iOS Python"}"#
        )
        let python = ToolCall(
            id: "python-1",
            name: PythonExecuteTool.name,
            argumentsJSON: #"{"code":"print('done')\n6 * 7"}"#
        )
        var payload = ToolActivityPayload()
        payload.apply(ToolActivityEvent(phase: .started, call: search, result: nil, createdAtMs: 1))
        payload.apply(ToolActivityEvent(
            phase: .finished,
            call: python,
            result: ToolResult(
                callId: python.id,
                name: python.name,
                content: #"{"status":"ok","stdout":"done\n","stderr":"","result_repr":"42","artifacts":[],"duration_ms":125,"error":null}"#,
                artifacts: [ToolArtifact(path: "/tmp/chart.png", name: "chart.png", mime: "image/png", size: 12)]
            ),
            createdAtMs: 2
        ))

        XCTAssertEqual(payload.steps.filter(\.isWebActivity).map(\.id), [search.id])
        let execution = try XCTUnwrap(payload.steps.first { !$0.isWebActivity })
        XCTAssertEqual(execution.resultPreview, "42")
        XCTAssertEqual(execution.outputPreview, "done")
        XCTAssertEqual(execution.artifactNames, ["chart.png"])
        XCTAssertEqual(execution.durationMs, 125)

        let restored = try JSONDecoder().decode(
            ToolActivityPayload.self,
            from: JSONEncoder().encode(payload)
        )
        XCTAssertEqual(restored.steps, payload.steps)
    }

    func testLegacyToolActivityStepDecodesWithoutResultDetails() throws {
        let json = #"{"id":"legacy","round":1,"toolName":"web_search","title":"Web","detail":"query","status":"completed","resultCount":1,"sources":[],"errorMessage":null,"createdAtMs":1}"#
        let step = try JSONDecoder().decode(ToolActivityStep.self, from: Data(json.utf8))

        XCTAssertTrue(step.isWebActivity)
        XCTAssertNil(step.resultPreview)
        XCTAssertNil(step.outputPreview)
        XCTAssertNil(step.artifactNames)
        XCTAssertNil(step.durationMs)
    }
}
