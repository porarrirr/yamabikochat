package com.porarri.yamabikochat.data.remote

import kotlinx.serialization.json.Json
import org.junit.Assert.assertEquals
import org.junit.Test

class CodexResponsesStreamParserTest {
    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun responseCompletedUsesDisjointCacheBuckets() {
        val payload = """
            {
              "type":"response.completed",
              "response":{"usage":{
                "input_tokens":1000,
                "output_tokens":50,
                "total_tokens":1050,
                "input_tokens_details":{"cached_tokens":800},
                "output_tokens_details":{"reasoning_tokens":20}
              }}
            }
        """.trimIndent()

        val usage = requireNotNull(CodexResponsesStreamParser.usage(json, payload))
        assertEquals(200, usage.inputTokens)
        assertEquals(800, usage.cachedInputTokens)
        assertEquals(50, usage.outputTokens)
        assertEquals(1050, usage.totalTokens)
        assertEquals(20, usage.reasoningTokens)
    }

    @Test
    fun cumulativeOutputItemOnlyEmitsUnseenSuffix() {
        val payload = """
            {"type":"response.output_item.done","item":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"hello world"}]}}
        """.trimIndent()

        assertEquals(
            Triple(" world", "", ""),
            CodexResponsesStreamParser.delta(json, payload, "hello")
        )
    }
}
