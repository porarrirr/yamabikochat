package com.porarri.yamabikochat.data.remote

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class ModelsDevReasoningWireTest {
    private val json = Json { encodeDefaults = false }

    @Test
    fun openAiCompatibleEffortUsesTopLevelReasoningEffort() {
        val payload = OpenRouterRequest(
            model = "reasoner",
            messages = listOf(OpenRouterMessage(role = "user", content = "hello")),
            reasoningEffort = "high"
        )

        val root = json.parseToJsonElement(json.encodeToString(payload)).jsonObject

        assertEquals("high", root["reasoning_effort"]?.jsonPrimitive?.content)
        assertFalse(root.containsKey("reasoning"))
    }

    @Test
    fun anthropicEffortUsesOutputConfig() {
        val payload = AnthropicMessageRequest(
            model = "claude-reasoner",
            messages = listOf(
                AnthropicMessage(
                    role = "user",
                    content = listOf(AnthropicContentBlock(type = "text", text = "hello"))
                )
            ),
            maxTokens = 4096,
            outputConfig = AnthropicOutputConfig(effort = "medium")
        )

        val root = json.parseToJsonElement(json.encodeToString(payload)).jsonObject
        val outputConfig = root["output_config"]?.jsonObject

        assertEquals("medium", outputConfig?.get("effort")?.jsonPrimitive?.content)
    }
}
