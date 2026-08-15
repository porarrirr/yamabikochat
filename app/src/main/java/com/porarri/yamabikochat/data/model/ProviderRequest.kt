package com.porarri.yamabikochat.data.model

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class ProviderTool(
    val type: String,
    val payload: Map<String, String> = emptyMap()
)

@Serializable
data class ProviderThinkingConfig(
    val enabled: Boolean? = null,
    val budget: Int? = null,
    val effort: String? = null,
    val includeThoughts: Boolean? = null,
    val exclude: Boolean? = null
)

@Serializable
data class ProviderMaxPriceConfig(
    val prompt: Double? = null,
    val completion: Double? = null,
    val request: Double? = null,
    val image: Double? = null,
    val audio: Double? = null
)

@Serializable
data class ProviderRoutingConfig(
    val order: List<String>? = null,
    @SerialName("allow_fallbacks")
    val allowFallbacks: Boolean? = null,
    @SerialName("require_parameters")
    val requireParameters: Boolean? = null,
    @SerialName("data_collection")
    val dataCollection: String? = null,
    val quantizations: List<String>? = null,
    @SerialName("max_price")
    val maxPrice: ProviderMaxPriceConfig? = null,
    val only: List<String>? = null,
    val ignore: List<String>? = null,
    val sort: String? = null
)

@Serializable
data class ProviderRequestMessage(
    val role: String,
    val content: String,
    val attachments: List<String> = emptyList(),
    val reasoningContent: String? = null,
    val toolCalls: List<ToolCall>? = null,
    val toolCallId: String? = null,
    val toolName: String? = null,
    val toolResultIsError: Boolean? = null
)

@Serializable
data class ProviderRequest(
    val model: String,
    val messages: List<ProviderRequestMessage>,
    val systemPrompt: String? = null,
    val stream: Boolean = true,
    val tools: List<ProviderTool> = emptyList(),
    val thinking: ProviderThinkingConfig? = null,
    val provider: ProviderRoutingConfig? = null,
    val metadata: Map<String, String> = emptyMap(),
    val timeoutInterval: Double? = null
)
