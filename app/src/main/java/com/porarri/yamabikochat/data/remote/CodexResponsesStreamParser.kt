package com.porarri.yamabikochat.data.remote

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/** One parser shared by every UI/repository consumer of Responses API SSE. */
object CodexResponsesStreamParser {
    fun delta(json: Json, payload: String, currentText: String): Triple<String, String, String> {
        val obj = runCatching { json.parseToJsonElement(payload).jsonObject }.getOrNull()
            ?: return Triple("", "", "")
        val type = obj["type"]?.jsonPrimitive?.contentOrNull ?: return Triple("", "", "")
        val delta = obj["delta"]?.jsonPrimitive?.contentOrNull.orEmpty()
        return when (type) {
            "response.output_text.delta" -> Triple(incrementalDelta(currentText, delta), "", "")
            "response.reasoning_text.delta" -> Triple("", delta, "")
            "response.reasoning_summary_text.delta" -> Triple("", "", delta)
            "response.output_item.done" -> Triple(
                incrementalDelta(currentText, outputText(obj["item"]?.jsonObject)),
                "",
                ""
            )
            else -> Triple("", "", "")
        }
    }

    fun usage(json: Json, payload: String): TokenUsageSnapshot? {
        val obj = runCatching { json.parseToJsonElement(payload).jsonObject }.getOrNull() ?: return null
        if (obj["type"]?.jsonPrimitive?.contentOrNull != "response.completed") return null
        val usage = runCatching { obj["response"]?.jsonObject?.get("usage")?.jsonObject }.getOrNull()
            ?: return null
        val inclusiveInput = usage["input_tokens"]?.jsonPrimitive?.contentOrNull?.toIntOrNull()
            ?.coerceAtLeast(0) ?: 0
        val output = usage["output_tokens"]?.jsonPrimitive?.contentOrNull?.toIntOrNull()
            ?.coerceAtLeast(0) ?: 0
        val cached = runCatching {
            usage["input_tokens_details"]?.jsonObject
                ?.get("cached_tokens")?.jsonPrimitive?.contentOrNull?.toIntOrNull()
        }.getOrNull()?.coerceIn(0, inclusiveInput) ?: 0
        val reasoning = runCatching {
            usage["output_tokens_details"]?.jsonObject
                ?.get("reasoning_tokens")?.jsonPrimitive?.contentOrNull?.toIntOrNull()
        }.getOrNull()
        return TokenUsageSnapshot(
            inputTokens = inclusiveInput - cached,
            outputTokens = output,
            totalTokens = inclusiveInput + output,
            reasoningTokens = reasoning,
            cachedInputTokens = cached.takeIf { it > 0 }
        ).normalized().takeUnless { it.isEmpty() }
    }

    private fun incrementalDelta(buffer: String, incoming: String): String {
        if (incoming.isEmpty() || incoming == buffer) return ""
        return if (incoming.length > buffer.length && incoming.startsWith(buffer)) {
            incoming.substring(buffer.length)
        } else {
            incoming
        }
    }

    private fun outputText(item: JsonObject?): String {
        if (item?.get("type")?.jsonPrimitive?.contentOrNull != "message") return ""
        if (item["role"]?.jsonPrimitive?.contentOrNull != "assistant") return ""
        return item["content"]?.jsonArray.orEmpty().joinToString("") { block ->
            val objectValue = block.jsonObject
            if (objectValue["type"]?.jsonPrimitive?.contentOrNull == "output_text") {
                objectValue["text"]?.jsonPrimitive?.contentOrNull.orEmpty()
            } else {
                ""
            }
        }
    }
}
