package com.porarri.yamabikochat.data.tools.search

import com.porarri.yamabikochat.data.model.ToolCall
import com.porarri.yamabikochat.data.model.ToolDefinition
import com.porarri.yamabikochat.data.model.ToolResult
import com.porarri.yamabikochat.data.model.ToolSource
import com.porarri.yamabikochat.data.tools.LocalToolExecutor
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement
import org.json.JSONObject
import java.net.URL
import java.nio.charset.StandardCharsets

class FetchUrlTool(
    private val httpClient: WebToolHTTPClient = OkHttpWebToolHTTPClient()
) : LocalToolExecutor {
    override val definition = ToolDefinition(
        name = NAME,
        description = "Fetch an HTTP or HTTPS page and return readable text. The returned body is limited to 8000 characters.",
        parametersJSON = """
        {
          "type": "object",
          "properties": {
            "url": {
              "type": "string",
              "description": "The HTTP or HTTPS URL to fetch."
            }
          },
          "required": ["url"],
          "additionalProperties": false
        }
        """.trimIndent()
    )

    override suspend fun execute(call: ToolCall): ToolResult {
        val arguments = ToolArguments.objectFrom(call.argumentsJSON)
        val rawUrl = (arguments["url"] as? String)?.trim()?.takeIf { it.isNotEmpty() }
        val url = rawUrl?.let { runCatching { URL(it) }.getOrNull() }
        val scheme = url?.protocol?.lowercase()
        val host = url?.host?.trim().orEmpty()
        if (url == null || scheme !in setOf("http", "https") || host.isEmpty()) {
            throw WebToolException.InvalidUrl(rawUrl ?: (arguments["url"] as? String).orEmpty())
        }
        WebToolURLPolicy.validatePublicHTTPURL(url)

        val response = httpClient.get(url = url, timeoutSeconds = REQUEST_TIMEOUT_SECONDS)
        WebToolURLPolicy.validatePublicHTTPURL(URL(response.finalUrl))
        if (response.statusCode !in 200..299) {
            val bodyText = response.body.toString(StandardCharsets.UTF_8)
            throw WebToolException.HttpStatus(response.statusCode, bodyText)
        }
        if (response.body.size > MAX_RESPONSE_BYTES) {
            throw WebToolException.ParseFailure("Fetched page exceeds the 2 MB response limit")
        }

        val contentType = response.contentType?.lowercase().orEmpty()
        val isJson = isJSONDocument(contentType, url.path)
        if (contentType.isNotEmpty() &&
            !contentType.contains("text/") &&
            !contentType.contains("application/xhtml+xml") &&
            !isJson
        ) {
            throw WebToolException.ParseFailure("Unsupported fetched content type: $contentType")
        }

        val rawText = decodeBody(response.body)
            ?: throw WebToolException.ParseFailure("Fetched page encoding is unsupported")

        val readableText = when {
            isJson -> {
                readableJSON(rawText)
            }
            contentType.contains("text/plain") -> rawText
            else -> HTMLTextExtractor.extract(from = rawText, maxCharacters = Int.MAX_VALUE)
        }
        val extracted = readableText.take(MAX_CHARACTERS)
        if (extracted.isEmpty()) {
            throw WebToolException.ParseFailure("Fetched page did not contain readable text")
        }

        val title = extractTitle(rawText) ?: url.host ?: url.toString()
        val content = JSONObject()
            .put("content", extracted)
            .put("title", title)
            .put("truncated", readableText.length > MAX_CHARACTERS)
            .put("url", url.toString())
            .toString()

        DiagnosticsLogger.log(
            "Client URL fetch completed url=${url} character_count=${extracted.length}"
        )
        return ToolResult(
            callId = call.id,
            name = call.name,
            content = content,
            sources = listOf(ToolSource(title = title, url = url.toString()))
        )
    }

    companion object {
        const val NAME = "fetch_url"
        const val MAX_CHARACTERS = 8_000
        const val MAX_RESPONSE_BYTES = 2 * 1024 * 1024
        const val REQUEST_TIMEOUT_SECONDS = 15L
        private val jsonFormatter = Json { prettyPrint = true }

        internal fun isJSONContentType(contentType: String): Boolean {
            val mediaType = contentType.lowercase().substringBefore(';').trim()
            return mediaType == "application/json" || mediaType.endsWith("+json")
        }

        internal fun isJSONDocument(contentType: String, path: String): Boolean {
            return isJSONContentType(contentType) || path.endsWith(".json", ignoreCase = true)
        }

        internal fun readableJSON(rawText: String): String {
            val value = runCatching { jsonFormatter.parseToJsonElement(rawText) }
                .getOrElse { throw WebToolException.ParseFailure("Fetched JSON is invalid") }
            return jsonFormatter.encodeToString(JsonElement.serializer(), value)
        }

        private fun extractTitle(html: String): String? {
            val match = Regex("""(?is)<title\b[^>]*>(.*?)</title>""").find(html) ?: return null
            val titleHtml = match.groupValues.getOrNull(1) ?: return null
            return HTMLTextExtractor.extract(titleHtml, maxCharacters = 300)
                .trim()
                .takeIf { it.isNotEmpty() }
        }

        private fun decodeBody(data: ByteArray): String? {
            return runCatching { String(data, StandardCharsets.UTF_8) }.getOrNull()
                ?: runCatching { String(data, Charsets.ISO_8859_1) }.getOrNull()
        }
    }
}
