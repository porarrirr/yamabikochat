package com.porarri.yamabikochat.data.remote

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class GenerateContentResponse(
    val candidates: List<Candidate>? = null,
    val promptFeedback: PromptFeedback? = null,
    val text: String? = null,
    @SerialName("usageMetadata")
    val usageMetadata: GeminiUsageMetadata? = null,
    val tokenUsage: TokenUsageSnapshot? = null
)

@Serializable
data class GeminiUsageMetadata(
    @SerialName("promptTokenCount")
    val promptTokenCount: Int? = null,
    @SerialName("candidatesTokenCount")
    val candidatesTokenCount: Int? = null,
    @SerialName("totalTokenCount")
    val totalTokenCount: Int? = null,
    @SerialName("cachedContentTokenCount")
    val cachedContentTokenCount: Int? = null,
    @SerialName("toolUsePromptTokenCount")
    val toolUsePromptTokenCount: Int? = null,
    @SerialName("thoughtsTokenCount")
    val thoughtsTokenCount: Int? = null
)

@Serializable
data class Candidate(
    val content: ResponseContent? = null,
    val finishReason: String? = null,
    val index: Int = 0,
    val safetyRatings: List<SafetyRating>? = null
)

@Serializable
data class ResponseContent(
    val parts: List<ResponsePart>,
    val role: String
)

@Serializable
data class ResponsePart(
    val text: String? = null,
    val inlineData: InlineData? = null,
    val fileData: FileData? = null,
    val functionCall: FunctionCall? = null,
    val functionResponse: FunctionResponse? = null,
    val thought: Boolean? = null,
    val thoughtSignature: String? = null
)

@Serializable
data class PromptFeedback(
    val safetyRatings: List<SafetyRating>
)

@Serializable
data class SafetyRating(
    val category: String,
    val probability: String
)
