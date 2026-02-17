package com.porarri.yamabikochat.data.remote

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class TokenUsageSnapshot(
    @SerialName("input_tokens")
    val inputTokens: Int = 0,
    @SerialName("output_tokens")
    val outputTokens: Int = 0,
    @SerialName("total_tokens")
    val totalTokens: Int = 0,
    @SerialName("reasoning_tokens")
    val reasoningTokens: Int? = null,
    @SerialName("cached_input_tokens")
    val cachedInputTokens: Int? = null
) {
    fun isEmpty(): Boolean = inputTokens <= 0 && outputTokens <= 0 && totalTokens <= 0

    fun normalized(): TokenUsageSnapshot {
        val safeInput = inputTokens.coerceAtLeast(0)
        val safeOutput = outputTokens.coerceAtLeast(0)
        val safeTotal = totalTokens.coerceAtLeast(safeInput + safeOutput)
        return copy(
            inputTokens = safeInput,
            outputTokens = safeOutput,
            totalTokens = safeTotal,
            reasoningTokens = reasoningTokens?.coerceAtLeast(0),
            cachedInputTokens = cachedInputTokens?.coerceAtLeast(0)
        )
    }
}

fun GenerateContentResponse.extractTokenUsageSnapshot(): TokenUsageSnapshot? {
    tokenUsage?.normalized()?.let { usage ->
        if (!usage.isEmpty()) return usage
    }
    usageMetadata?.let { usage ->
        val input = usage.promptTokenCount ?: 0
        val output = usage.candidatesTokenCount ?: 0
        val total = usage.totalTokenCount ?: (input + output)
        val snapshot = TokenUsageSnapshot(
            inputTokens = input,
            outputTokens = output,
            totalTokens = total,
            reasoningTokens = usage.thoughtsTokenCount,
            cachedInputTokens = usage.cachedContentTokenCount
        ).normalized()
        if (!snapshot.isEmpty()) return snapshot
    }
    return null
}

fun OpenRouterUsage.toTokenUsageSnapshot(): TokenUsageSnapshot {
    return TokenUsageSnapshot(
        inputTokens = prompt_tokens ?: 0,
        outputTokens = completion_tokens ?: 0,
        totalTokens = total_tokens ?: ((prompt_tokens ?: 0) + (completion_tokens ?: 0)),
        reasoningTokens = completion_tokens_details?.reasoning_tokens,
        cachedInputTokens = prompt_tokens_details?.cached_tokens
    ).normalized()
}
