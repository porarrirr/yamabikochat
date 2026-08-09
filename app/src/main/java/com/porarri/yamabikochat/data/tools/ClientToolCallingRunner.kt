package com.porarri.yamabikochat.data.tools

import com.porarri.yamabikochat.data.remote.Content
import com.porarri.yamabikochat.data.remote.FunctionCall
import com.porarri.yamabikochat.data.remote.FunctionResponse
import com.porarri.yamabikochat.data.remote.GenerateContentRequest
import com.porarri.yamabikochat.data.remote.GenerateContentResponse
import com.porarri.yamabikochat.data.remote.Part
import com.porarri.yamabikochat.data.remote.TokenUsageSnapshot
import com.porarri.yamabikochat.data.remote.extractTokenUsageSnapshot
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonPrimitive
import retrofit2.Response

class ClientToolCallingRunner(
    private val generate: suspend (GenerateContentRequest, String /*model*/, String /*provider*/) -> Response<GenerateContentResponse>,
    private val registry: LocalToolRegistry = ClientTools.defaultRegistry(),
    private val json: Json = Json { ignoreUnknownKeys = true; isLenient = true },
    private val maxRounds: Int = ToolCallingOrchestrator.DEFAULT_MAX_ROUNDS
) {
    data class Result(
        val text: String,
        val thinking: String,
        val activities: List<ToolActivityStep>,
        val usage: TokenUsageSnapshot?
    )

    suspend fun run(
        baseRequest: GenerateContentRequest,
        model: String,
        provider: String,
        onActivitiesChanged: (suspend (List<ToolActivityStep>) -> Unit)? = null
    ): Result {
        val orchestrator = ToolCallingOrchestrator(registry = registry, maxRounds = maxRounds)
        var workingTools = baseRequest.tools

        val initial = ToolTurnRequest(messages = contentsToToolMessages(baseRequest.contents))
        val outcome = orchestrator.run(
            request = initial,
            invoke = { turnRequest, round ->
                var request = baseRequest.copy(
                    contents = toolMessagesToContents(turnRequest.messages),
                    tools = workingTools
                )
                var response = generate(request, model, provider)
                if (!response.isSuccessful) {
                    val errorBody = response.errorBody()?.string().orEmpty()
                    if (baseRequest.skillContext == null && ClientToolFallbackPolicy.shouldRetryWithoutClientTools(
                            httpStatus = response.code(),
                            body = errorBody,
                            tools = request.tools.orEmpty(),
                            round = round
                        )
                    ) {
                        DiagnosticsLogger.log(
                            "Model rejected client tools; retrying without local functions " +
                                "provider=${provider.uppercase()} model=$model code=${response.code()}"
                        )
                        workingTools = ClientToolFallbackPolicy
                            .removingClientTools(request.tools.orEmpty())
                            .takeIf { it.isNotEmpty() }
                        request = request.copy(tools = workingTools)
                        response = generate(request, model, provider)
                    } else {
                        throw ClientToolCallingException(
                            apiFailureMessage(provider, response.code(), errorBody)
                        )
                    }
                }
                if (!response.isSuccessful) {
                    val errorBody = response.errorBody()?.string().orEmpty()
                    throw ClientToolCallingException(
                        apiFailureMessage(provider, response.code(), errorBody)
                    )
                }
                val body = response.body()
                    ?: throw ClientToolCallingException("Empty response body from ${provider.uppercase()}")
                parseGenerateContentResponse(body)
            },
            onActivitiesChanged = onActivitiesChanged
        )

        return Result(
            text = outcome.response.text,
            thinking = outcome.response.reasoningSummary.orEmpty(),
            activities = outcome.activities,
            usage = outcome.response.usage
        )
    }

    private fun parseGenerateContentResponse(body: GenerateContentResponse): ToolTurnResponse {
        val parts = body.candidates?.firstOrNull()?.content?.parts.orEmpty()
        val textBuilder = StringBuilder()
        val thinkingBuilder = StringBuilder()

        for (part in parts) {
            if (part.thought == true) {
                thinkingBuilder.append(part.text.orEmpty())
            } else {
                part.text?.let { textBuilder.append(it) }
            }
        }

        val toolCalls = parts.mapNotNull { it.functionCall }.mapIndexed { index, call ->
            ToolCall(
                id = "call-$index-${call.name}",
                name = call.name,
                argumentsJSON = call.args?.toString() ?: "{}"
            )
        }

        if (textBuilder.isEmpty()) {
            body.text?.let { textBuilder.append(it) }
        }

        return ToolTurnResponse(
            text = textBuilder.toString(),
            reasoningSummary = thinkingBuilder.toString().takeIf { it.isNotBlank() },
            toolCalls = toolCalls,
            usage = body.extractTokenUsageSnapshot()
        )
    }

    private fun contentsToToolMessages(contents: List<Content>): MutableList<ToolTurnMessage> {
        val messages = mutableListOf<ToolTurnMessage>()
        for (content in contents) {
            val role = content.role ?: "user"
            val text = content.parts.mapNotNull { it.text }.joinToString("\n")
            val functionCalls = content.parts.mapNotNull { it.functionCall }
            val functionResponses = content.parts.mapNotNull { it.functionResponse }

            when {
                functionResponses.isNotEmpty() -> {
                    for (response in functionResponses) {
                        messages.add(
                            ToolTurnMessage(
                                role = "tool",
                                content = response.response?.toString() ?: "{}",
                                toolCallId = response.id,
                                toolName = response.name
                            )
                        )
                    }
                }
                role.equals("model", ignoreCase = true) ||
                    role.equals("assistant", ignoreCase = true) ||
                    functionCalls.isNotEmpty() -> {
                    val toolCalls = functionCalls.mapIndexed { index, call ->
                        ToolCall(
                            id = "call-$index-${call.name}",
                            name = call.name,
                            argumentsJSON = call.args?.toString() ?: "{}"
                        )
                    }.takeIf { it.isNotEmpty() }
                    messages.add(
                        ToolTurnMessage(
                            role = "assistant",
                            content = text,
                            toolCalls = toolCalls
                        )
                    )
                }
                else -> {
                    messages.add(ToolTurnMessage(role = "user", content = text))
                }
            }
        }
        return messages
    }

    private fun toolMessagesToContents(messages: List<ToolTurnMessage>): List<Content> {
        return messages.map { message ->
            when (message.role) {
                "assistant" -> {
                    val parts = mutableListOf<Part>()
                    if (message.content.isNotBlank()) {
                        parts.add(Part(text = message.content))
                    }
                    message.toolCalls.orEmpty().forEach { call ->
                        parts.add(
                            Part(
                                functionCall = FunctionCall(
                                    name = call.name,
                                    args = parseJsonElementOrNull(call.argumentsJSON)
                                )
                            )
                        )
                    }
                    if (parts.isEmpty()) {
                        parts.add(Part(text = ""))
                    }
                    Content(role = "model", parts = parts)
                }
                "tool" -> {
                    Content(
                        role = "user",
                        parts = listOf(
                            Part(
                                functionResponse = FunctionResponse(
                                    name = message.toolName.orEmpty(),
                                    response = parseJsonElement(message.content),
                                    id = message.toolCallId
                                )
                            )
                        )
                    )
                }
                else -> Content(
                    role = "user",
                    parts = listOf(Part(text = message.content))
                )
            }
        }
    }

    private fun parseJsonElement(raw: String): JsonElement {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return JsonPrimitive("{}")
        return runCatching { json.parseToJsonElement(trimmed) }.getOrElse { JsonPrimitive(trimmed) }
    }

    private fun parseJsonElementOrNull(raw: String): JsonElement? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null
        return runCatching { json.parseToJsonElement(trimmed) }.getOrNull()
    }

    private fun apiFailureMessage(provider: String, code: Int, body: String): String {
        val p = provider.uppercase()
        val detail = body.take(200).takeIf { it.isNotBlank() }
        return when (code) {
            401 -> "APIキーが未設定または無効です（$p）"
            403 -> "アクセスが拒否されました（$p）"
            404 -> "エンドポイント/モデルが見つかりません（$p）"
            408 -> "タイムアウトしました（$p）"
            429 -> "レート制限です。少し待って再試行してください（$p）"
            in 500..599 -> "サーバーエラーが発生しました（$p, code=$code）"
            else -> if (detail != null) {
                "APIエラーが発生しました（$p, code=$code）: $detail"
            } else {
                "APIエラーが発生しました（$p, code=$code）"
            }
        }
    }

    class ClientToolCallingException(message: String) : Exception(message)
}
