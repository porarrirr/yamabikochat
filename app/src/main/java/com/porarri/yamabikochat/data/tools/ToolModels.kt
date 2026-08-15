package com.porarri.yamabikochat.data.tools

import com.porarri.yamabikochat.data.remote.TokenUsageSnapshot
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.json.JSONArray
import org.json.JSONObject

data class ToolDefinition(
    val name: String,
    val description: String,
    val parametersJSON: String
)

data class ToolCall(
    val id: String,
    val name: String,
    val argumentsJSON: String,
    val providerMetadata: Map<String, String>? = null
)

data class ToolResult(
    val callId: String,
    val name: String,
    val content: String,
    val isError: Boolean = false,
    val sources: List<ToolSource> = emptyList()
)

@Serializable
data class ToolSource(
    val title: String,
    val url: String
)

data class ToolCallDelta(
    val index: Int,
    val id: String? = null,
    val name: String? = null,
    val argumentsFragment: String = "",
    val providerMetadata: Map<String, String>? = null
)

class ToolCallAccumulator {
    private data class PartialCall(
        var id: String = "",
        var name: String = "",
        var argumentsJSON: String = "",
        var providerMetadata: MutableMap<String, String>? = null
    )

    private val partials = mutableMapOf<Int, PartialCall>()

    fun append(delta: ToolCallDelta) {
        val partial = partials.getOrPut(delta.index) { PartialCall() }
        val id = delta.id
        if (!id.isNullOrEmpty()) {
            partial.id += incrementalDelta(partial.id, id)
        }
        val name = delta.name
        if (!name.isNullOrEmpty()) {
            partial.name += incrementalDelta(partial.name, name)
        }
        if (delta.argumentsFragment.isNotEmpty()) {
            partial.argumentsJSON += incrementalDelta(partial.argumentsJSON, delta.argumentsFragment)
        }
        delta.providerMetadata?.let { metadata ->
            val merged = partial.providerMetadata ?: mutableMapOf()
            merged.putAll(metadata)
            partial.providerMetadata = merged
        }
        partials[delta.index] = partial
    }

    val toolCalls: List<ToolCall>
        get() = partials.keys.sorted().mapNotNull { index ->
            val partial = partials[index] ?: return@mapNotNull null
            val name = partial.name.trim().takeIf { it.isNotEmpty() } ?: return@mapNotNull null
            val id = partial.id.trim().takeIf { it.isNotEmpty() } ?: "tool-call-$index"
            ToolCall(
                id = id,
                name = name,
                argumentsJSON = partial.argumentsJSON.trim().takeIf { it.isNotEmpty() } ?: "{}",
                providerMetadata = partial.providerMetadata?.toMap()
            )
        }
}

@Serializable
data class ToolActivityStep(
    val id: String,
    val round: Int,
    val toolName: String,
    val title: String,
    val detail: String,
    var status: Status,
    var resultCount: Int? = null,
    var sources: List<ToolSource> = emptyList(),
    var errorMessage: String? = null,
    val createdAtMs: Long
) {
    @Serializable
    enum class Status {
        running,
        completed,
        failed
    }

    fun finish(with: ToolResult) {
        sources = with.sources
        if (with.isError) {
            status = Status.failed
            errorMessage = errorMessageFrom(with.content)
            return
        }
        status = Status.completed
        if (toolName == CLIENT_TOOL_WEB_SEARCH) {
            resultCount = with.sources.size
        }
    }

    companion object {
        private const val CLIENT_TOOL_WEB_SEARCH = "web_search"
        private const val CLIENT_TOOL_FETCH_URL = "fetch_url"

        fun started(call: ToolCall, round: Int): ToolActivityStep {
            val arguments = runCatching { ToolArguments.objectFrom(call.argumentsJSON) }.getOrDefault(emptyMap())
            val detail = when (call.name) {
                CLIENT_TOOL_WEB_SEARCH ->
                    (arguments["query"] as? String)?.trim()?.takeIf { it.isNotEmpty() }
                        ?: call.argumentsJSON
                CLIENT_TOOL_FETCH_URL ->
                    (arguments["url"] as? String)?.trim()?.takeIf { it.isNotEmpty() }
                        ?: call.argumentsJSON
                else -> call.argumentsJSON
            }
            return ToolActivityStep(
                id = call.id,
                round = round,
                toolName = call.name,
                title = if (call.name == CLIENT_TOOL_WEB_SEARCH) "Webを検索" else "ページを取得",
                detail = detail,
                status = Status.running,
                resultCount = null,
                sources = emptyList(),
                errorMessage = null,
                createdAtMs = System.currentTimeMillis()
            )
        }

        private fun errorMessageFrom(content: String): String {
            return runCatching {
                JSONObject(content).optString("error").takeIf { it.isNotEmpty() }
            }.getOrNull() ?: content
        }

        private val codec = Json {
            ignoreUnknownKeys = true
            isLenient = true
            encodeDefaults = true
        }

        fun encodeSteps(steps: List<ToolActivityStep>): String =
            codec.encodeToString(steps)

        fun decodeSteps(stepsJSON: String): List<ToolActivityStep> {
            val trimmed = stepsJSON.trim()
            if (trimmed.isEmpty()) return emptyList()
            return runCatching { codec.decodeFromString<List<ToolActivityStep>>(trimmed) }
                .getOrDefault(emptyList())
        }
    }
}

