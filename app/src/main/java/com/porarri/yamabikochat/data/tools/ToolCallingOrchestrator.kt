package com.porarri.yamabikochat.data.tools

import com.porarri.yamabikochat.data.remote.TokenUsageSnapshot
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import kotlinx.coroutines.ensureActive
import org.json.JSONObject
import kotlin.coroutines.coroutineContext

class ToolCallingOrchestrator(
    private val registry: LocalToolRegistry,
    private val maxRounds: Int = DEFAULT_MAX_ROUNDS
) {
    suspend fun run(
        request: ToolTurnRequest,
        invoke: suspend (ToolTurnRequest, Int) -> ToolTurnResponse,
        onActivitiesChanged: (suspend (List<ToolActivityStep>) -> Unit)? = null,
        onProgressChanged: (suspend (ToolCallingProgress) -> Unit)? = null
    ): ToolCallingOutcome {
        val working = ToolTurnRequest(messages = request.messages.toMutableList())
        val activities = mutableListOf<ToolActivityStep>()
        var sources = emptyList<ToolSource>()
        val seenCalls = mutableSetOf<String>()
        var combinedUsage: TokenUsageSnapshot? = null
        val replayMessages = mutableListOf<ToolTurnMessage>()
        val roundLimit = maxOf(1, maxRounds)

        for (round in 1..roundLimit) {
            coroutineContext.ensureActive()
            var response = invoke(working, round)
            combinedUsage = mergedUsage(combinedUsage, response.usage)
            response = response.copy(usage = combinedUsage)

            if (response.toolCalls.isEmpty()) {
                return ToolCallingOutcome(
                    response = response,
                    activities = activities.toList(),
                    sources = sources,
                    rounds = round,
                    replayMessages = replayMessages.toList()
                )
            }

            val assistantToolMessage = ToolTurnMessage(
                    role = "assistant",
                    content = response.text,
                    reasoningContent = response.reasoningSummary,
                    toolCalls = response.toolCalls
                )
            working.messages.add(assistantToolMessage)
            val completedRoundMessages = mutableListOf(assistantToolMessage)

            for (call in response.toolCalls) {
                val duplicateKey = duplicateKey(call)
                var step = ToolActivityStep.started(call = call, round = round)
                activities.add(step)
                onActivitiesChanged?.invoke(activities.toList())
                onProgressChanged?.invoke(
                    ToolCallingProgress(activities.toList(), replayMessages.toList())
                )

                val result = if (seenCalls.contains(duplicateKey)) {
                    ToolResult(
                        callId = call.id,
                        name = call.name,
                        content = """{"error":"Duplicate tool call suppressed"}""",
                        isError = true
                    )
                } else {
                    seenCalls.add(duplicateKey)
                    registry.execute(call)
                }

                step.finish(with = result)
                activities[activities.lastIndex] = step
                sources = mergedSources(sources, result.sources)
                onActivitiesChanged?.invoke(activities.toList())

                val toolMessage = ToolTurnMessage(
                        role = "tool",
                        content = result.content,
                        toolCallId = result.callId,
                        toolName = result.name,
                        toolResultIsError = result.isError
                    )
                working.messages.add(toolMessage)
                completedRoundMessages.add(toolMessage)
                onProgressChanged?.invoke(
                    ToolCallingProgress(activities.toList(), replayMessages.toList())
                )
            }

            replayMessages.addAll(completedRoundMessages)
            onProgressChanged?.invoke(
                ToolCallingProgress(activities.toList(), replayMessages.toList())
            )

            if (round == roundLimit) {
                val message = "Web検索ツールは最大ラウンド数に達したため停止しました。"
                DiagnosticsLogger.log(
                    "Local tool round limit reached rounds=$roundLimit"
                )
                val finalText = response.text.trim().takeIf { it.isNotEmpty() } ?: message
                return ToolCallingOutcome(
                    response = response.copy(text = finalText, toolCalls = emptyList()),
                    activities = activities.toList(),
                    sources = sources,
                    rounds = round,
                    replayMessages = replayMessages.toList()
                )
            }
        }

        throw WebToolException.ParseFailure("Local tool orchestrator ended unexpectedly")
    }

    companion object {
        const val DEFAULT_MAX_ROUNDS = 15

        private fun duplicateKey(call: ToolCall): String {
            val arguments = runCatching {
                val obj = JSONObject(call.argumentsJSON)
                val keys = obj.keys().asSequence().sorted().toList()
                val normalized = JSONObject()
                for (key in keys) {
                    normalized.put(key, obj.get(key))
                }
                normalized.toString()
            }.getOrDefault(call.argumentsJSON.trim())
            return "${call.name}\n$arguments"
        }

        private fun mergedSources(
            current: List<ToolSource>,
            incoming: List<ToolSource>
        ): List<ToolSource> {
            val result = current.toMutableList()
            val seen = current.map { it.url }.toMutableSet()
            for (source in incoming) {
                if (seen.add(source.url)) {
                    result.add(source)
                }
            }
            return result
        }

        private fun mergedUsage(
            current: TokenUsageSnapshot?,
            incoming: TokenUsageSnapshot?
        ): TokenUsageSnapshot? {
            if (current == null && incoming == null) return null
            fun sum(lhs: Int?, rhs: Int?): Int? {
                if (lhs == null && rhs == null) return null
                return maxOf(0, lhs ?: 0) + maxOf(0, rhs ?: 0)
            }
            val merged = TokenUsageSnapshot(
                inputTokens = sum(current?.inputTokens, incoming?.inputTokens) ?: 0,
                outputTokens = sum(current?.outputTokens, incoming?.outputTokens) ?: 0,
                totalTokens = sum(current?.totalTokens, incoming?.totalTokens) ?: 0,
                reasoningTokens = sum(current?.reasoningTokens, incoming?.reasoningTokens),
                cachedInputTokens = sum(current?.cachedInputTokens, incoming?.cachedInputTokens)
            ).normalized()
            return merged.takeUnless { it.isEmpty() }
        }
    }
}
