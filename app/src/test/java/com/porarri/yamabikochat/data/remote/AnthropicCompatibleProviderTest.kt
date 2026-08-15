package com.porarri.yamabikochat.data.remote

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Test

class AnthropicCompatibleProviderTest {
    private val provider = AnthropicCompatibleProvider { error("service is not used") }

    @Test
    fun mapsCompleteToolTranscriptWithoutFlatteningItToText() {
        val contents = listOf(
            Content(role = "user", parts = listOf(Part(text = "search"))),
            Content(
                role = "model",
                parts = listOf(
                    Part(text = "reasoning", thought = true),
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
                            response = Json.parseToJsonElement("""{"results":[1,2,3]}"""),
                            id = "call-1"
                        )
                    )
                )
            )
        )

        val mapped = provider.mapMessages(contents)

        assertEquals(listOf("user", "assistant", "user"), mapped.map { it.role })
        assertEquals("reasoning", mapped[1].content[0].text)
        assertEquals("tool_use", mapped[1].content[1].type)
        assertEquals("call-1", mapped[1].content[1].id)
        assertEquals("web_search", mapped[1].content[1].name)
        assertEquals("large", mapped[1].content[1].input?.jsonObject?.get("query")?.jsonPrimitive?.content)
        assertEquals("tool_result", mapped[2].content.single().type)
        assertEquals("call-1", mapped[2].content.single().toolUseId)
        assertEquals("""{"results":[1,2,3]}""", mapped[2].content.single().content)
    }

    @Test
    fun mapsClientFunctionDeclarationsToAnthropicTools() {
        val tools = provider.buildFunctionTools(
            listOf(
                Tool(
                    function_declarations = listOf(
                        FunctionDeclaration(
                            name = "web_search",
                            description = "Search",
                            parameters = buildJsonObject {
                                put("type", JsonPrimitive("object"))
                            }
                        )
                    )
                )
            )
        )

        val tool = tools.single().jsonObject
        assertEquals("web_search", tool["name"]?.jsonPrimitive?.content)
        assertEquals("Search", tool["description"]?.jsonPrimitive?.content)
        assertNotNull(tool["input_schema"])
    }

    @Test
    fun cacheUsageCountsOnlyProviderReportedCacheReads() {
        val usage = AnthropicUsage(
            inputTokens = 100,
            outputTokens = 10,
            cacheReadInputTokens = 80,
            cacheCreationInputTokens = 20
        ).toTokenUsageSnapshot()

        assertEquals(80, usage.cachedInputTokens)
    }
}
