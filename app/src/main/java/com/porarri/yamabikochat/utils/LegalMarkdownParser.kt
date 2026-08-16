package com.porarri.yamabikochat.utils

sealed class LegalMarkdownBlock {
    data class Heading(val level: Int, val text: String) : LegalMarkdownBlock()
    data class Paragraph(val text: String) : LegalMarkdownBlock()
    data class Table(val headers: List<String>, val rows: List<List<String>>) : LegalMarkdownBlock()
    data class Code(val text: String) : LegalMarkdownBlock()
}

object LegalMarkdownParser {
    fun parse(markdown: String): List<LegalMarkdownBlock> {
        val lines = markdown.replace("\r\n", "\n").replace("\r", "\n").split("\n")
        val blocks = mutableListOf<LegalMarkdownBlock>()
        var index = 0
        while (index < lines.size) {
            val trimmed = lines[index].trim()
            when {
                trimmed.startsWith("```") -> {
                    val (code, next) = readCodeBlock(lines, index)
                    if (code.isNotBlank()) blocks += LegalMarkdownBlock.Code(code)
                    index = next
                }
                trimmed.isEmpty() -> index++
                parseHeading(trimmed) != null -> {
                    blocks += parseHeading(trimmed)!!
                    index++
                }
                trimmed.startsWith("|") -> {
                    val (table, next) = readTable(lines, index)
                    if (table != null) blocks += table
                    index = next
                }
                else -> {
                    val (paragraph, next) = readParagraph(lines, index)
                    if (paragraph.isNotEmpty()) blocks += LegalMarkdownBlock.Paragraph(paragraph)
                    index = next
                }
            }
        }
        return blocks
    }

    fun inlinePlainText(markdown: String): String {
        var text = replaceLinks(markdown)
        text = BOLD_REGEX.replace(text, "$1")
        text = CODE_REGEX.replace(text, "$1")
        return text.trim()
    }

    private fun parseHeading(line: String): LegalMarkdownBlock.Heading? {
        if (!line.startsWith("#")) return null
        var level = 0
        for (character in line) {
            if (character == '#') level++ else break
        }
        if (level !in 1..6) return null
        val raw = line.drop(level).trim()
        if (raw.isEmpty()) return null
        return LegalMarkdownBlock.Heading(level, inlinePlainText(raw))
    }

    private fun readCodeBlock(lines: List<String>, start: Int): Pair<String, Int> {
        val body = mutableListOf<String>()
        var index = start + 1
        while (index < lines.size) {
            if (lines[index].trim().startsWith("```")) {
                return body.joinToString("\n") to index + 1
            }
            body += lines[index]
            index++
        }
        return body.joinToString("\n") to index
    }

    private fun readTable(lines: List<String>, start: Int): Pair<LegalMarkdownBlock.Table?, Int> {
        var index = start
        val tableLines = mutableListOf<String>()
        while (index < lines.size) {
            val trimmed = lines[index].trim()
            if (trimmed.startsWith("|")) {
                tableLines += trimmed
                index++
            } else {
                break
            }
        }
        val parsedRows = tableLines.map(::splitTableRow)
            .filter { row -> row.isNotEmpty() && !isAlignmentRow(row) }
        val headers = parsedRows.firstOrNull()
        if (headers == null || headers.size < 2 || parsedRows.size < 2) {
            return null to index
        }
        val rows = parsedRows.drop(1).map { padded(it, headers.size) }
        return LegalMarkdownBlock.Table(headers, rows) to index
    }

    private fun readParagraph(lines: List<String>, start: Int): Pair<String, Int> {
        var index = start
        val parts = mutableListOf<String>()
        while (index < lines.size) {
            val trimmed = lines[index].trim()
            if (trimmed.isEmpty() || trimmed.startsWith("#") || trimmed.startsWith("|") || trimmed.startsWith("```")) {
                break
            }
            parts += trimmed
            index++
        }
        return inlinePlainText(parts.joinToString(" ")) to index
    }

    private fun splitTableRow(line: String): List<String> {
        val cells = line.split("|").map { it.trim() }.toMutableList()
        if (cells.firstOrNull() == "") cells.removeAt(0)
        if (cells.lastOrNull() == "") cells.removeAt(cells.lastIndex)
        return cells.map(::inlinePlainText)
    }

    private fun isAlignmentRow(row: List<String>): Boolean {
        return row.isNotEmpty() && row.all { cell ->
            val compact = cell.replace(":", "").replace("-", "")
            compact.isEmpty() && cell.contains("-")
        }
    }

    private fun padded(row: List<String>, count: Int): List<String> {
        return if (row.size >= count) row.take(count) else row + List(count - row.size) { "" }
    }

    private fun replaceLinks(text: String): String = LINK_REGEX.replace(text, "$1")

    private val LINK_REGEX = Regex("""\[([^\]]+)\]\(([^)]+)\)""")
    private val BOLD_REGEX = Regex("""\*\*(.+?)\*\*""")
    private val CODE_REGEX = Regex("""`([^`]+)`""")
}
