package com.porarri.yamabikochat.data.tools.search

import com.porarri.yamabikochat.utils.DiagnosticsLogger
import java.net.URL
import java.net.URLDecoder
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.Locale

class DuckDuckGoHTMLEngine(
    private val httpClient: WebToolHTTPClient = OkHttpWebToolHTTPClient()
) : SearchEngine {
    companion object {
        const val RESULT_LIMIT = 8
        const val REQUEST_TIMEOUT_SECONDS = 15L

        fun parseResults(html: String, maxResults: Int = RESULT_LIMIT): List<SearchResult> {
            val anchorPattern =
                """(?is)<a\b([^>]*\bclass\s*=\s*["'][^"']*(?:result__a|result-link)[^"']*["'][^>]*)>(.*?)</a>"""
            val genericLitePattern =
                """(?is)<a\b([^>]*\brel\s*=\s*["']nofollow["'][^>]*)>(.*?)</a>"""
            val anchorMatches = matches(anchorPattern, html)
            val matchesToUse = if (anchorMatches.isEmpty()) {
                matches(genericLitePattern, html)
            } else {
                anchorMatches
            }

            val results = mutableListOf<SearchResult>()
            val seenUrls = mutableSetOf<String>()
            val limit = minOf(maxOf(1, maxResults), RESULT_LIMIT)

            for (match in matchesToUse) {
                val attributes = match.groupValues.getOrNull(1) ?: continue
                val titleHtml = match.groupValues.getOrNull(2) ?: continue
                val href = attribute(named = "href", input = attributes) ?: continue
                val decodedUrl = decodeResultURL(href) ?: continue
                if (!seenUrls.add(decodedUrl)) continue

                val title = HTMLTextExtractor.extract(titleHtml, maxCharacters = 300)
                if (title.isEmpty()) continue

                val suffixStart = match.range.last + 1
                val remaining = html.substring(suffixStart, minOf(html.length, suffixStart + 2_000))
                val snippetHtml = firstCapture(
                    patterns = listOf(
                        """(?is)<(?:a|div|td)\b[^>]*class\s*=\s*["'][^"']*result__snippet[^"']*["'][^>]*>(.*?)</(?:a|div|td)>""",
                        """(?is)<td\b[^>]*class\s*=\s*["'][^"']*result-snippet[^"']*["'][^>]*>(.*?)</td>"""
                    ),
                    input = remaining
                )
                val snippet = snippetHtml?.let {
                    HTMLTextExtractor.extract(it, maxCharacters = 600)
                }.orEmpty()

                results.add(SearchResult(title = title, snippet = snippet, url = decodedUrl))
                if (results.size >= limit) break
            }
            return results
        }

        fun decodeResultURL(rawValue: String): String? {
            val decodedEntityValue = HTMLTextExtractor.decodeEntities(rawValue)
            val absoluteValue = when {
                decodedEntityValue.startsWith("//") -> "https:$decodedEntityValue"
                decodedEntityValue.startsWith("/") -> "https://duckduckgo.com$decodedEntityValue"
                else -> decodedEntityValue
            }

            val uri = runCatching { java.net.URI(absoluteValue) }.getOrNull()
            if (uri != null &&
                uri.host?.lowercase()?.endsWith("duckduckgo.com") == true &&
                (uri.path == "/l/" || uri.path == "/l")
            ) {
                val uddg = uri.rawQuery.orEmpty()
                    .split('&')
                    .firstOrNull { it.startsWith("uddg=") }
                    ?.substringAfter("uddg=")
                if (!uddg.isNullOrEmpty()) {
                    val decoded = runCatching {
                        URLDecoder.decode(uddg, StandardCharsets.UTF_8.name())
                    }.getOrNull()
                    val redirectedUrl = decoded?.let { runCatching { URL(it) }.getOrNull() }
                    val scheme = redirectedUrl?.protocol?.lowercase()
                    if (scheme == "http" || scheme == "https") {
                        return redirectedUrl.toString()
                    }
                }
            }

            val url = runCatching { URL(absoluteValue) }.getOrNull() ?: return null
            val scheme = url.protocol?.lowercase()
            return if (scheme == "http" || scheme == "https") url.toString() else null
        }

        fun regionParameter(locale: Locale): String {
            val language = locale.language.lowercase(Locale.ROOT).ifEmpty { "en" }
            val region = locale.country.lowercase(Locale.ROOT).ifEmpty { "us" }
            if (region == "jp" || language == "ja") {
                return "jp-jp"
            }
            return "$region-$language"
        }

        private fun matches(pattern: String, input: String): List<MatchResult> {
            return runCatching { Regex(pattern).findAll(input).toList() }.getOrDefault(emptyList())
        }

        private fun attribute(named: String, input: String): String? {
            val escaped = Regex.escape(named)
            val regex = Regex("""(?is)\b$escaped\s*=\s*(["'])(.*?)\1""")
            return regex.find(input)?.groupValues?.getOrNull(2)
        }

        private fun firstCapture(patterns: List<String>, input: String): String? {
            for (pattern in patterns) {
                val match = runCatching { Regex(pattern).find(input) }.getOrNull() ?: continue
                val capture = match.groupValues.getOrNull(1)
                if (capture != null) return capture
            }
            return null
        }
    }

    override suspend fun search(query: String, locale: Locale, maxResults: Int): List<SearchResult> {
        val normalizedQuery = query.trim()
        if (normalizedQuery.isEmpty()) {
            throw WebToolException.ParseFailure("Search query is empty")
        }
        val limit = minOf(maxOf(1, maxResults), RESULT_LIMIT)
        val region = regionParameter(locale)

        try {
            val primary = fetch(
                endpoint = "https://html.duckduckgo.com/html/",
                query = normalizedQuery,
                region = region
            )
            val results = parseResults(html = primary, maxResults = limit)
            if (results.isNotEmpty()) {
                return results
            }
            throw WebToolException.ParseFailure("DuckDuckGo HTML returned no results")
        } catch (e: kotlinx.coroutines.CancellationException) {
            throw e
        } catch (e: Exception) {
            DiagnosticsLogger.log(
                "DuckDuckGo HTML search failed; trying Lite query=$normalizedQuery",
                e
            )
            try {
                val fallback = fetch(
                    endpoint = "https://lite.duckduckgo.com/lite/",
                    query = normalizedQuery,
                    region = region
                )
                val results = parseResults(html = fallback, maxResults = limit)
                if (results.isEmpty()) {
                    val noResultsError =
                        WebToolException.ParseFailure("DuckDuckGo Lite returned no results")
                    DiagnosticsLogger.log(
                        "DuckDuckGo Lite returned no results query=$normalizedQuery",
                        noResultsError
                    )
                    throw noResultsError
                }
                return results
            } catch (ce: kotlinx.coroutines.CancellationException) {
                throw ce
            } catch (liteError: WebToolException.ParseFailure) {
                if (liteError.message == "DuckDuckGo Lite returned no results") {
                    throw liteError
                }
                DiagnosticsLogger.log(
                    "DuckDuckGo Lite search failed query=$normalizedQuery",
                    liteError
                )
                throw liteError
            } catch (liteError: Exception) {
                DiagnosticsLogger.log(
                    "DuckDuckGo Lite search failed query=$normalizedQuery",
                    liteError
                )
                throw liteError
            }
        }
    }

    private suspend fun fetch(endpoint: String, query: String, region: String): String {
        val encodedQuery = URLEncoder.encode(query, StandardCharsets.UTF_8.name())
        val encodedRegion = URLEncoder.encode(region, StandardCharsets.UTF_8.name())
        val url = URL("$endpoint?q=$encodedQuery&kl=$encodedRegion&kp=1")
        val response = httpClient.get(url = url, timeoutSeconds = REQUEST_TIMEOUT_SECONDS)
        if (response.statusCode !in 200..299) {
            val bodyText = response.body.toString(StandardCharsets.UTF_8)
            val httpError = WebToolException.HttpStatus(response.statusCode, bodyText)
            DiagnosticsLogger.log(
                "DuckDuckGo search HTTP error endpoint=$endpoint status_code=${response.statusCode}",
                httpError
            )
            throw httpError
        }
        return decodeHtmlBody(response.body)
            ?: throw WebToolException.ParseFailure("DuckDuckGo response encoding is unsupported")
    }

    private fun decodeHtmlBody(data: ByteArray): String? {
        return runCatching { String(data, StandardCharsets.UTF_8) }.getOrNull()
            ?: runCatching { String(data, Charsets.ISO_8859_1) }.getOrNull()
    }
}
