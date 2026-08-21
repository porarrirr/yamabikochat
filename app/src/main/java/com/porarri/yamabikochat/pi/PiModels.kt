package com.porarri.yamabikochat.pi

import com.porarri.yamabikochat.data.model.LLMProvider
import com.porarri.yamabikochat.data.model.ProviderRequest
import com.porarri.yamabikochat.data.model.ProviderResponse
import com.porarri.yamabikochat.data.model.ProviderRoutingConfig
import com.porarri.yamabikochat.data.model.ProviderThinkingConfig
import com.porarri.yamabikochat.data.model.ProviderTool
import com.porarri.yamabikochat.data.model.ProviderUsage
import com.porarri.yamabikochat.data.model.ToolCall
import com.porarri.yamabikochat.data.model.ToolSource
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class PiAgentConfiguration(
    val contractVersion: Int = 2,
    val provider: String,
    val model: String,
    val apiKey: String? = null,
    val headers: Map<String, String> = emptyMap(),
    val env: Map<String, String> = emptyMap(),
    val catalogContract: PiCatalogModelContract? = null,
    val thinkingLevel: String? = null,
    val mcpAuthorizationToken: String? = null
)

@Serializable
data class PiCatalogModelContract(
    val npm: String? = null,
    val api: String? = null,
    val shape: String? = null,
    val provenance: String? = null,
    val toolCall: Boolean? = null,
    val name: String? = null,
    val reasoning: Boolean? = null,
    val input: List<String>? = null,
    val contextWindow: Long? = null,
    val maxTokens: Long? = null
)

@Serializable
data class PiModelResolution(
    val supported: Boolean,
    val reason: String? = null,
    val provider: String? = null,
    val model: String? = null,
    val api: String? = null,
    val source: String? = null,
    val reasoning: Boolean? = null,
    val input: List<String>? = null,
    val contextWindow: Int? = null,
    val maxTokens: Int? = null,
    val toolCall: Boolean? = null,
    val message: String? = null
)

@Serializable
data class PiModelResolutionEnvelope(val models: List<PiAgentConfiguration>)

@Serializable
data class PiModelResolutionResponse(val contractVersion: Int, val models: List<PiModelResolution>)

@Serializable
data class PiHealthResponse(val ok: Boolean, val contractVersion: Int)

@Serializable
data class PiAttachment(
    val data: String,
    val mimeType: String
)

@Serializable
data class PiMessage(
    val role: String,
    val content: String,
    val attachments: List<PiAttachment> = emptyList(),
    val reasoningContent: String? = null,
    val toolCalls: List<ToolCall>? = null,
    val toolCallId: String? = null,
    val toolName: String? = null,
    val toolResultIsError: Boolean? = null
)

@Serializable
data class PiRequest(
    val messages: List<PiMessage>,
    val systemPrompt: String? = null,
    val tools: List<ProviderTool> = emptyList(),
    val thinking: ProviderThinkingConfig? = null,
    val provider: ProviderRoutingConfig? = null,
    val metadata: Map<String, String> = emptyMap(),
    val timeoutInterval: Double? = null
)

@Serializable
data class PiRunEnvelope(
    val runId: String,
    val request: PiRequest,
    val config: PiAgentConfiguration
)

@Serializable
data class PiRuntimeEvent(
    val type: String,
    val runId: String? = null,
    val stage: String? = null,
    val delta: String? = null,
    val message: String? = null,
    val metadata: Map<String, String>? = null,
    val requestId: String? = null,
    val toolCallId: String? = null,
    val stepId: Int? = null,
    val timeMs: Long? = null,
    val succeeded: Boolean? = null,
    val usage: ProviderUsage? = null,
    val name: String? = null,
    val arguments: JsonElement? = null,
    val response: ProviderResponse? = null,
    val url: String? = null,
    val userCode: String? = null,
    val verificationUri: String? = null,
    val credential: JsonElement? = null,
    val profile: PiOAuthProfile? = null
)

@Serializable
enum class PiOAuthProvider {
    @SerialName("codex")
    CODEX,
    @SerialName("supergrok")
    SUPERGROK
}

@Serializable
enum class PiOAuthLoginMethod {
    @SerialName("browser")
    BROWSER,
    @SerialName("device")
    DEVICE
}

@Serializable
data class PiOAuthProfile(
    val email: String? = null,
    val planType: String? = null,
    val accountId: String? = null
)

@Serializable
data class PiOAuthResolution(
    val credential: JsonElement,
    val accessToken: String,
    val accountId: String? = null,
    val profile: PiOAuthProfile
)

@Serializable
data class PiOAuthLoginRequest(
    val provider: PiOAuthProvider,
    val method: PiOAuthLoginMethod
)

@Serializable
data class PiOAuthResolveRequest(
    val provider: PiOAuthProvider,
    val credential: JsonElement,
    val force: Boolean = false
)

@Serializable
data class PiToolResultEnvelope(
    val requestId: String,
    val content: String,
    val isError: Boolean,
    val sources: List<ToolSource> = emptyList()
)

data class SuperGrokDeviceCodeChallenge(
    val verificationURI: String,
    val userCode: String,
    val browserURL: String
)
