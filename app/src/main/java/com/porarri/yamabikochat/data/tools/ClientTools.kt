package com.porarri.yamabikochat.data.tools

import com.porarri.yamabikochat.data.remote.FunctionDeclaration
import com.porarri.yamabikochat.data.tools.search.FetchUrlTool
import com.porarri.yamabikochat.data.tools.search.WebSearchTool
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement

object ClientTools {
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    fun supportsClientWebSearchTool(provider: String): Boolean {
        return when (provider.trim().uppercase()) {
            "OPENROUTER",
            "OPENAI",
            "OPENAI_COMPAT",
            "MINIMAX",
            "ZAI",
            "CLINEPASS",
            "ALIBABA_CODING_PLAN",
            "GEMINI",
            "GEMINI_AUTH" -> true
            "OPENCODE_GO",
            "CODEX_AUTH",
            "SUPERGROK",
            "APPLE_INTELLIGENCE" -> false
            else -> false
        }
    }

    fun defaultRegistry(): LocalToolRegistry =
        LocalToolRegistry(listOf(WebSearchTool(), FetchUrlTool()))

    fun clientToolDefinitions(): List<ToolDefinition> =
        defaultRegistry().definitions

    fun toGeminiFunctionDeclarations(): List<FunctionDeclaration> {
        return clientToolDefinitions().map { definition ->
            FunctionDeclaration(
                name = definition.name,
                description = definition.description,
                parameters = parseParameters(definition.parametersJSON)
            )
        }
    }

    private fun parseParameters(parametersJSON: String): JsonElement? {
        val trimmed = parametersJSON.trim()
        if (trimmed.isEmpty()) return null
        return runCatching { json.parseToJsonElement(trimmed) }.getOrNull()
    }
}
