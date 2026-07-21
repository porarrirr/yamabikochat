package com.porarri.yamabikochat.ui.chat.logic

import com.porarri.yamabikochat.BuildConfig
import com.porarri.yamabikochat.data.remote.GenerateContentResponse
import com.porarri.yamabikochat.data.remote.OpenCodeGoEndpointKind
import com.porarri.yamabikochat.data.remote.OpenCodeGoModelCatalog
import com.porarri.yamabikochat.data.remote.ResponsePart
import com.porarri.yamabikochat.data.remote.TokenUsageSnapshot
import com.porarri.yamabikochat.data.remote.extractTokenUsageSnapshot
import com.porarri.yamabikochat.data.remote.toTokenUsageSnapshot
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.ResponseBody

/**
 * Shared SSE / NDJSON stream consumer for provider responses.
 * Emits cumulative text + thinking via [onDelta].
 */
object StreamChunkConsumer {
    private const val DONE_TOKEN = "[DONE]"

    data class StreamResult(
        val text: String,
        val thinking: String,
        val summary: String = "",
        val hasData: Boolean = false
    )

    suspend fun consumeStream(
        body: ResponseBody,
        provider: String,
        model: String,
        json: Json,
        onDelta: suspend (text: String, thinking: String, summary: String) -> Unit,
        onUsage: suspend (TokenUsageSnapshot) -> Unit = {}
    ): Pair<String, String> {
        val result = consumeStreamDetailed(body, provider, model, json, onDelta, onUsage)
        return result.text to result.thinking
    }

