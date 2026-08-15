package com.porarri.yamabikochat.data.remote

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class AnthropicMessageRequest(
    val model: String,
    val messages: List<AnthropicMessage>,
    val system: String? = null,
    @SerialName("max_tokens")
    val maxTokens: Int,
    val stream: Boolean = false,
    val thinking: AnthropicThinking? = null,
    @SerialName("output_config")
    val outputConfig: AnthropicOutputConfig? = null,
    @SerialName("cache_control")
    val cacheControl: AnthropicCacheControl? = null,
    @SerialName("mcp_servers")
    val mcpServers: List<AnthropicMcpServer>? = null,
    val tools: List<JsonElement>? = null
)

@Serializable
data class AnthropicCacheControl(
    val type: String = "ephemeral"
)

@Serializable
data class AnthropicMessage(
    val role: String,
    val content: List<AnthropicContentBlock>
)

@Serializable
data class AnthropicContentBlock(
    val type: String,
    val text: String? = null,
    val source: AnthropicImageSource? = null,
    val id: String? = null,
    val name: String? = null,
    val input: JsonElement? = null,
    @SerialName("tool_use_id")
    val toolUseId: String? = null,
    val content: String? = null,
    @SerialName("is_error")
    val isError: Boolean? = null
)

@Serializable
data class AnthropicImageSource(
    val type: String = "base64",
    @SerialName("media_type")
    val mediaType: String,
    val data: String
)

@Serializable
data class AnthropicThinking(
    val type: String = "enabled",
    @SerialName("budget_tokens")
    val budgetTokens: Int
)

@Serializable
data class AnthropicOutputConfig(
    val effort: String
)

@Serializable
data class AnthropicMcpServer(
    val type: String = "url",
    val url: String,
    val name: String,
    @SerialName("authorization_token")
    val authorizationToken: String? = null
)

@Serializable
data class AnthropicMcpToolset(
    val type: String = "mcp_toolset",
    @SerialName("mcp_server_name")
    val mcpServerName: String,
    @SerialName("default_config")
    val defaultConfig: AnthropicMcpToolConfiguration? = null,
    val configs: Map<String, AnthropicMcpToolConfiguration>? = null
)

@Serializable
data class AnthropicMcpToolConfiguration(
    val enabled: Boolean? = null
)

@Serializable
data class AnthropicMessageResponse(
    val id: String? = null,
    val type: String? = null,
    val role: String? = null,
    val content: List<AnthropicResponseContentBlock> = emptyList(),
    val usage: AnthropicUsage? = null
)

@Serializable
data class AnthropicResponseContentBlock(
    val type: String,
    val text: String? = null,
    val thinking: String? = null,
    val id: String? = null,
    val name: String? = null,
    val input: JsonElement? = null
)

@Serializable
data class AnthropicUsage(
    @SerialName("input_tokens")
    val inputTokens: Int? = null,
    @SerialName("output_tokens")
    val outputTokens: Int? = null,
    @SerialName("cache_read_input_tokens")
    val cacheReadInputTokens: Int? = null,
    @SerialName("cache_creation_input_tokens")
    val cacheCreationInputTokens: Int? = null
) {
    fun toTokenUsageSnapshot(): TokenUsageSnapshot {
        val input = (inputTokens ?: 0).coerceAtLeast(0)
        val output = (outputTokens ?: 0).coerceAtLeast(0)
        val cached = (cacheReadInputTokens ?: 0).coerceAtLeast(0)
        return TokenUsageSnapshot(
            inputTokens = input,
            outputTokens = output,
            totalTokens = input + output,
            cachedInputTokens = cached.takeIf { it > 0 }
        )
    }
}
