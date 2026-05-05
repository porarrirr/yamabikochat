package com.porarri.yamabikochat.data.remote

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * OpenRouter API用のリクエスト/レスポンスデータクラス
 * OpenAI互換のChat Completions APIに準拠
 */

sealed interface OpenRouterPayload {
    val model: String
    val stream: Boolean
    val provider: ProviderPreferences?
    val reasoning: OpenRouterReasoning?
}

@Serializable
data class OpenRouterRequest(
    override val model: String,
    val messages: List<OpenRouterMessage>,
    val temperature: Float? = null,
    val top_p: Float? = null,
    val max_tokens: Int? = null,
    override val stream: Boolean = false,
    val stop: List<String>? = null,
    override val provider: ProviderPreferences? = null,
    override val reasoning: OpenRouterReasoning? = null,
    @SerialName("reasoning_split")
    val reasoningSplit: Boolean? = null,
    val thinking: ZaiThinking? = null,
    @SerialName("cache_control")
    val cacheControl: PromptCacheControl? = null,
    @SerialName("prompt_cache_key")
    val promptCacheKey: String? = null
) : OpenRouterPayload

@Serializable
data class OpenRouterMultiModalRequest(
    override val model: String,
    val messages: List<OpenRouterMultiModalMessage>,
    val temperature: Float? = null,
    val top_p: Float? = null,
    val max_tokens: Int? = null,
    override val stream: Boolean = false,
    val stop: List<String>? = null,
    override val provider: ProviderPreferences? = null,
    override val reasoning: OpenRouterReasoning? = null,
    @SerialName("reasoning_split")
    val reasoningSplit: Boolean? = null,
    val thinking: ZaiThinking? = null,
    @SerialName("cache_control")
    val cacheControl: PromptCacheControl? = null,
    @SerialName("prompt_cache_key")
    val promptCacheKey: String? = null
) : OpenRouterPayload

@Serializable
data class PromptCacheControl(
    val type: String = "ephemeral"
)

@Serializable
data class OpenRouterMessage(
    val role: String,
    val content: String
)

@Serializable
data class OpenRouterMultiModalMessage(
    val role: String,
    val content: List<OpenRouterContentPart>
)

@Serializable
sealed class OpenRouterContentPart {
    @Serializable
    @SerialName("text")
    data class TextPart(
        val text: String
    ) : OpenRouterContentPart()
    
    @Serializable
    @SerialName("image_url")
    data class ImagePart(
        @SerialName("image_url")
        val imageUrl: OpenRouterImageUrl
    ) : OpenRouterContentPart()
}

@Serializable
data class OpenRouterImageUrl(
    val url: String,
    val detail: String = "auto"
)

@Serializable
data class OpenRouterResponse(
    val id: String,
    @kotlinx.serialization.SerialName("object")
    val objectType: String,
    val created: Long,
    val model: String,
    val choices: List<OpenRouterChoice>,
    val usage: OpenRouterUsage? = null
)

@Serializable
data class OpenRouterChoice(
    val index: Int,
    val message: OpenRouterResponseMessage,
    val finish_reason: String? = null
)

@Serializable
data class OpenRouterResponseMessage(
    val role: String,
    val content: String,
    // For reasoning/thinking-enabled models, OpenRouter may return chain-of-thought here
    val reasoning: String? = null,
    // Z.ai returns reasoning under reasoning_content
    @SerialName("reasoning_content")
    val reasoningContent: String? = null,
    @SerialName("reasoning_details")
    val reasoningDetails: List<ReasoningDetail>? = null
)

@Serializable
data class ReasoningDetail(
    val text: String? = null,
    val type: String? = null
)

@Serializable
data class OpenRouterUsage(
    val prompt_tokens: Int? = null,
    val completion_tokens: Int? = null,
    val total_tokens: Int? = null,
    val prompt_tokens_details: OpenRouterPromptTokenDetails? = null,
    val completion_tokens_details: OpenRouterCompletionTokenDetails? = null,
    val cost: Double? = null
)

@Serializable
data class OpenRouterPromptTokenDetails(
    val cached_tokens: Int? = null
)

@Serializable
data class OpenRouterCompletionTokenDetails(
    val reasoning_tokens: Int? = null
)

// Neutral, OpenAI-compatible stream response (used by Z.ai / OpenRouter / OpenAI-compat)
@Serializable
data class ChatCompletionStreamResponse(
    val id: String = "",
    @kotlinx.serialization.SerialName("object")
    val objectType: String? = null, // 一部のプロバイダーは省略するため必須にしない
    val created: Long = 0L,
    val model: String = "",
    val choices: List<ChatCompletionStreamChoice> = emptyList(),
    val usage: OpenRouterUsage? = null
)

@Serializable
data class ChatCompletionStreamChoice(
    val index: Int,
    val delta: ChatCompletionDelta = ChatCompletionDelta(),
    val finish_reason: String? = null
)

@Serializable
data class ChatCompletionDelta(
    val role: String? = null,
    val content: String? = null,
    // For reasoning streams, thinking tokens arrive here
    val reasoning: String? = null,
    // Some providers use 'reasoning_content' instead of 'reasoning'
    @SerialName("reasoning_content")
    val reasoningContent: String? = null,
    @SerialName("reasoning_details")
    val reasoningDetails: List<ReasoningDetail>? = null
)

// Backward-compatible aliases (old names kept to reduce churn)
typealias OpenRouterStreamResponse = ChatCompletionStreamResponse
typealias OpenRouterStreamChoice = ChatCompletionStreamChoice
typealias OpenRouterDelta = ChatCompletionDelta

@Serializable
data class ProviderPreferences(
    val order: List<String>? = null,
    val allow_fallbacks: Boolean? = null,
    val require_parameters: Boolean? = null,
    val data_collection: String? = null,
    val quantizations: List<String>? = null,
    val max_price: MaxPrice? = null,
    val only: List<String>? = null,
    val ignore: List<String>? = null,
    val sort: String? = null
)

@Serializable
data class MaxPrice(
    val prompt: Double? = null,
    val completion: Double? = null,
    val request: Double? = null,
    val image: Double? = null,
    val audio: Double? = null
)

@Serializable
data class OpenRouterReasoning(
    // Enable or disable externalized reasoning tokens
    val enabled: Boolean? = null,
    // Optional guidance for effort level: e.g., "low", "medium", "high"
    val effort: String? = null,
    // Upper bound for reasoning tokens
    val max_tokens: Int? = null,
    // Whether to exclude reasoning from the assistant output (keep private)
    val exclude: Boolean? = null
)

@Serializable
data class ZaiThinking(
    // "enabled" or "disabled"
    val type: String
)
