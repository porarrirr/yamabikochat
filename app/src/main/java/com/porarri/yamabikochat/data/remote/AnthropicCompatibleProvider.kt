package com.porarri.yamabikochat.data.remote

import android.util.Log
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody
import okhttp3.ResponseBody.Companion.toResponseBody
import retrofit2.Response
import java.io.IOException
import java.net.URI

class AnthropicCompatibleProvider(
    private val makeService: (baseUrl: String) -> AnthropicCompatibleApiService
) {
    private companion object {
        const val ANTHROPIC_VERSION = "2023-06-01"
        const val MCP_BETA_HEADER = "mcp-client-2025-11-20"
        const val DEFAULT_MAX_TOKENS = 4096
        const val MINIMUM_THINKING_BUDGET_TOKENS = 1024
    }

    suspend fun generateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest,
        baseUrl: String,
        providerLabel: String,
        mcpAuthorizationToken: String? = null,
        reasoningEffort: String? = null
    ): Response<GenerateContentResponse> = withContext(Dispatchers.IO) {
        val cleanedKey = apiKey.trim()
        if (cleanedKey.isEmpty()) {
            return@withContext Response.error(401, "API Key is empty".toResponseBody())
        }
        val payload = buildRequest(
            model,
            request,
            stream = false,
            mcpAuthorizationToken = mcpAuthorizationToken,
            reasoningEffort = reasoningEffort
        )
        try {
            val response = makeService(baseUrl).createMessage(
                apiKey = cleanedKey,
                anthropicVersion = ANTHROPIC_VERSION,
                anthropicBeta = MCP_BETA_HEADER.takeIf { payload.mcpServers?.isNotEmpty() == true },
                request = payload
            )
            if (response.isSuccessful && response.body() != null) {
                Response.success(toGemini(response.body()!!))
            } else {
                val body = response.errorBody()?.string().orEmpty()
                Response.error(response.code(), body.toResponseBody("application/json".toMediaType()))
            }
        } catch (e: IOException) {
            DiagnosticsLogger.log("$providerLabel generateContent failed model=$model", e)
            Log.e("AnthropicProvider", "$providerLabel generateContent failed: ${e.message}", e)
            Response.error(500, (e.message ?: "Unknown error").toResponseBody())
        }
    }

    suspend fun streamGenerateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest,
        baseUrl: String,
        providerLabel: String,
        mcpAuthorizationToken: String? = null,
        reasoningEffort: String? = null
    ): Response<ResponseBody> = withContext(Dispatchers.IO) {
        val cleanedKey = apiKey.trim()
        if (cleanedKey.isEmpty()) {
            return@withContext Response.error(401, "API Key is empty".toResponseBody())
        }
        val payload = buildRequest(
            model,
            request,
            stream = true,
            mcpAuthorizationToken = mcpAuthorizationToken,
            reasoningEffort = reasoningEffort
        )
        try {
            makeService(baseUrl).streamMessage(
                apiKey = cleanedKey,
                anthropicVersion = ANTHROPIC_VERSION,
                anthropicBeta = MCP_BETA_HEADER.takeIf { payload.mcpServers?.isNotEmpty() == true },
                request = payload
            )
        } catch (e: IOException) {
            DiagnosticsLogger.log("$providerLabel streamGenerateContent failed model=$model", e)
            Response.error(500, (e.message ?: "Unknown error").toResponseBody())
        }
    }

    private fun buildRequest(
        model: String,
        request: GenerateContentRequest,
        stream: Boolean,
        mcpAuthorizationToken: String?,
        reasoningEffort: String?
    ): AnthropicMessageRequest {
        val thinking = buildThinking(request.generationConfig?.thinkingConfig)
        val mcp = buildMcpConfiguration(request.tools.orEmpty(), mcpAuthorizationToken)
        val maxTokens = maxOf(DEFAULT_MAX_TOKENS, (thinking?.budgetTokens ?: 0) + 1024)
        return AnthropicMessageRequest(
            model = model.trim(),
            messages = mapMessages(request.contents),
            system = request.system_instruction?.parts?.mapNotNull { it.text }?.joinToString("\n")?.trim()?.takeIf { it.isNotEmpty() },
            maxTokens = maxTokens,
            stream = stream,
            thinking = thinking,
            outputConfig = reasoningEffort?.trim()?.takeIf { it.isNotEmpty() }?.let(::AnthropicOutputConfig),
            mcpServers = mcp?.servers,
            tools = mcp?.toolsets
        )
    }

    private fun buildThinking(config: ThinkingConfig?): AnthropicThinking? {
        if (config?.enabled != true) return null
        val budget = config.thinkingBudget ?: return null
        if (budget < MINIMUM_THINKING_BUDGET_TOKENS) return null
        return AnthropicThinking(budgetTokens = budget)
    }

    private fun mapMessages(contents: List<Content>): List<AnthropicMessage> =
        contents.map { content ->
            AnthropicMessage(
                role = when (content.role?.trim()?.lowercase()) {
                    "assistant", "model" -> "assistant"
                    else -> "user"
                },
                content = content.parts.mapNotNull(::mapContentBlock).ifEmpty {
                    listOf(AnthropicContentBlock(type = "text", text = ""))
                }
            )
        }

    private fun mapContentBlock(part: Part): AnthropicContentBlock? {
        part.text?.let { return AnthropicContentBlock(type = "text", text = it) }
        val inline = part.inlineData ?: return null
        return AnthropicContentBlock(
            type = "image",
            source = AnthropicImageSource(
                mediaType = inline.mimeType,
                data = inline.data
            )
        )
    }

    private fun buildMcpConfiguration(
        tools: List<Tool>,
        mcpAuthorizationToken: String?
    ): McpConfiguration? {
        val tool = tools.firstOrNull { it.mcp_toolset != null }?.mcp_toolset ?: return null
        val normalizedUrl = normalizeHttpsUrl(tool.serverUrl)
            ?: throw IllegalArgumentException("Invalid MCP server URL: ${tool.serverUrl}")
        val serverName = tool.serverName.trim().ifBlank { ProviderCatalog.alibabaMcpDefaultServerName }
        val server = AnthropicMcpServer(
            url = normalizedUrl,
            name = serverName,
            authorizationToken = mcpAuthorizationToken?.trim()?.takeIf { it.isNotEmpty() }
        )
        val allowedTools = tool.allowedTools
            .map { it.trim() }
            .filter { it.isNotEmpty() }
            .distinctBy { it.lowercase() }
        val toolset = if (allowedTools.isEmpty()) {
            AnthropicMcpToolset(mcpServerName = serverName)
        } else {
            AnthropicMcpToolset(
                mcpServerName = serverName,
                defaultConfig = AnthropicMcpToolConfiguration(enabled = false),
                configs = allowedTools.associateWith { AnthropicMcpToolConfiguration(enabled = true) }
            )
        }
        return McpConfiguration(servers = listOf(server), toolsets = listOf(toolset))
    }

    private fun normalizeHttpsUrl(raw: String): String? {
        val trimmed = raw.trim()
        if (trimmed.isEmpty()) return null
        val uri = runCatching { URI(trimmed) }.getOrNull() ?: return null
        if (!uri.scheme.equals("https", ignoreCase = true)) return null
        if (uri.host.isNullOrBlank()) return null
        if (!uri.userInfo.isNullOrBlank()) return null
        return uri.toString()
    }

    private fun toGemini(response: AnthropicMessageResponse): GenerateContentResponse {
        val parts = buildList {
            val reasoning = response.content
                .filter { it.type.equals("thinking", ignoreCase = true) }
                .joinToString("") { it.thinking.orEmpty() }
                .takeIf { it.isNotBlank() }
            if (reasoning != null) {
                add(ResponsePart(text = reasoning, thought = true))
            }
            val text = response.content
                .filter { it.type.equals("text", ignoreCase = true) }
                .joinToString("") { it.text.orEmpty() }
            add(ResponsePart(text = text))
        }
        return GenerateContentResponse(
            candidates = listOf(
                Candidate(
                    content = ResponseContent(parts = parts, role = "model"),
                    finishReason = null,
                    index = 0
                )
            ),
            text = parts.filter { it.thought != true }.joinToString("") { it.text.orEmpty() },
            tokenUsage = response.usage?.toTokenUsageSnapshot()
        )
    }

    private data class McpConfiguration(
        val servers: List<AnthropicMcpServer>,
        val toolsets: List<AnthropicMcpToolset>
    )
}
