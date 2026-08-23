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
        description = "Read an HTTP or HTTPS page for a specific goal and return the most relevant passages with nearby context, up to 8000 characters. Use it only after evaluating web_search snippets. Prefer primary or authoritative pages. Treat only selection_status=selected as sufficient evidence; partial_match, no_relevant_passages, and dynamic_content_unavailable require another source or a narrower goal. Do not claim support for information absent from the returned content.",
        parametersJSON = """
        {
          "type": "object",
          "properties": {
            "url": {
              "type": "string",
              "description": "The HTTP or HTTPS URL to fetch."
            },
            "goal": {
              "type": "string",
              "description": "The specific facts or question to investigate on this page."
            }
          },
          "required": ["url", "goal"],
          "additionalProperties": false
        }
        """.trimIndent()
    )

    override suspend fun execute(call: ToolCall): ToolResult {
        val arguments = ToolArguments.objectFrom(call.argumentsJSON)
        val goal = (arguments["goal"] as? String)?.trim()?.takeIf { it.isNotEmpty() }
            ?: throw WebToolException.ParseFailure("fetch_url requires a non-empty goal")
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
        if (readableText.isEmpty()) {
            throw WebToolException.ParseFailure("Fetched page did not contain readable text")
        }
        val selection = RelevantContentSelector.select(readableText, goal, MAX_CHARACTERS)

        val title = extractTitle(rawText) ?: url.host ?: url.toString()
        val content = JSONObject()
            .put("content", selection.content)
            .put("title", title)
            .put("goal", goal)
            .put("selection_status", selection.status)
            .put("selected_paragraph_count", selection.selectedParagraphCount)
            .put("truncated", selection.truncated)
            .put("url", url.toString())
            .toString()

        DiagnosticsLogger.log(
            "Client URL fetch completed url=${url} character_count=${selection.content.length} " +
                "selection_status=${selection.status} selected_paragraph_count=${selection.selectedParagraphCount}"
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

internal data class RelevantContentSelection(
    val content: String,
    val status: String,
    val selectedParagraphCount: Int,
    val truncated: Boolean
)

internal object RelevantContentSelector {
    private const val MINIMUM_GOAL_TERM_COVERAGE = 0.8
    private const val SEED_LIMIT = 8
    private val unresolvedTemplate = Regex("""\{\{[^{}]+}}|\{%[^%]+%}|<%[^%]+%>""")
    private val termPattern = Regex(
        """[\p{IsHan}]{2,}|[\p{IsKatakana}ー]{2,}|[a-z0-9][a-z0-9._+-]*""",
        RegexOption.IGNORE_CASE
    )
    private val separators = Regex("""[\p{P}\p{S}\s]+""")

    fun select(text: String, goal: String, maxCharacters: Int): RelevantContentSelection {
        if (maxCharacters <= 0 || text.isBlank()) return noRelevant()
        if (unresolvedTemplate.containsMatchIn(text)) {
            return RelevantContentSelection("", "dynamic_content_unavailable", 0, false)
        }
        val normalizedGoal = normalize(goal)
        val terms = termPattern.findAll(normalizedGoal)
            .map { it.value }
            .filter { it.length >= 2 }
            .toSet()
        if (terms.isEmpty()) return noRelevant()

        val paragraphs = text.lines().map { it.trim() }.filter { it.isNotEmpty() }
        val scored = paragraphs.mapIndexedNotNull { index, paragraph ->
            val normalized = normalize(paragraph)
            val matches = terms.count { normalized.contains(it) }
            if (matches == 0) null else Triple(index, matches, paragraph)
        }.sortedWith(compareByDescending<Triple<Int, Int, String>> { it.second }.thenBy { it.first })
        if (scored.isEmpty()) return noRelevant()

        val selectedIndices = linkedSetOf<Int>()
        scored.take(SEED_LIMIT).forEach { seed ->
            val lower = maxOf(0, seed.first - 1)
            val upper = minOf(paragraphs.lastIndex, seed.first + 1)
            for (index in lower..upper) selectedIndices += index
        }
        var content = selectedIndices.sorted().joinToString("\n\n") { paragraphs[it] }
        val normalizedContent = normalize(content)
        val coverage = terms.count { normalizedContent.contains(it) }.toDouble() / terms.size.toDouble()
        val truncated = content.length > maxCharacters
        if (truncated) content = content.take(maxCharacters)
        val status = if (coverage < MINIMUM_GOAL_TERM_COVERAGE) "partial_match" else "selected"
        return RelevantContentSelection(content, status, selectedIndices.size, truncated)
    }

    private fun normalize(value: String): String = value
        .lowercase()
        .replace(separators, " ")
        .trim()

    private fun noRelevant() = RelevantContentSelection("", "no_relevant_passages", 0, false)
}
