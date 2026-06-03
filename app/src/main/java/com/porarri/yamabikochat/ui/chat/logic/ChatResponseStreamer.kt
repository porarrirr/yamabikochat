package com.porarri.yamabikochat.ui.chat.logic

import com.porarri.yamabikochat.data.ChatRepository
import com.porarri.yamabikochat.data.local.ChatMessage
import com.porarri.yamabikochat.data.local.ChatMessageVariant
import com.porarri.yamabikochat.data.local.FullChatMessage
import com.porarri.yamabikochat.data.remote.GenerateContentRequest
import com.porarri.yamabikochat.data.remote.GenerateContentResponse
import com.porarri.yamabikochat.data.remote.FunctionCall
import com.porarri.yamabikochat.data.remote.FunctionResponse
import com.porarri.yamabikochat.data.remote.Part
import com.porarri.yamabikochat.data.remote.ResponsePart
import com.porarri.yamabikochat.data.remote.TokenUsageSnapshot
import com.porarri.yamabikochat.data.remote.extractTokenUsageSnapshot
import com.porarri.yamabikochat.data.remote.toTokenUsageSnapshot
import com.porarri.yamabikochat.BuildConfig
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Handles model response generation for single-provider conversations.
 * Extracted from ChatViewModel to keep the view-model lean and focused on state orchestration.
 */