    suspend fun consumeStreamDetailed(
        body: ResponseBody,
        provider: String,
        model: String,
        json: Json,
        onDelta: suspend (text: String, thinking: String, summary: String) -> Unit,
        onUsage: suspend (TokenUsageSnapshot) -> Unit = {}
    ): StreamResult {
        var currentText = ""
        var currentThinking = ""
        var currentSummary = ""
        var hasData = false
        var usageRecorded = false
        var parseError: Throwable? = null
        var parseErrorCount = 0
        val nonDataLines = mutableListOf<String>()
        var sawAnyLine = false

        val normalizedProvider = provider.uppercase()
        val isOpenCodeGoMessagesModel =
            normalizedProvider == "OPENCODE_GO" &&
                OpenCodeGoModelCatalog.modelFor(model)?.endpointKind == OpenCodeGoEndpointKind.MESSAGES
        val isAnthropicCompatibleStream =
            normalizedProvider == "ALIBABA_CODING_PLAN" || isOpenCodeGoMessagesModel
        val isOpenAiCompatibleStream = normalizedProvider == "OPENROUTER" ||
            normalizedProvider == "ZAI" ||
            normalizedProvider == "OPENAI" ||
            normalizedProvider == "MINIMAX" ||
            normalizedProvider == "OPENAI_COMPAT" ||
            normalizedProvider == "CLINEPASS" ||
            (normalizedProvider == "OPENCODE_GO" && !isOpenCodeGoMessagesModel)

        val reader = body.byteStream().bufferedReader(Charsets.UTF_8)
        try {
            val eventBuffer = StringBuilder()

            suspend fun recordUsageOnce(snapshot: TokenUsageSnapshot?) {
                if (usageRecorded) return
                val usage = snapshot?.normalized() ?: return
                if (usage.isEmpty()) return
                onUsage(usage)
                usageRecorded = true
            }

            suspend fun flushEvent() {
                val payload = eventBuffer.toString().trim()
                eventBuffer.setLength(0)
                if (payload.isEmpty() || payload == DONE_TOKEN) {
                    return
                }

                try {
                    val parsedChunk = if (normalizedProvider == "CODEX_AUTH" || normalizedProvider == "SUPERGROK") {
                        val delta = parseCodexResponsesDelta(json, payload, currentText)
                        val usage = parseCodexResponsesUsage(json, payload)
                        StreamChunkParse(
                            deltaText = delta.first,
                            deltaThinking = delta.second,
                            deltaSummary = delta.third,
                            usage = usage
                        )
                    } else if (isAnthropicCompatibleStream) {
                        parseAnthropicCompatibleDelta(json, payload)
                    } else if (isOpenAiCompatibleStream) {
                        val streamResponse = json.decodeFromString<com.porarri.yamabikochat.data.remote.ChatCompletionStreamResponse>(payload)
                        val delta = streamResponse.choices.firstOrNull()?.delta
                        val fullText = delta?.content.orEmpty()
                        val fullThinking = delta?.reasoningDetails
                            ?.joinToString(separator = "") { it.text.orEmpty() }
                            ?.takeIf { it.isNotBlank() }
                            ?: (delta?.reasoning ?: delta?.reasoningContent).orEmpty()

                        val textDelta = incrementalDelta(currentText, fullText)
                        val thinkingDelta = incrementalDelta(currentThinking, fullThinking)
                        StreamChunkParse(
                            deltaText = textDelta,
                            deltaThinking = thinkingDelta,
                            usage = streamResponse.usage?.toTokenUsageSnapshot()
                        )
                    } else {
                        val chunk = json.decodeFromString<GenerateContentResponse>(payload)
                        val parts = chunk.candidates?.firstOrNull()?.content?.parts.orEmpty()
                        val parsed = parseGeminiParts(parts)
                        val textDelta = parsed.text + chunk.text.orEmpty()
                        StreamChunkParse(
                            deltaText = textDelta,
                            deltaThinking = parsed.thinking,
                            usage = chunk.extractTokenUsageSnapshot()
                        )
                    }

                    recordUsageOnce(parsedChunk.usage)

                    currentThinking += parsedChunk.deltaThinking
                    if (parsedChunk.deltaSummary.isNotEmpty()) {
                        currentSummary += parsedChunk.deltaSummary
                    }
                    if (
                        parsedChunk.deltaText.isNotEmpty() ||
                        parsedChunk.deltaThinking.isNotEmpty() ||
                        parsedChunk.deltaSummary.isNotEmpty()
                    ) {
                        hasData = true
                        currentText += parsedChunk.deltaText
                        onDelta(currentText, currentThinking, currentSummary)
                    }
                } catch (e: Exception) {
                    parseErrorCount += 1
                    if (parseError == null) parseError = e
                    DiagnosticsLogger.log(
                        "Failed to parse streaming chunk provider=${provider.uppercase()} model=$model payload=${payload.take(512)}",
                        e
                    )
                    if (BuildConfig.DEBUG || BuildConfig.DIAGNOSTIC) {
                        android.util.Log.e(
                            "StreamChunkConsumer",
                            "Failed to parse streaming chunk: ${payload.take(256)}",
                            e
                        )
                    } else {
                        android.util.Log.e("StreamChunkConsumer", "Failed to parse streaming chunk", e)
                    }
                }
            }

            while (true) {
                val rawLine = reader.readLine() ?: break
                sawAnyLine = true
                val trimmedLine = rawLine.trim()
                if (trimmedLine.startsWith(":")) continue
                if (trimmedLine.isEmpty()) {
                    if (eventBuffer.isNotEmpty()) flushEvent()
                    continue
                }
                if (trimmedLine.startsWith("{") || trimmedLine.startsWith("[")) {
                    if (eventBuffer.isNotEmpty()) flushEvent()
                    eventBuffer.append(trimmedLine)
                    flushEvent()
                } else if (trimmedLine.startsWith("data:")) {
                    val payload = trimmedLine.substringAfter("data:").trimStart()
                    if (eventBuffer.isNotEmpty()) {
                        val pending = eventBuffer.toString().trim()
                        if (looksLikeCompleteJsonEvent(json, pending)) {
                            flushEvent()
                        } else {
                            eventBuffer.append('\n')
                        }
                    }
                    eventBuffer.append(payload)
                } else if (nonDataLines.size < 8) {
                    if (trimmedLine.isNotEmpty()) {
                        nonDataLines.add(trimmedLine.take(256))
                    }
                }
            }

            if (eventBuffer.isNotEmpty()) {
                flushEvent()
            }
        } finally {
            reader.close()
        }

        if (!hasData) {
            parseError?.let {
                DiagnosticsLogger.log(
                    "Streaming finished without usable data provider=${provider.uppercase()} model=$model parseErrors=$parseErrorCount",
                    it
                )
            }
            if (parseError == null) {
                DiagnosticsLogger.log(
                    "Streaming had no data provider=${provider.uppercase()} model=$model sawAnyLine=$sawAnyLine nonDataLines=${nonDataLines.joinToString(" | ")}"
                )
            }
        }

        return StreamResult(
            text = currentText,
            thinking = currentThinking,
            summary = currentSummary,
            hasData = hasData
        )
    }

    private data class ParsedParts(val text: String, val thinking: String)

    private fun parseGeminiParts(parts: List<ResponsePart>): ParsedParts {
        val textBuilder = StringBuilder()
        val thinkingBuilder = StringBuilder()
        for (part in parts) {
            if (part.thought == true) {
                thinkingBuilder.append(part.text.orEmpty())
            } else {
                part.text?.let { textBuilder.append(it) }
            }
        }
        return ParsedParts(textBuilder.toString(), thinkingBuilder.toString())
    }

    private fun incrementalDelta(buffer: String, incoming: String): String {
        if (incoming.isEmpty()) return ""
        if (incoming == buffer) return ""
        if (incoming.length > buffer.length && incoming.startsWith(buffer)) {
            return incoming.substring(buffer.length)
        }
        return incoming
    }

    private fun parseCodexResponsesDelta(
        json: Json,
        payload: String,
        currentText: String
    ): Triple<String, String, String> {
        val element = runCatching { json.parseToJsonElement(payload) }.getOrNull() ?: return Triple("", "", "")
        val obj = element.jsonObject
        val type = obj["type"]?.jsonPrimitive?.contentOrNull ?: return Triple("", "", "")
        val delta = obj["delta"]?.jsonPrimitive?.contentOrNull.orEmpty()
        return when (type) {
            "response.output_text.delta" -> Triple(incrementalDelta(currentText, delta), "", "")
            "response.reasoning_text.delta" -> Triple("", delta, "")
            "response.reasoning_summary_text.delta" -> Triple("", "", delta)
            "response.output_item.done" -> {
                val fullText = extractOutputTextFromItem(obj["item"]?.jsonObject)
                Triple(incrementalDelta(currentText, fullText), "", "")
            }
            else -> Triple("", "", "")
        }
    }

