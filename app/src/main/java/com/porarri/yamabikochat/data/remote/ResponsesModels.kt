@file:OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)

package com.porarri.yamabikochat.data.remote

import kotlinx.serialization.EncodeDefault
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonClassDiscriminator
import kotlinx.serialization.json.JsonElement

@Serializable
data class ResponsesRequest(
    val model: String,
    val input: List<ResponseInputItem>,
    val instructions: String = "",
    val tools: List<JsonElement> = emptyList(),
    @SerialName("tool_choice")
    val toolChoice: String = "auto",
    @SerialName("parallel_tool_calls")
    val parallelToolCalls: Boolean = false,
    val stream: Boolean = false,
    @EncodeDefault
    val store: Boolean = false,
    val include: List<String> = emptyList(),
    val text: ResponsesTextConfig? = null,
    @SerialName("prompt_cache_key")
    val promptCacheKey: String? = null,
    @SerialName("max_output_tokens")
    val maxOutputTokens: Int? = null,
    val temperature: Float? = null,
    @SerialName("top_p")
    val topP: Float? = null,
    val reasoning: ResponsesReasoning? = null
)

@Serializable
data class ResponsesTextConfig(
    val verbosity: String? = null
)

@Serializable
data class ResponseInputItem(
    @EncodeDefault
    val type: String = "message",
    val role: String,
    val content: List<ResponseInputContent>
)

@Serializable
@JsonClassDiscriminator("type")
sealed class ResponseInputContent

@Serializable
@SerialName("input_text")
data class ResponseInputText(
    val text: String
) : ResponseInputContent()

@Serializable
@SerialName("output_text")
data class ResponseOutputText(
    val text: String
) : ResponseInputContent()

@Serializable
@SerialName("input_image")
data class ResponseInputImage(
    @SerialName("image_url")
    val imageUrl: String
) : ResponseInputContent()

@Serializable
data class ResponsesReasoning(
    val effort: String? = null,
    @SerialName("summary")
    val summary: String? = null
)

@Serializable
data class ResponsesStreamEvent(
    @SerialName("type")
    val type: String,
    val delta: String? = null,
    val item: JsonElement? = null,
    val response: JsonElement? = null,
    @SerialName("summary_index")
    val summaryIndex: Int? = null,
    @SerialName("content_index")
    val contentIndex: Int? = null
)
