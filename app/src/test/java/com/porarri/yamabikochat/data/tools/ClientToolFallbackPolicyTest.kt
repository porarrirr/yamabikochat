package com.porarri.yamabikochat.data.tools

import com.porarri.yamabikochat.data.remote.FunctionDeclaration
import com.porarri.yamabikochat.data.remote.Tool
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ClientToolFallbackPolicyTest {

    private val clientTools = listOf(
        Tool(
            function_declarations = listOf(
                FunctionDeclaration(name = "web_search", description = "search"),
                FunctionDeclaration(name = "fetch_url", description = "fetch")
            )
        )
    )

    @Test
    fun retriesOnRoundOneWhenToolsUnsupported() {
        assertTrue(
            ClientToolFallbackPolicy.shouldRetryWithoutClientTools(
                httpStatus = 400,
                body = """{"error":"tools field is unsupported"}""",
                tools = clientTools,
                round = 1
            )
        )
    }

    @Test
    fun doesNotRetryAfterRoundOne() {
        assertFalse(
            ClientToolFallbackPolicy.shouldRetryWithoutClientTools(
                httpStatus = 400,
                body = """{"error":"tools field is unsupported"}""",
                tools = clientTools,
                round = 2
            )
        )
    }

    @Test
    fun doesNotRetryWithoutClientToolsPresent() {
        assertFalse(
            ClientToolFallbackPolicy.shouldRetryWithoutClientTools(
                httpStatus = 400,
                body = """{"error":"tools field is unsupported"}""",
                tools = listOf(Tool(google_search = com.porarri.yamabikochat.data.remote.GoogleSearch())),
                round = 1
            )
        )
    }

    @Test
    fun removingClientToolsKeepsOtherDeclarations() {
        val tools = listOf(
            Tool(
                function_declarations = listOf(
                    FunctionDeclaration(name = "web_search", description = "search"),
                    FunctionDeclaration(name = "custom_tool", description = "custom")
                )
            )
        )
        val stripped = ClientToolFallbackPolicy.removingClientTools(tools)
        assertTrue(stripped.single().function_declarations.orEmpty().any { it.name == "custom_tool" })
        assertFalse(stripped.single().function_declarations.orEmpty().any { it.name == "web_search" })
    }
}
