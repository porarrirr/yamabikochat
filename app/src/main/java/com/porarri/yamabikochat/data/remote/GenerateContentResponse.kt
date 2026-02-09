package com.porarri.yamabikochat.data.remote

import kotlinx.serialization.Serializable

@Serializable
data class GenerateContentResponse(
    val candidates: List<Candidate>? = null,
    val promptFeedback: PromptFeedback? = null,
    val text: String? = null
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
    val thought: Boolean? = null
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
