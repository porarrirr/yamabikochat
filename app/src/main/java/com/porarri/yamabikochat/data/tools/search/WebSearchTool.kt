package com.porarri.yamabikochat.data.tools.search

import com.porarri.yamabikochat.data.tools.LocalToolExecutor
import com.porarri.yamabikochat.data.tools.LocalToolRegistry
import com.porarri.yamabikochat.data.tools.ToolArguments
import com.porarri.yamabikochat.data.tools.ToolCall
import com.porarri.yamabikochat.data.tools.ToolDefinition
import com.porarri.yamabikochat.data.tools.ToolResult
import com.porarri.yamabikochat.data.tools.ToolSource
import com.porarri.yamabikochat.data.tools.WebToolException
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import org.json.JSONArray
import org.json.JSONObject
import java.util.Locale

class WebSearchTool(
    private val engine: SearchEngine = DuckDuckGoHTMLEngine(),
    private val locale: Locale = Locale.getDefault()
) : LocalToolExecutor {
    override val definition = ToolDefinition(
        name = NAME,
        description = "Search the public web. Returns up to 8 result titles, snippets, and URLs. Use fetch_url only when page text is needed.",
        parametersJSON = """
        {
          "type": "object",
          "properties": {
            "query": {
              "type": "string",
              "description": "The search query."
            },
            "max_results": {
              "type": "integer",
              "minimum": 1,
              "maximum": 8,
              "default": 8
            }
          },
          "required": ["query"],
          "additionalProperties": false
        }
        """.trimIndent()
    )

    override suspend fun execute(call: ToolCall): ToolResult {
        return try {
            val arguments = ToolArguments.objectFrom(call.argumentsJSON)
            val query = (arguments["query"] as? String)?.trim()?.takeIf { it.isNotEmpty() }
                ?: throw WebToolException.ParseFailure("web_search requires a non-empty query")
            val requestedLimit =
                ToolArguments.int(arguments["max_results"]) ?: DuckDuckGoHTMLEngine.RESULT_LIMIT
            val limit = minOf(maxOf(1, requestedLimit), DuckDuckGoHTMLEngine.RESULT_LIMIT)
            val results = engine.search(query = query, locale = locale, maxResults = limit)

            val resultsArray = JSONArray()
            for (result in results) {
                resultsArray.put(
                    JSONObject()
                        .put("snippet", result.snippet)
                        .put("title", result.title)
                        .put("url", result.url)
                )
            }
            val content = JSONObject()
                .put("query", query)
                .put("results", resultsArray)
                .toString()

            DiagnosticsLogger.log(
                "Client web search completed query=$query result_count=${results.size}"
            )
            ToolResult(
                callId = call.id,
                name = call.name,
                content = content,
                sources = results.map { ToolSource(title = it.title, url = it.url) }
            )
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            val query = queryFrom(call.argumentsJSON) ?: "-"
            val limit = limitFrom(call.argumentsJSON)
            DiagnosticsLogger.log(
                "Client web search failed query=$query max_results=$limit",
                e
            )
            ToolResult(
                callId = call.id,
                name = call.name,
                content = LocalToolRegistry.errorContent(e.message ?: "web_search failed"),
                isError = true
            )
        }
    }

    companion object {
        const val NAME = "web_search"

        private fun queryFrom(argumentsJSON: String): String? {
            return runCatching {
                (ToolArguments.objectFrom(argumentsJSON)["query"] as? String)
                    ?.trim()
                    ?.takeIf { it.isNotEmpty() }
            }.getOrNull()
        }

        private fun limitFrom(argumentsJSON: String): Int {
            return runCatching {
                val requested =
                    ToolArguments.int(ToolArguments.objectFrom(argumentsJSON)["max_results"])
                        ?: DuckDuckGoHTMLEngine.RESULT_LIMIT
                minOf(maxOf(1, requested), DuckDuckGoHTMLEngine.RESULT_LIMIT)
            }.getOrDefault(DuckDuckGoHTMLEngine.RESULT_LIMIT)
        }
    }
}
