package com.porarri.yamabikochat.data.model

import com.porarri.yamabikochat.data.local.ToolActivityPayload
import kotlinx.serialization.Serializable

@Serializable
data class ProviderUsage(
    val inputTokens: Int? = null,
    val outputTokens: Int? = null,
    val totalTokens: Int? = null,
    val reasoningTokens: Int? = null,
    val cachedInputTokens: Int? = null,
    val cacheCreationInputTokens: Int? = null
) {
    val isEmpty: Boolean
        get() {
            val input = maxOf(0, inputTokens ?: 0)
            val output = maxOf(0, outputTokens ?: 0)
            val total = maxOf(0, totalTokens ?: 0)
            return input <= 0 && output <= 0 && total <= 0
        }

    fun normalized(): ProviderUsage {
        val input = maxOf(0, inputTokens ?: 0)
        val output = maxOf(0, outputTokens ?: 0)
        val totalBase = totalTokens ?: (input + output)
        val total = maxOf(maxOf(0, totalBase), input + output)
        return ProviderUsage(
            inputTokens = input,
            outputTokens = output,
            totalTokens = total,
            reasoningTokens = reasoningTokens?.let { maxOf(0, it) },
            cachedInputTokens = cachedInputTokens?.let { maxOf(0, it) },
            cacheCreationInputTokens = cacheCreationInputTokens?.let { maxOf(0, it) }
        )
    }

    fun normalizedNonEmpty(): ProviderUsage? {
        val normalized = normalized()
        return if (normalized.isEmpty) null else normalized
    }

    fun adding(other: ProviderUsage?): ProviderUsage {
        if (other == null) return this
        fun sum(lhs: Int?, rhs: Int?): Int? {
            if (lhs == null && rhs == null) return null
            return maxOf(0, lhs ?: 0) + maxOf(0, rhs ?: 0)
        }
        return ProviderUsage(
            inputTokens = sum(inputTokens, other.inputTokens),
            outputTokens = sum(outputTokens, other.outputTokens),
            totalTokens = sum(totalTokens, other.totalTokens),
            reasoningTokens = sum(reasoningTokens, other.reasoningTokens),
            cachedInputTokens = sum(cachedInputTokens, other.cachedInputTokens),
            cacheCreationInputTokens = sum(cacheCreationInputTokens, other.cacheCreationInputTokens)
        )
    }
}

@Serializable
data class ProviderResponse(
    var text: String = "",
    var reasoningSummary: String? = null,
    var raw: String? = null,
    var usage: ProviderUsage? = null,
    var usageSamples: List<ProviderUsage>? = null,
    var toolCalls: List<ToolCall> = emptyList(),
    var providerTranscript: List<ProviderRequestMessage>? = null,
    var toolActivity: ToolActivityPayload? = null
)

sealed interface ProviderStreamEvent {
    data object AnswerStart : ProviderStreamEvent
    data class TextDelta(val delta: String) : ProviderStreamEvent
    data class ReasoningDelta(val delta: String) : ProviderStreamEvent
    data class ToolActivity(val event: ToolActivityEvent) : ProviderStreamEvent
    data class Completed(val response: ProviderResponse) : ProviderStreamEvent

    val includesNonEmptyAnswerText: Boolean
        get() = when (this) {
            is TextDelta -> delta.trim().isNotEmpty()
            is Completed -> response.text.trim().isNotEmpty()
            AnswerStart, is ReasoningDelta, is ToolActivity -> false
        }
}

data class ToolActivityEvent(
    val phase: Phase,
    val call: ToolCall,
    val result: ToolResult? = null,
    val createdAtMs: Long = System.currentTimeMillis()
) {
    enum class Phase { started, finished }
}
