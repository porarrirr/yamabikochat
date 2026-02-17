package com.porarri.yamabikochat.data.remote

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement

@Serializable
data class GeminiCliGenerateContentRequest(
    val model: String,
    val project: String? = null,
    @SerialName("user_prompt_id")
    val userPromptId: String? = null,
    val request: GeminiCliRequest
)

@Serializable
data class GeminiCliRequest(
    val contents: List<Content>,
    @SerialName("systemInstruction")
    val systemInstruction: Content? = null,
    val tools: List<Tool>? = null,
    @SerialName("toolConfig")
    val toolConfig: ToolConfig? = null,
    val generationConfig: GeminiCliGenerationConfig? = null,
    @SerialName("session_id")
    val sessionId: String? = null
)

@Serializable
data class GeminiCliGenerationConfig(
    val temperature: Float? = null,
    val topK: Int? = null,
    val topP: Float? = null,
    val maxOutputTokens: Int? = null,
    val stopSequences: List<String>? = null,
    @SerialName("responseMimeType")
    val responseMimeType: String? = null,
    @SerialName("responseJsonSchema")
    val responseJsonSchema: JsonElement? = null,
    val thinkingConfig: ThinkingConfig? = null
)

@Serializable
data class GeminiCliGenerateContentResponse(
    val response: GeminiCliResponseBody,
    val traceId: String? = null
)

@Serializable
data class GeminiCliResponseBody(
    val candidates: List<Candidate>? = null,
    val promptFeedback: PromptFeedback? = null,
    @SerialName("usageMetadata")
    val usageMetadata: GeminiUsageMetadata? = null
)
