package com.porarri.yamabikochat.data.tools.search

object HTMLTextExtractor {
    fun extract(from: String, maxCharacters: Int = 8_000): String {
        val withoutInvisible = replacingMatches(
            input = from,
            pattern = """(?is)<(script|style|noscript|svg|template)\b[^>]*>.*?</\1\s*>""",
            replacement = " "
        )
        val withLineBreaks = replacingMatches(
            input = withoutInvisible,
            pattern = """(?i)</?(p|div|section|article|header|footer|main|aside|h[1-6]|li|tr|br|hr)\b[^>]*>""",
            replacement = "\n"
        )
        val withoutTags = replacingMatches(
            input = withLineBreaks,
            pattern = """(?s)<[^>]+>""",
            replacement = " "
        )
        val decoded = decodeEntities(withoutTags)
        val lines = decoded
            .split('\n')
            .map { line ->
                line.replace(Regex("""\s+"""), " ").trim()
            }
            .filter { it.isNotEmpty() }
        val normalized = lines.joinToString("\n")
        return if (normalized.length > maxCharacters) {
            normalized.take(maxCharacters)
        } else {
            normalized
        }
    }

    fun decodeEntities(input: String): String {
        var result = input
        val named = mapOf(
            "&amp;" to "&",
            "&lt;" to "<",
            "&gt;" to ">",
            "&quot;" to "\"",
            "&#39;" to "'",
            "&apos;" to "'",
            "&nbsp;" to " "
        )
        for ((entity, value) in named) {
            result = result.replace(entity, value, ignoreCase = true)
        }

        val numeric = Regex("""&#(x[0-9a-fA-F]+|[0-9]+);""")
        result = numeric.replace(result) { match ->
            val raw = match.groupValues[1]
            val scalarValue = if (raw.lowercase().startsWith("x")) {
                raw.drop(1).toIntOrNull(16)
            } else {
                raw.toIntOrNull(10)
            }
            if (scalarValue != null && Character.isValidCodePoint(scalarValue)) {
                String(Character.toChars(scalarValue))
            } else {
                match.value
            }
        }
        return result
    }

    private fun replacingMatches(input: String, pattern: String, replacement: String): String {
        return runCatching {
            Regex(pattern).replace(input, replacement)
        }.getOrDefault(input)
    }
}