    private fun parseCodexResponsesUsage(json: Json, payload: String): TokenUsageSnapshot? {
        val element = runCatching { json.parseToJsonElement(payload) }.getOrNull() ?: return null
        val obj = element.jsonObject
        if (obj["type"]?.jsonPrimitive?.contentOrNull != "response.completed") return null
        val usageObj = runCatching {
            obj["response"]?.jsonObject?.get("usage")?.jsonObject
        }.getOrNull() ?: return null
        val inputTokens = usageObj["input_tokens"]?.jsonPrimitive?.contentOrNull?.toIntOrNull() ?: 0
        val outputTokens = usageObj["output_tokens"]?.jsonPrimitive?.contentOrNull?.toIntOrNull() ?: 0
        val totalTokens = usageObj["total_tokens"]?.jsonPrimitive?.contentOrNull?.toIntOrNull()
            ?: (inputTokens + outputTokens)
        val reasoningTokens = runCatching {
            usageObj["output_tokens_details"]?.jsonObject
                ?.get("reasoning_tokens")
                ?.jsonPrimitive
                ?.contentOrNull
                ?.toIntOrNull()
        }.getOrNull()
        val cachedTokens = runCatching {
            usageObj["input_tokens_details"]?.jsonObject
                ?.get("cached_tokens")
                ?.jsonPrimitive
                ?.contentOrNull
                ?.toIntOrNull()
        }.getOrNull()
        val snapshot = TokenUsageSnapshot(
            inputTokens = inputTokens,
            outputTokens = outputTokens,
            totalTokens = totalTokens,
            reasoningTokens = reasoningTokens,
            cachedInputTokens = cachedTokens
        ).normalized()
        return snapshot.takeUnless { it.isEmpty() }
    }

    private fun extractOutputTextFromItem(item: kotlinx.serialization.json.JsonObject?): String {
        if (item == null) return ""
        val type = item["type"]?.jsonPrimitive?.contentOrNull
        if (type != "message") return ""
        val role = item["role"]?.jsonPrimitive?.contentOrNull
        if (role != "assistant") return ""
        val content = item["content"]?.jsonArray ?: return ""
        val builder = StringBuilder()
        content.forEach { block ->
            val blockObj = block.jsonObject
            if (blockObj["type"]?.jsonPrimitive?.contentOrNull == "output_text") {
                builder.append(blockObj["text"]?.jsonPrimitive?.contentOrNull.orEmpty())
            }
        }
        return builder.toString()
    }

    private fun parseAnthropicCompatibleDelta(json: Json, payload: String): StreamChunkParse {
        val element = json.parseToJsonElement(payload)
        val obj = element.jsonObject
        val type = obj["type"]?.jsonPrimitive?.contentOrNull?.lowercase() ?: return StreamChunkParse("", "")
        return when (type) {
            "content_block_delta" -> {
                val delta = obj["delta"]?.jsonObject ?: return StreamChunkParse("", "")
                when (delta["type"]?.jsonPrimitive?.contentOrNull?.lowercase()) {
                    "text_delta" -> StreamChunkParse(
                        deltaText = delta["text"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                        deltaThinking = ""
                    )
                    "thinking_delta" -> StreamChunkParse(
                        deltaText = "",
                        deltaThinking = delta["thinking"]?.jsonPrimitive?.contentOrNull.orEmpty()
                    )
                    else -> StreamChunkParse("", "")
                }
            }
            "content_block_start" -> {
                val block = obj["content_block"]?.jsonObject ?: return StreamChunkParse("", "")
                when (block["type"]?.jsonPrimitive?.contentOrNull?.lowercase()) {
                    "text" -> StreamChunkParse(
                        deltaText = block["text"]?.jsonPrimitive?.contentOrNull.orEmpty(),
                        deltaThinking = ""
                    )
                    "thinking" -> StreamChunkParse(
                        deltaText = "",
                        deltaThinking = block["thinking"]?.jsonPrimitive?.contentOrNull.orEmpty()
                    )
                    else -> StreamChunkParse("", "")
                }
            }
            "message_stop", "message_delta", "message_start", "ping" -> StreamChunkParse("", "")
            else -> StreamChunkParse("", "")
        }
    }

    private fun looksLikeCompleteJsonEvent(json: Json, raw: String): Boolean {
        if (!raw.startsWith("{")) return false
        val obj = runCatching { json.parseToJsonElement(raw).jsonObject }.getOrNull() ?: return false
        return obj.containsKey("choices") || obj.containsKey("type") || obj.containsKey("candidates")
    }

    private data class StreamChunkParse(
        val deltaText: String,
        val deltaThinking: String,
        val deltaSummary: String = "",
        val usage: TokenUsageSnapshot? = null
    )
}
