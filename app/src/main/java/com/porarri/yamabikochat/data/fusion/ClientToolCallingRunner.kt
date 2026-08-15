package com.porarri.yamabikochat.data.fusion

import com.porarri.yamabikochat.data.remote.Content
import com.porarri.yamabikochat.data.remote.FunctionCall
import com.porarri.yamabikochat.data.remote.FunctionResponse
import com.porarri.yamabikochat.data.remote.GenerateContentRequest
import com.porarri.yamabikochat.data.remote.GenerateContentResponse
import com.porarri.yamabikochat.data.remote.Part
import com.porarri.yamabikochat.data.remote.extractTokenUsageSnapshot
import com.porarri.yamabikochat.data.tools.ClientTools
import com.porarri.yamabikochat.data.tools.ToolCall
import com.porarri.yamabikochat.data.tools.ToolCallingOrchestrator
import com.porarri.yamabikochat.data.tools.ToolTurnMessage
import com.porarri.yamabikochat.data.tools.ToolTurnRequest
import com.porarri.yamabikochat.data.tools.ToolTurnResponse
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

/**
 * Runs client-side tool calling loops for Fusion panel phase.
 */
fun interface ClientToolCallingRunner {
    suspend fun run(
        model: String,
        provider: String,
        request: GenerateContentRequest
    ): FusionInvokeResult
}

class DefaultClientToolCallingRunner(
    private val generate: FusionGenerate,
    private val registry: com.porarri.yamabikochat.data.tools.LocalToolRegistry = ClientTools.defaultRegistry()
) : ClientToolCallingRunner {
    private val json = Json { ignoreUnknownKeys = true; isLenient = true }
    private val orchestrator = ToolCallingOrchestrator(registry)

    override suspend fun run(
        model: String,
        provider: String,
        request: GenerateContentRequest
    ): FusionInvokeResult {
        val initialMessages = request.contents.map { content ->
            ToolTurnMessage(
                role = content.role ?: "user",
                content = content.parts.mapNotNull { it.text }.joinToString("\n")
            )
        }.toMutableList()

        val outcome = orchestrator.run(
            request = ToolTurnRequest(messages = initialMessages),
            invoke = { turnRequest, _ ->
                val roundRequest = request.copy(contents = turnRequest.messages.toContents())
                val response = generate(model, provider, roundRequest)
                response.toToolTurnResponse()
            }
        )

        return FusionInvokeResult(
            text = outcome.response.text,
            inputTokens = outcome.response.usage?.inputTokens,
            outputTokens = outcome.response.usage?.outputTokens,
            toolCalls = outcome.response.toolCalls.takeIf { it.isNotEmpty() }
        )
    }

    private fun List<ToolTurnMessage>.toContents(): List<Content> =
        map { message ->
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
                                    args = runCatching {
                                        json.parseToJsonElement(call.argumentsJSON)
                                    }.getOrNull(),
                                    id = call.id
                                )
                            )
                        )
                    }
                    Content(role = "model", parts = parts.ifEmpty { listOf(Part(text = "")) })
                }
                "tool" -> Content(
                    role = "user",
                    parts = listOf(
                        Part(
                            functionResponse = FunctionResponse(
                                name = message.toolName.orEmpty(),
                                response = buildJsonObject {
                                    put("result", JsonPrimitive(message.content))
                                },
                                id = message.toolCallId
                            )
                        )
                    )
                )
                else -> Content(
                    role = "user",
                    parts = listOf(Part(text = message.content))
                )
            }
        }

    private fun GenerateContentResponse.toToolTurnResponse(): ToolTurnResponse {
        val parts = candidates?.firstOrNull()?.content?.parts.orEmpty()
        val bodyText = text.orEmpty()
        val assembled = buildString {
            parts.forEach { part ->
                if (part.thought != true && !part.text.isNullOrEmpty()) {
                    append(part.text)
                }
            }
            if (isEmpty()) append(bodyText)
        }
        val toolCalls = parts.mapIndexedNotNull { index, part ->
            val call = part.functionCall ?: return@mapIndexedNotNull null
            ToolCall(
                id = "tool-call-$index",
                name = call.name,
                argumentsJSON = call.args?.toString() ?: "{}"
            )
        }
        return ToolTurnResponse(
            text = assembled,
            toolCalls = toolCalls,
            usage = extractTokenUsageSnapshot()
        )
    }
}

typealias FusionGenerate = suspend (
    model: String,
    provider: String,
    request: GenerateContentRequest
) -> GenerateContentResponse

typealias FusionStream = suspend (
    model: String,
    provider: String,
    request: GenerateContentRequest
) -> String

typealias FusionCostEstimator = suspend (
    provider: String,
    model: String,
    inputTokens: Int,
    outputTokens: Int
) -> Double?

fun GenerateContentResponse.toFusionInvokeResult(): FusionInvokeResult {
    val parts = candidates?.firstOrNull()?.content?.parts.orEmpty()
    val bodyText = text.orEmpty()
    val assembled = buildString {
        parts.forEach { part ->
            if (part.thought != true && !part.text.isNullOrEmpty()) {
                append(part.text)
            }
        }
        if (isEmpty()) append(bodyText)
    }
    val usage = extractTokenUsageSnapshot()
    val toolCalls = parts.mapIndexedNotNull { index, part ->
        val call = part.functionCall ?: return@mapIndexedNotNull null
        ToolCall(
            id = "tool-call-$index",
            name = call.name,
            argumentsJSON = call.args?.toString() ?: "{}"
        )
    }
    return FusionInvokeResult(
        text = assembled,
        inputTokens = usage?.inputTokens,
        outputTokens = usage?.outputTokens,
        toolCalls = toolCalls.takeIf { it.isNotEmpty() }
    )
}
