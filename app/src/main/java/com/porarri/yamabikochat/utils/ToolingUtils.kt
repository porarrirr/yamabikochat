package com.porarri.yamabikochat.utils

import android.util.Log
import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.data.remote.CodeExecution
import com.porarri.yamabikochat.data.remote.FunctionDeclaration
import com.porarri.yamabikochat.data.remote.GoogleSearch
import com.porarri.yamabikochat.data.remote.McpToolset
import com.porarri.yamabikochat.data.remote.Tool
import com.porarri.yamabikochat.data.remote.UrlContext
import com.porarri.yamabikochat.data.remote.GoogleMaps
import com.porarri.yamabikochat.data.remote.ComputerUse
import kotlinx.serialization.json.Json

object ToolingUtils {
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    fun buildTools(
        settings: Settings,
        provider: String,
        context: Settings.ReasoningContext? = null
    ): List<Tool> {
        val providerTools = mutableListOf<Tool>()
        if (settings.isGoogleSearchEnabledFor(provider, context)) {
            providerTools.add(Tool(google_search = GoogleSearch()))
        }
        if (settings.isUrlContextEnabledFor(provider, context)) {
            providerTools.add(Tool(url_context = UrlContext()))
        }
        if (settings.isCodeExecutionEnabledFor(provider, context)) {
            providerTools.add(Tool(code_execution = CodeExecution()))
        }
        if (settings.isGoogleMapsEnabledFor(provider, context)) {
            providerTools.add(Tool(google_maps = GoogleMaps()))
        }
        if (settings.isComputerUseEnabledFor(provider, context)) {
            providerTools.add(Tool(computer_use = ComputerUse()))
        }
        if (provider.uppercase() == "GEMINI") {
            parseFunctionDeclarations(settings.geminiFunctionDeclarations)?.let { declarations ->
                providerTools.add(Tool(function_declarations = declarations))
            }
        }
        if (provider.uppercase() == "ALIBABA_CODING_PLAN" && settings.alibabaMcpEnabled) {
            val serverUrl = settings.resolvedAlibabaMcpServerUrl()
                ?: throw IllegalArgumentException("Invalid Alibaba MCP server URL: ${settings.alibabaMcpServerUrl}")
            providerTools.add(
                Tool(
                    mcp_toolset = McpToolset(
                        serverUrl = serverUrl,
                        serverName = settings.resolvedAlibabaMcpServerName(),
                        allowedTools = settings.alibabaMcpAllowedToolsList()
                    )
                )
            )
        }
        return providerTools
    }

    private fun parseFunctionDeclarations(raw: String): List<FunctionDeclaration>? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null
        return runCatching {
            json.decodeFromString<List<FunctionDeclaration>>(trimmed)
        }.getOrElse { err ->
            Log.w("ToolingUtils", "Invalid function declarations JSON: ${err.message}")
            null
        }?.takeIf { it.isNotEmpty() }
    }
}
