import Foundation

struct ToolCallingOutcome: Sendable, Equatable {
    var response: ProviderResponse
    var activities: [ToolActivityStep]
    var sources: [ToolSource]
    var rounds: Int
    var replayMessages: [ProviderRequestMessage]
}

struct ToolCallingProgress: Sendable, Equatable {
    var activities: [ToolActivityStep]
    /// Only complete assistant-tool/result rounds are exposed for durable replay.
    var replayMessages: [ProviderRequestMessage]
}

struct ToolCallingOrchestrator: Sendable {
    static let defaultMaxRounds = 15

    let registry: LocalToolRegistry
    var maxRounds: Int = Self.defaultMaxRounds

    func run(
        request initialRequest: ProviderRequest,
        invoke: @Sendable (ProviderRequest, Int) async throws -> ProviderResponse,
        onActivitiesChanged: (@Sendable ([ToolActivityStep]) async -> Void)? = nil,
        onProgressChanged: (@Sendable (ToolCallingProgress) async -> Void)? = nil
    ) async throws -> ToolCallingOutcome {
        var request = initialRequest
        var activities: [ToolActivityStep] = []
        var sources: [ToolSource] = []
        var seenCalls: Set<String> = []
        var combinedUsage: ProviderUsage?
        var replayMessages: [ProviderRequestMessage] = []
        let roundLimit = max(1, maxRounds)

        for round in 1 ... roundLimit {
            try Task.checkCancellation()
            var response = try await invoke(request, round)
            combinedUsage = Self.mergedUsage(combinedUsage, response.usage)
            response.usage = combinedUsage

            guard !response.toolCalls.isEmpty else {
                return ToolCallingOutcome(
                    response: response,
                    activities: activities,
                    sources: sources,
                    rounds: round,
                    replayMessages: replayMessages
                )
            }

            let assistantToolMessage = ProviderRequestMessage(
                    role: "assistant",
                    content: response.text,
                    reasoningContent: response.reasoningSummary,
                    toolCalls: response.toolCalls
                )
            request.messages.append(assistantToolMessage)
            var completedRoundMessages = [assistantToolMessage]

            for call in response.toolCalls {
                let duplicateKey = Self.duplicateKey(for: call)
                var step = ToolActivityStep.started(call: call, round: round)
                activities.append(step)
                await onActivitiesChanged?(activities)
                await onProgressChanged?(ToolCallingProgress(
                    activities: activities,
                    replayMessages: replayMessages
                ))

                let result: ToolResult
                if seenCalls.contains(duplicateKey) {
                    result = ToolResult(
                        callId: call.id,
                        name: call.name,
                        content: #"{"error":"Duplicate tool call suppressed"}"#,
                        isError: true
                    )
                } else {
                    seenCalls.insert(duplicateKey)
                    let toolStartedAtMs = Int64(Date().timeIntervalSince1970 * 1_000)
                    result = await registry.execute(call: call)
                    let toolCompletedAtMs = Int64(Date().timeIntervalSince1970 * 1_000)
                    if let metrics = ProviderMetricsContext.current {
                        metrics.recorder(
                            ConversationExecutionMetric(
                                conversationId: metrics.conversationId,
                                turnId: metrics.turnId,
                                kind: .tool,
                                startedAtMs: toolStartedAtMs,
                                firstTokenAtMs: nil,
                                completedAtMs: toolCompletedAtMs,
                                succeeded: !result.isError,
                                inputTokens: nil,
                                outputTokens: nil,
                                cachedInputTokens: nil,
                                cacheCreationInputTokens: nil
                            )
                        )
                    }
                }

                step.finish(with: result)
                activities[activities.count - 1] = step
                sources = Self.mergedSources(sources, result.sources)

                let toolMessage = ProviderRequestMessage(
                        role: "tool",
                        content: result.content,
                        toolCallId: result.callId,
                        toolName: result.name,
                        toolResultIsError: result.isError
                    )
                request.messages.append(toolMessage)
                completedRoundMessages.append(toolMessage)
                await onActivitiesChanged?(activities)
                await onProgressChanged?(ToolCallingProgress(
                    activities: activities,
                    replayMessages: replayMessages
                ))
            }

            replayMessages.append(contentsOf: completedRoundMessages)
            await onProgressChanged?(ToolCallingProgress(
                activities: activities,
                replayMessages: replayMessages
            ))

            if round == roundLimit {
                let message = L10n.text("Web検索ツールは最大ラウンド数に達したため停止しました。")
                DiagnosticsLogger.log(
                    "Local tool round limit reached",
                    level: .warning,
                    category: .chat,
                    metadata: ["rounds": String(roundLimit)]
                )
                response.text = response.text.trimmedNonEmpty ?? message
                response.toolCalls = []
                return ToolCallingOutcome(
                    response: response,
                    activities: activities,
                    sources: sources,
                    rounds: round,
                    replayMessages: replayMessages
                )
            }
        }

        throw ProviderClientError.parseFailure("Local tool orchestrator ended unexpectedly")
    }

    private static func duplicateKey(for call: ToolCall) -> String {
        if call.name == WebSearchTool.name,
           let data = call.argumentsJSON.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let query = object["query"] as? String {
            let limit = ToolArguments.int(object["max_results"]) ?? DuckDuckGoHTMLEngine.resultLimit
            return "\(call.name)\nquery=\(RelevantPageReader.normalizeSearchQuery(query))\nmax_results=\(limit)"
        }
        let arguments: String
        if let data = call.argumentsJSON.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           let normalized = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
           let json = String(data: normalized, encoding: .utf8) {
            arguments = json
        } else {
            arguments = call.argumentsJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "\(call.name)\n\(arguments)"
    }

    private static func mergedSources(_ current: [ToolSource], _ incoming: [ToolSource]) -> [ToolSource] {
        var result = current
        var seen = Set(current.map(\.url))
        for source in incoming where seen.insert(source.url).inserted {
            result.append(source)
        }
        return result
    }

    private static func mergedUsage(_ current: ProviderUsage?, _ incoming: ProviderUsage?) -> ProviderUsage? {
        guard current != nil || incoming != nil else { return nil }
        func sum(_ lhs: Int?, _ rhs: Int?) -> Int? {
            guard lhs != nil || rhs != nil else { return nil }
            return max(0, lhs ?? 0) + max(0, rhs ?? 0)
        }
        return ProviderUsage(
            inputTokens: sum(current?.inputTokens, incoming?.inputTokens),
            outputTokens: sum(current?.outputTokens, incoming?.outputTokens),
            totalTokens: sum(current?.totalTokens, incoming?.totalTokens),
            reasoningTokens: sum(current?.reasoningTokens, incoming?.reasoningTokens),
            cachedInputTokens: sum(current?.cachedInputTokens, incoming?.cachedInputTokens),
            cacheCreationInputTokens: sum(
                current?.cacheCreationInputTokens,
                incoming?.cacheCreationInputTokens
            )
        )
        .normalizedNonEmpty()
    }
}
