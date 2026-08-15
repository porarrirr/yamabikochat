package com.porarri.yamabikochat.data.remote

import com.porarri.yamabikochat.TestLogUtils
import kotlinx.serialization.json.Json
import kotlinx.serialization.encodeToString
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
class RequestConverterTest {

    @Before
    fun setUp() {
        TestLogUtils.setup()
    }

    @After
    fun tearDown() {
        TestLogUtils.tearDown()
    }

    @Test
    fun geminiToOpenRouter_mapsReasoningBudget() {
        val request = GenerateContentRequest(
            contents = listOf(Content(role = "user", parts = listOf(Part(text = "hello")))),
            generationConfig = GenerationConfig(
                thinkingConfig = ThinkingConfig(
                    thinkingBudget = 2048,
                    includeThoughts = false,
                    enabled = true
                )
            )
        )

        val converted = RequestConverter.geminiToOpenRouter(request, "anthropic/claude-3.7-sonnet")
        assertTrue(converted is OpenRouterRequest)
        val openRouterRequest = converted as OpenRouterRequest
        val reasoning = openRouterRequest.reasoning

        assertNotNull(reasoning)
        reasoning!!
        assertEquals(2048, reasoning.max_tokens)
        assertEquals(true, reasoning.exclude)
        assertEquals(true, reasoning.enabled)
        assertNull(reasoning.effort)
        assertEquals("ephemeral", openRouterRequest.cacheControl?.type)
    }

    @Test
    fun geminiToOpenRouter_mapsEffortOnly() {
        val request = GenerateContentRequest(
            contents = listOf(Content(role = "user", parts = listOf(Part(text = "plan")))),
            generationConfig = GenerationConfig(
                thinkingConfig = ThinkingConfig(
                    thinkingBudget = null,
                    includeThoughts = true,
                    effort = "medium"
                )
            )
        )

        val converted = RequestConverter.geminiToOpenRouter(request, "openai/gpt-5a")
        assertTrue(converted is OpenRouterRequest)
        val openRouterRequest = converted as OpenRouterRequest
        val reasoning = openRouterRequest.reasoning

        assertNotNull(reasoning)
        reasoning!!
        assertEquals("medium", reasoning.effort)
        assertNull(reasoning.max_tokens)
        assertNull(reasoning.exclude)
        assertNull(reasoning.enabled)
        assertNull(openRouterRequest.cacheControl)
    }

    @Test
    fun geminiToOpenRouter_enablesPromptCacheControlForClaudeMultimodalRequests() {
        val request = GenerateContentRequest(
            contents = listOf(
                Content(
                    role = "user",
                    parts = listOf(
                        Part(text = "describe"),
                        Part(inlineData = InlineData(mimeType = "image/png", data = "AAAA"))
                    )
                )
            )
        )

        val converted = RequestConverter.geminiToOpenRouter(request, "claude-sonnet-4.6")
        assertTrue(converted is OpenRouterMultiModalRequest)
        assertEquals("ephemeral", (converted as OpenRouterMultiModalRequest).cacheControl?.type)
    }

    @Test
    fun geminiToOpenRouter_preservesReplayToolCallIdResultAndReasoning() {
        val request = GenerateContentRequest(
            contents = listOf(
                Content(
                    role = "model",
                    parts = listOf(
                        Part(text = "kept reasoning", thought = true),
                        Part(
                            functionCall = FunctionCall(
                                name = "web_search",
                                args = Json.parseToJsonElement("""{"query":"large"}"""),
                                id = "call-1"
                            )
                        )
                    )
                ),
                Content(
                    role = "user",
                    parts = listOf(
                        Part(
                            functionResponse = FunctionResponse(
                                name = "web_search",
                                response = Json.parseToJsonElement("""{"results":[1]}"""),
                                id = "call-1"
                            )
                        )
                    )
                )
            )
        )

        val converted = RequestConverter.geminiToOpenRouter(request, "openai/gpt-5a")
            as OpenRouterRequest

        assertEquals("call-1", converted.messages[0].tool_calls?.single()?.id)
        assertEquals("kept reasoning", converted.messages[0].reasoningContent)
        assertEquals("call-1", converted.messages[1].toolCallId)
        assertEquals("tool", converted.messages[1].role)
    }