class ChatResponseStreamer(
    private val repository: ChatRepository,
    private val splitReasoningBlocks: (String) -> Pair<String, String>,
    private val json: Json
) {
    /**
     * Launches a streaming request and incrementally updates the UI state.
     */
    fun launchStreamingResponse(
        scope: CoroutineScope,
        conversationId: Long,
        model: String,
        provider: String,
        request: GenerateContentRequest,
        fullMessages: MutableStateFlow<Map<Long, FullChatMessage>>,
        fetchFullMessage: (Long) -> Unit,
        existingMessageId: Long? = null
    ) {
        scope.launch(Dispatchers.IO) {
            val isRegeneration = existingMessageId != null
            var activeVariant: ChatMessageVariant? = null
            val messageId = if (existingMessageId == null) {
                val placeholderMessage =
                    ChatMessage(conversationId = conversationId, role = "model", text = "")
                repository.insertMessage(placeholderMessage)
            } else {
                val existingFull = repository.getFullMessageById(existingMessageId)
                if (existingFull == null) {
                    android.util.Log.e(
                        "ChatResponseStreamer",
                        "Regeneration failed: message not found id=$existingMessageId"
                    )
                    return@launch
                }
                val createdVariant = repository.insertMessageVariant(
                    baseMessageId = existingMessageId,
                    text = "",
                    attachments = emptyList(),
                    thinkingStream = null
                )
                activeVariant = createdVariant
                val selectedBase = existingFull.chatMessage.copy(selectedVariantIndex = createdVariant.variantIndex)
                fullMessages.update { currentMap ->
                    currentMap + (
                        existingMessageId to existingFull.copy(
                            chatMessage = selectedBase,
                            variants = (existingFull.variants.filterNot { it.variantIndex == createdVariant.variantIndex } + createdVariant)
                                .sortedBy { it.variantIndex }
                        )
                    )
                }
                existingMessageId
            }

            fun updateFullMessageState(
                text: String,
                attachments: List<String>,
                thinkingSummary: String?,
                thinkingStream: String
            ) {
                fullMessages.update { currentMap ->
                    val existingFull = currentMap[messageId]
                    val variant = activeVariant
                    if (variant != null) {
                        val updatedVariant = variant.copy(
                            text = text,
                            attachments = attachments,
                            thinkingStream = thinkingStream.takeIf { it.isNotBlank() } ?: thinkingSummary
                        )
                        activeVariant = updatedVariant
                        val base = (existingFull?.chatMessage ?: ChatMessage(
                            id = messageId,
                            conversationId = conversationId,
                            role = "model",
                            text = ""
                        )).copy(selectedVariantIndex = variant.variantIndex)
                        val variants = (existingFull?.variants.orEmpty()
                            .filterNot { it.variantIndex == updatedVariant.variantIndex } + updatedVariant)
                            .sortedBy { it.variantIndex }
                        currentMap + (messageId to FullChatMessage(base, existingFull?.thinkingStream, variants))
                    } else {
                        val updated = FullChatMessage(
                            chatMessage = ChatMessage(
                                id = messageId,
                                conversationId = conversationId,
                                role = "model",
                                text = text,
                                attachments = attachments,
                                thinkingSummary = thinkingSummary
                            ),
                            thinkingStream = thinkingStream
                        )
                        currentMap + (messageId to updated)
                    }
                }
            }

            suspend fun persistResponse(
                text: String,
                attachments: List<String> = emptyList(),
                thinkingSummary: String? = null,
                thinkingStream: String = ""
            ) {
                val variant = activeVariant
                if (variant != null) {
                    val updatedVariant = variant.copy(
                        text = text,
                        attachments = attachments,
                        thinkingStream = thinkingStream.takeIf { it.isNotBlank() } ?: thinkingSummary
                    )
                    repository.updateMessageVariant(updatedVariant)
                    activeVariant = updatedVariant
                    return
                }

                repository.getFullMessageById(messageId)?.chatMessage?.let {
                    repository.updateMessage(
                        it.copy(
                            text = text,
                            thinkingSummary = thinkingSummary,
                            attachments = attachments
                        )
                    )
                }
                if (thinkingStream.isNotBlank()) {
                    repository.insertThinking(messageId, thinkingStream)
                } else if (isRegeneration) {
                    repository.updateThinkingStream(messageId, "")
                }
            }

            try {
                val sessionId = if (provider.equals("CODEX_AUTH", ignoreCase = true)) {
                    repository.getOrCreateCodexSessionId(conversationId)
                } else {
                    null
                }
                val response = repository.streamGenerateContent(
                    model = model,
                    request = request,
                    providerOverride = provider,
                    sessionId = sessionId
                )
                if (!response.isSuccessful) {
                    val body = if (BuildConfig.DEBUG || BuildConfig.DIAGNOSTIC) {
                        response.errorBody()?.string()?.take(2048)
                    } else {
                        null
                    }
                    DiagnosticsLogger.log(
                        "Streaming API failed provider=${provider.uppercase()} model=$model code=${response.code()} body=${body.orEmpty()}"
                    )
                    if (BuildConfig.DEBUG || BuildConfig.DIAGNOSTIC) {
                        android.util.Log.e(
                            "ChatResponseStreamer",
                            "Streaming API failed: code=${response.code()} body=$body"
                        )
                    } else {
                        android.util.Log.e(
                            "ChatResponseStreamer",
                            "Streaming API failed: code=${response.code()}"
                        )
                    }
                    persistResponse(text = apiFailureMessage(provider, response.code()))
                    return@launch
                }

                val body = response.body()
                if (body == null) {
                    DiagnosticsLogger.log("Streaming API returned empty body provider=${provider.uppercase()} model=$model")
                    persistResponse(text = STREAMING_GENERIC_ERROR)
                    return@launch
                }

                var currentText = ""
                var currentThinking = ""
                var currentSummary = ""
                val currentAttachments = mutableListOf<String>()
                var hasData = false
                var usageRecorded = false
                var parseError: Throwable? = null
                var parseErrorCount = 0
                val nonDataLines = mutableListOf<String>()
                var sawAnyLine = false

                val reader = body.byteStream().bufferedReader(Charsets.UTF_8)   
                try {
                    val eventBuffer = StringBuilder()

                    suspend fun recordUsageOnce(snapshot: TokenUsageSnapshot?, phase: String) {
                        if (usageRecorded) return
                        val usage = snapshot?.normalized() ?: return
                        if (usage.isEmpty()) return
                        runCatching {
                            repository.recordTokenUsage(
                                provider = provider,
                                model = model,
                                usage = usage,
                                conversationId = conversationId,
                                requestType = phase
                            )
                        }.onSuccess {
                            usageRecorded = true
                        }
                    }

                    suspend fun flushEvent() {
                        val payload = eventBuffer.toString().trim()
                        eventBuffer.setLength(0)
                        if (payload.isEmpty() || payload == DONE_TOKEN) {
                            return
                        }

                        try {
                            val parsedChunk = if (
                                provider.uppercase() == "CODEX_AUTH"
                            ) {
                                val delta = parseCodexResponsesDelta(payload, currentText)
                                val usage = parseCodexResponsesUsage(payload)
                                StreamChunkParse(
                                    deltaText = delta.first,
                                    deltaThinking = delta.second,
                                    deltaSummary = delta.third,
                                    usage = usage
                                )
                            } else if (
                                provider.uppercase() == "OPENROUTER" ||
                                provider.uppercase() == "ZAI" ||
                                provider.uppercase() == "OPENAI" ||
                                provider.uppercase() == "MINIMAX" ||
                                provider.uppercase() == "OPENAI_COMPAT"
                            ) {
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
                                val attachmentsAdded = parsed.attachments.isNotEmpty()
                                if (attachmentsAdded) {
                                    currentAttachments.addAll(parsed.attachments)
                                }
                                val textDelta = parsed.text + chunk.text.orEmpty()
                                if (attachmentsAdded && textDelta.isEmpty() && parsed.thinking.isEmpty()) {
                                    hasData = true
                                }
                                StreamChunkParse(
                                    deltaText = textDelta,
                                    deltaThinking = parsed.thinking,
                                    usage = chunk.extractTokenUsageSnapshot()
                                )
                            }
                            val deltaText = parsedChunk.deltaText
                            val deltaThinking = parsedChunk.deltaThinking
                            val deltaSummary = parsedChunk.deltaSummary
                            recordUsageOnce(parsedChunk.usage, "chat_stream")

                            currentThinking += deltaThinking
                            if (deltaSummary.isNotEmpty()) {
                                currentSummary += deltaSummary
                            }
                            if (deltaText.isNotEmpty() || deltaThinking.isNotEmpty() || deltaSummary.isNotEmpty() || currentAttachments.isNotEmpty()) {
                                hasData = true
                                currentText += deltaText
                                val summaryForMessage = if (
                                    provider.uppercase() == "CODEX_AUTH" && currentSummary.isNotBlank()
                                ) {
                                    currentSummary
                                } else {
                                    null
                                }
                                updateFullMessageState(
                                    text = currentText,
                                    attachments = currentAttachments.toList(),
                                    thinkingSummary = summaryForMessage,
                                    thinkingStream = currentThinking
                                )
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
                                    "ChatResponseStreamer",
                                    "Failed to parse streaming chunk: ${payload.take(256)}",
                                    e
                                )
                            } else {
                                android.util.Log.e("ChatResponseStreamer", "Failed to parse streaming chunk", e)
                            }
                        }
                    }

                    while (true) {
                        val rawLine = reader.readLine() ?: break
                        sawAnyLine = true
                        if (rawLine.startsWith(":")) continue
                        if (rawLine.isEmpty()) {
                            if (eventBuffer.isNotEmpty()) flushEvent()
                            continue
                        }
                        if (rawLine.startsWith("data:")) {
                            val payload = rawLine.substringAfter("data:").trimStart()
                            if (eventBuffer.isNotEmpty()) {
                                eventBuffer.append('\n')
                            }
                            eventBuffer.append(payload)
                        } else if (nonDataLines.size < 8) {
                            val trimmed = rawLine.trim()
                            if (trimmed.isNotEmpty()) {
                                nonDataLines.add(trimmed.take(256))
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
                        val safeUrl = runCatching {
                            val url = response.raw().request.url
                            "${url.scheme}://${url.host}${url.encodedPath}"
                        }.getOrNull()
                        DiagnosticsLogger.log(
                            "Streaming had no data provider=${provider.uppercase()} model=$model code=${response.code()} url=${safeUrl.orEmpty()} contentType=${body.contentType()} length=${body.contentLength()} sawAnyLine=$sawAnyLine nonDataLines=${nonDataLines.joinToString(" | ")}"
                        )
                    }
                    DiagnosticsLogger.log(
                        "Streaming produced no usable data; falling back to non-streaming provider=${provider.uppercase()} model=$model"
                    )
                    when (val fallback = requestSingleResponse(conversationId, model, provider, request)) {
                        is NonStreamingResult.Success -> {
                            persistResponse(
                                text = fallback.text,
                                attachments = fallback.attachments,
                                thinkingSummary = fallback.thinking.ifBlank { null },
                                thinkingStream = fallback.thinking
                            )
                        }
                        is NonStreamingResult.Failure -> {
                            persistResponse(text = fallback.message)
                        }
                    }
                    return@launch
                }

                val (cleanText, additionalThinking) = splitReasoningBlocks(currentText)
                val finalThinking = (currentThinking + additionalThinking).trim()
                val isCodex = provider.uppercase() == "CODEX_AUTH"
                val finalSummary = currentSummary.trim()
                val summaryToStore = if (isCodex && finalSummary.isNotEmpty()) {
                    finalSummary
                } else {
                    finalThinking.ifEmpty { null }
                }
                persistResponse(
                    text = cleanText,
                    attachments = currentAttachments.toList(),
                    thinkingSummary = summaryToStore,
                    thinkingStream = finalThinking
                )
            } catch (e: Exception) {
                DiagnosticsLogger.log("Streaming request failed provider=${provider.uppercase()} model=$model", e)
                android.util.Log.e("ChatResponseStreamer", "Streaming request failed", e)
                persistResponse(text = networkFailureMessage(provider, e))
            } finally {
                fetchFullMessage.invoke(messageId)
            }
        }
    }

    /**
     * Executes a non-streaming request and returns the parsed result.
     */
    suspend fun requestSingleResponse(
        conversationId: Long,
        model: String,
        provider: String,
        request: GenerateContentRequest
    ): NonStreamingResult = withContext(Dispatchers.IO) {
        return@withContext try {
            val sessionId = if (provider.equals("CODEX_AUTH", ignoreCase = true)) {
                repository.getOrCreateCodexSessionId(conversationId)
            } else {
                null
            }
            val response = repository.generateContent(
                model = model,
                request = request,
                providerOverride = provider,
                sessionId = sessionId
            )
            if (!response.isSuccessful) {
                val errorBody = if (BuildConfig.DEBUG || BuildConfig.DIAGNOSTIC) {
                    response.errorBody()?.string()?.take(2048)
                } else {
                    null
                }
                DiagnosticsLogger.log(
                    "Generate content failed provider=${provider.uppercase()} model=$model code=${response.code()} body=${errorBody.orEmpty()}"
                )
                if (BuildConfig.DEBUG || BuildConfig.DIAGNOSTIC) {
                    android.util.Log.e(
                        "ChatResponseStreamer",
                        "Generate content failed: code=${response.code()} body=$errorBody"
                    )
                } else {
                    android.util.Log.e("ChatResponseStreamer", "Generate content failed: code=${response.code()}")
                }
                NonStreamingResult.Failure(apiFailureMessage(provider, response.code()))
            } else {
                val body = response.body()
                if (body == null) {
                    DiagnosticsLogger.log("Generate content returned empty body provider=${provider.uppercase()} model=$model")
                    NonStreamingResult.Failure(STREAMING_GENERIC_ERROR)
                } else {
                    var text = ""
                    var thinking = ""
                    val attachments = mutableListOf<String>()
                    body.extractTokenUsageSnapshot()?.let { usage ->
                        runCatching {
                            repository.recordTokenUsage(
                                provider = provider,
                                model = model,
                                usage = usage,
                                conversationId = conversationId,
                                requestType = "chat_non_stream"
                            )
                        }
                    }
                    val parsed = parseGeminiParts(body.candidates?.firstOrNull()?.content?.parts.orEmpty())
                    text += parsed.text + body.text.orEmpty()
                    thinking += parsed.thinking
                    attachments.addAll(parsed.attachments)
                    val (cleanText, extraThinking) = splitReasoningBlocks(text)
                    val combinedThinking = (thinking + extraThinking).trim()
                    NonStreamingResult.Success(cleanText, combinedThinking, attachments)
                }
            }
        } catch (e: Exception) {
            DiagnosticsLogger.log("Generate content request threw exception provider=${provider.uppercase()} model=$model", e)
            android.util.Log.e("ChatResponseStreamer", "Generate content request threw exception", e)
            NonStreamingResult.Failure(networkFailureMessage(provider, e))
        }
    }

    sealed class NonStreamingResult {
        data class Success(val text: String, val thinking: String, val attachments: List<String>) : NonStreamingResult()
        data class Failure(val message: String) : NonStreamingResult()
    }

    companion object {
        private const val DONE_TOKEN = "[DONE]"
        private const val STREAMING_GENERIC_ERROR = "応答の取得に失敗しました。しばらくしてから再試行してください。"
    }

    private fun apiFailureMessage(provider: String, code: Int): String {
        val p = provider.uppercase()
        return when (code) {
            401 -> "APIキーが未設定または無効です（$p）"
            403 -> "アクセスが拒否されました（$p）"
            404 -> "エンドポイント/モデルが見つかりません（$p）"
            408 -> "タイムアウトしました（$p）"
            429 -> "レート制限です。少し待って再試行してください（$p）"
            in 500..599 -> "サーバーエラーが発生しました（$p, code=$code）"
            else -> "APIエラーが発生しました（$p, code=$code）"
        }
    }

    private fun networkFailureMessage(provider: String, throwable: Throwable): String {
        val p = provider.uppercase()
        val kind = throwable::class.java.simpleName
        return "通信に失敗しました（$p, $kind）"
    }

    private data class ParsedParts(
        val text: String,
        val thinking: String,
        val attachments: List<String>
    )

    private suspend fun parseGeminiParts(parts: List<ResponsePart>): ParsedParts {
        val textBuilder = StringBuilder()
        val thinkingBuilder = StringBuilder()
        val attachments = mutableListOf<String>()

        for (part in parts) {
            if (part.thought == true) {
                thinkingBuilder.append(part.text.orEmpty())
            } else {
                part.text?.let { textBuilder.append(it) }
            }

            part.functionCall?.let { textBuilder.append(formatFunctionCall(it)) }
            part.functionResponse?.let { response ->
                textBuilder.append(formatFunctionResponse(response))
                response.parts?.forEach { respPart ->
                    respPart.inlineData?.let { inline ->
                        repository.saveInlineData(inline, respPart.fileData?.displayName)?.let { attachments.add(it) }
                    }
                    respPart.fileData?.let { file ->
                        textBuilder.append(formatFileDataPlaceholder(file.displayName, file.fileUri))
                    }
                }
            }

            part.inlineData?.let { inline ->
                repository.saveInlineData(inline, part.fileData?.displayName)?.let { attachments.add(it) }
            }
            if (part.fileData != null && part.inlineData == null) {
                textBuilder.append(formatFileDataPlaceholder(part.fileData.displayName, part.fileData.fileUri))
            }
        }

        return ParsedParts(
            text = textBuilder.toString(),
            thinking = thinkingBuilder.toString(),
            attachments = attachments
        )
    }

    private fun formatFunctionCall(functionCall: FunctionCall): String {
        val args = functionCall.args?.toString() ?: ""
        return "\n[Function call] ${functionCall.name}${if (args.isNotBlank()) " $args" else ""}"
    }

    private fun formatFunctionResponse(functionResponse: FunctionResponse): String {
        val response = functionResponse.response?.toString() ?: ""
        return if (response.isBlank()) {
            "\n[Function response] ${functionResponse.name}"
        } else {
            "\n[Function response] ${functionResponse.name}: $response"
        }
    }

    private fun formatFileDataPlaceholder(displayName: String?, fileUri: String?): String {
        val label = displayName ?: fileUri ?: "file"
        return "\n[File] $label"
    }

    private fun incrementalDelta(buffer: String, incoming: String): String {
        if (incoming.isEmpty()) return ""
        if (incoming == buffer) return ""
        if (incoming.length > buffer.length && incoming.startsWith(buffer)) {
            return incoming.substring(buffer.length)
        }
        return incoming
    }

    private fun parseCodexResponsesDelta(payload: String, currentText: String): Triple<String, String, String> {
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

    private fun parseCodexResponsesUsage(payload: String): TokenUsageSnapshot? {
        val element = runCatching { json.parseToJsonElement(payload) }.getOrNull() ?: return null
        val obj = element.jsonObject
        if (obj["type"]?.jsonPrimitive?.contentOrNull != "response.completed") return null
        val usageObj = runCatching {
            obj["response"]?.jsonObject?.get("usage")?.jsonObject
        }.getOrNull() ?: return null
        val inputTokens = usageObj["input_tokens"]?.jsonPrimitive?.contentOrNull?.toIntOrNull() ?: 0
        val outputTokens = usageObj["output_tokens"]?.jsonPrimitive?.contentOrNull?.toIntOrNull() ?: 0
        val totalTokens = usageObj["total_tokens"]?.jsonPrimitive?.contentOrNull?.toIntOrNull() ?: (inputTokens + outputTokens)
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

    private data class StreamChunkParse(
        val deltaText: String,
        val deltaThinking: String,
        val deltaSummary: String = "",
        val usage: TokenUsageSnapshot? = null
    )
}
