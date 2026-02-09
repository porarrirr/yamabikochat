package com.porarri.yamabikochat.data.remote

import com.porarri.yamabikochat.TestLogUtils
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
        val reasoning = (converted as OpenRouterRequest).reasoning

        assertNotNull(reasoning)
        reasoning!!
        assertEquals(2048, reasoning.max_tokens)
        assertEquals(true, reasoning.exclude)
        assertEquals(true, reasoning.enabled)
        assertNull(reasoning.effort)
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
        val reasoning = (converted as OpenRouterRequest).reasoning

        assertNotNull(reasoning)
        reasoning!!
        assertEquals("medium", reasoning.effort)
        assertNull(reasoning.max_tokens)
        assertNull(reasoning.exclude)
        assertNull(reasoning.enabled)
    }
}