    @Test
    fun secondRequestKeepsPreviousWireMessagesAsExactSerializedPrefix() {
        val prefix = listOf(
            Content(role = "user", parts = listOf(Part(text = "search"))),
            Content(
                role = "model",
                parts = listOf(
                    Part(text = "need current data", thought = true),
                    Part(functionCall = FunctionCall(
                        name = "web_search",
                        args = Json.parseToJsonElement("""{"query":"news"}"""),
                        id = "call-1"
                    ))
                )
            ),
            Content(
                role = "user",
                parts = listOf(Part(functionResponse = FunctionResponse(
                    name = "web_search",
                    response = Json.parseToJsonElement("""{"raw":"large result"}"""),
                    id = "call-1"
                )))
            )
        )
        val first = RequestConverter.geminiToOpenRouter(
            GenerateContentRequest(contents = prefix, promptCacheKey = "conversation-42"),
            "deepseek-v4-flash"
        ) as OpenRouterRequest
        val second = RequestConverter.geminiToOpenRouter(
            GenerateContentRequest(
                contents = prefix + listOf(
                    Content(role = "model", parts = listOf(
                        Part(text = "final reasoning", thought = true),
                        Part(text = "summary")
                    )),
                    Content(role = "user", parts = listOf(Part(text = "ありがとう")))
                ),
                promptCacheKey = "conversation-42"
            ),
            "deepseek-v4-flash"
        ) as OpenRouterRequest

        val json = Json { encodeDefaults = false }
        val firstWire = first.messages.map { json.encodeToString(it) }
        val secondPrefixWire = second.messages.take(first.messages.size).map { json.encodeToString(it) }
        assertEquals(firstWire, secondPrefixWire)
        assertEquals(first.promptCacheKey, second.promptCacheKey)
    }

    @Test
    fun geminiToOpenRouter_preservesToolTranscriptWhenHistoryContainsAnImage() {
        val request = GenerateContentRequest(
            contents = listOf(
                Content(
                    role = "user",
                    parts = listOf(
                        Part(text = "image"),
                        Part(inlineData = InlineData("image/png", "AAAA"))
                    )
                ),
                Content(
                    role = "model",
                    parts = listOf(
                        Part(
                            functionCall = FunctionCall(
                                name = "web_search",
                                args = Json.parseToJsonElement("""{"query":"large"}"""),
                                id = "call-image-1"
                            )
                        )
                    )
                ),
                Content(
                    role = "user",
                    parts = listOf(
                        Part(
                            functionResponse = FunctionResponse(
                                name = "web_search",
                                response = Json.parseToJsonElement("""{"raw":"large result"}"""),
                                id = "call-image-1"
                            )
                        )
                    )
                )
            )
        )

        val converted = RequestConverter.geminiToOpenRouter(request, "openai/gpt-5a")
            as OpenRouterMultiModalRequest

        assertEquals("call-image-1", converted.messages[1].tool_calls?.single()?.id)
        assertEquals("tool", converted.messages[2].role)
        assertEquals("call-image-1", converted.messages[2].toolCallId)
        assertEquals(
            "{\"raw\":\"large result\"}",
            (converted.messages[2].content?.single() as OpenRouterContentPart.TextPart).text
        )
    }

    @Test
    fun geminiToResponses_prefersRequestPromptCacheKeyOverSessionFallback() {
        val request = GenerateContentRequest(
            contents = listOf(Content(role = "user", parts = listOf(Part(text = "hello")))),
            codexConfig = CodexRequestConfig(promptCacheEnabled = true),
            promptCacheKey = " conversation-42 "
        )

        val converted = RequestConverter.geminiToResponses(
            geminiRequest = request,
            model = "openai/gpt-5-codex",
            stream = false,
            promptCacheKey = "session-123"
        )

        assertEquals("conversation-42", converted.promptCacheKey)
    }

    @Test
    fun geminiToResponses_omitsPromptCacheKeyWhenCodexPromptCacheDisabled() {
        val request = GenerateContentRequest(
            contents = listOf(Content(role = "user", parts = listOf(Part(text = "hello")))),
            codexConfig = CodexRequestConfig(promptCacheEnabled = false),
            promptCacheKey = "conversation-42"
        )

        val converted = RequestConverter.geminiToResponses(
            geminiRequest = request,
            model = "gpt-5-codex",
            stream = false,
            promptCacheKey = "session-123"
        )

        assertNull(converted.promptCacheKey)
    }
}
