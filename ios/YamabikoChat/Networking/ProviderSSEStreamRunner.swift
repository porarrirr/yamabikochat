import Foundation

/// Shared SSE line → `ProviderStreamEvent` pump for OpenAI-style chat completion streams.
enum ProviderSSEStreamRunner {
    struct Options {
        var usageFromRoot: ([String: Any]) -> ProviderUsage?
        var eventsFromRoot: ([String: Any], inout String, inout String) -> [ProviderStreamEvent]
        /// Reasoning summary when the stream ends via `[DONE]` or EOF (not inline `.completed`).
        var streamEndReasoningSummary: (String) -> String? = { _ in nil }
        var mergeInlineCompleted: (ProviderResponse, ProviderUsage?) -> ProviderResponse = { response, latestUsage in
            ProviderResponse(
                text: response.text,
                reasoningSummary: response.reasoningSummary,
                raw: response.raw,
                usage: response.usage ?? latestUsage,
                toolCalls: response.toolCalls
            )
        }
    }

    static func pump(
        lineStream: AsyncThrowingStream<String, Error>,
        continuation: AsyncThrowingStream<ProviderStreamEvent, Error>.Continuation,
        options: Options
    ) async throws {
        var fullText = ""
        var fullReasoning = ""
        var latestUsage: ProviderUsage?
        var toolCallAccumulator = ToolCallAccumulator()

        func yieldStreamCompleted(andFinish: Bool) {
            continuation.yield(
                .completed(
                    ProviderResponse(
                        text: fullText,
                        reasoningSummary: options.streamEndReasoningSummary(fullReasoning),
                        raw: nil,
                        usage: latestUsage,
                        toolCalls: toolCallAccumulator.toolCalls
                    )
                )
            )
            if andFinish {
                continuation.finish()
            }
        }

        for try await dataChunk in SSEPayloadAssembly.payloads(from: lineStream) {
            if dataChunk == "[DONE]" {
                yieldStreamCompleted(andFinish: true)
                return
            }
            guard let root = try? JSONSerialization.jsonObject(with: Data(dataChunk.utf8)) as? [String: Any] else {
                continue
            }
            if let usage = options.usageFromRoot(root) {
                latestUsage = usage
            }
            for event in options.eventsFromRoot(root, &fullText, &fullReasoning) {
                if case let .toolCallDelta(delta) = event {
                    toolCallAccumulator.append(delta)
                }
                if case let .completed(response) = event {
                    var final = options.mergeInlineCompleted(response, latestUsage)
                    if final.toolCalls.isEmpty {
                        final.toolCalls = toolCallAccumulator.toolCalls
                    }
                    continuation.yield(.completed(final))
                    continuation.finish()
                    return
                }
                continuation.yield(event)
            }
        }
        yieldStreamCompleted(andFinish: true)
    }
}