data class ToolTurnMessage(
    val role: String,
    val content: String,
    val toolCalls: List<ToolCall>? = null,
    val toolCallId: String? = null,
    val toolName: String? = null,
    val toolResultIsError: Boolean? = null,
    val reasoningContent: String? = null
)

data class ToolTurnRequest(
    val messages: MutableList<ToolTurnMessage>
)

data class ToolTurnResponse(
    val text: String,
    val reasoningSummary: String? = null,
    val toolCalls: List<ToolCall> = emptyList(),
    val usage: TokenUsageSnapshot? = null
)

data class ToolCallingOutcome(
    val response: ToolTurnResponse,
    val activities: List<ToolActivityStep>,
    val sources: List<ToolSource>,
    val rounds: Int,
    val replayMessages: List<ToolTurnMessage>
)

data class ToolCallingProgress(
    val activities: List<ToolActivityStep>,
    val replayMessages: List<ToolTurnMessage>
)

object ToolArguments {
    fun objectFrom(json: String): Map<String, Any?> {
        val trimmed = json.trim()
        if (trimmed.isEmpty()) {
            throw WebToolException.ParseFailure("Tool arguments must be a JSON object")
        }
        val parsed = runCatching { JSONObject(trimmed) }.getOrElse {
            throw WebToolException.ParseFailure("Tool arguments must be a JSON object")
        }
        return parsed.keys().asSequence().associateWith { key -> jsonValue(parsed.get(key)) }
    }

    fun int(value: Any?): Int? {
        return when (value) {
            is Int -> value
            is Long -> value.toInt()
            is Double -> value.toInt()
            is Float -> value.toInt()
            is Number -> value.toInt()
            is String -> value.toIntOrNull()
            else -> null
        }
    }

    private fun jsonValue(value: Any?): Any? {
        return when (value) {
            null, JSONObject.NULL -> null
            is JSONObject -> value.keys().asSequence().associateWith { key -> jsonValue(value.get(key)) }
            is JSONArray -> (0 until value.length()).map { jsonValue(value.get(it)) }
            else -> value
        }
    }
}

/**
 * Returns only the suffix of [incoming] that extends [buffer], matching iOS StreamDeltaAccumulator
 * and Android ChatResponseStreamer.incrementalDelta.
 */
fun incrementalDelta(buffer: String, incoming: String): String {
    if (incoming.isEmpty()) return ""
    if (incoming == buffer) return ""
    if (incoming.length > buffer.length && incoming.startsWith(buffer)) {
        return incoming.substring(buffer.length)
    }
    return incoming
}

sealed class WebToolException(message: String) : Exception(message) {
    class ParseFailure(message: String) : WebToolException(message)
    class HttpStatus(val status: Int, val body: String) :
        WebToolException("HTTP $status: ${body.take(200)}")
    class InvalidUrl(message: String) : WebToolException(message)
}
