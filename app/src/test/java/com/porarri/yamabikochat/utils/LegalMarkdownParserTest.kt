package com.porarri.yamabikochat.utils

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LegalMarkdownParserTest {
    @Test
    fun parsesHeadingsParagraphsTablesAndCode() {
        val markdown = """
            # Third-party notices

            See [LICENSE](LICENSE) and **Apache License 2.0**.

            ## Android libraries

            | Component | Version | SPDX | Source |
            | --- | --- | --- | --- |
            | Markwon (`core`) | 4.6.2 | Apache-2.0 | https://github.com/noties/Markwon |
            | AndroidSVG | 1.4 | Apache-2.0 | https://github.com/BigBadaboom/androidsvg |

            ## License texts

            ```
            MIT License text
            ```
        """.trimIndent()

        val blocks = LegalMarkdownParser.parse(markdown)
        assertEquals(6, blocks.size)

        val heading = blocks[0] as LegalMarkdownBlock.Heading
        assertEquals(1, heading.level)
        assertEquals("Third-party notices", heading.text)

        val paragraph = blocks[1] as LegalMarkdownBlock.Paragraph
        assertEquals("See LICENSE and Apache License 2.0.", paragraph.text)
        assertFalse(paragraph.text.contains("["))
        assertFalse(paragraph.text.contains("**"))

        val section = blocks[2] as LegalMarkdownBlock.Heading
        assertEquals(2, section.level)
        assertEquals("Android libraries", section.text)

        val table = blocks[3] as LegalMarkdownBlock.Table
        assertEquals(listOf("Component", "Version", "SPDX", "Source"), table.headers)
        assertEquals(2, table.rows.size)
        assertEquals("Markwon (core)", table.rows[0][0])
        assertEquals("4.6.2", table.rows[0][1])
        assertEquals("AndroidSVG", table.rows[1][0])

        val code = blocks[5] as LegalMarkdownBlock.Code
        assertEquals("MIT License text", code.text)
    }

    @Test
    fun ignoresAlignmentRowAndKeepsCellCount() {
        val markdown = """
            | Package | Version | License |
            | :--- | ---: | --- |
            | typebox | 1.3.7 | MIT |
        """.trimIndent()

        val blocks = LegalMarkdownParser.parse(markdown)
        val table = blocks.single() as LegalMarkdownBlock.Table
        assertEquals(3, table.headers.size)
        assertEquals(listOf(listOf("typebox", "1.3.7", "MIT")), table.rows)
        assertTrue(table.rows.none { row -> row.any { it.contains("---") } })
    }
}
