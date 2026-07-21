package com.porarri.yamabikochat.data.fusion

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class FusionJudgeParserTest {
    private val validJSON = """
    {
      "consensus": ["both agree"],
      "contradictions": [],
      "unique_insights": [],
      "coverage_gaps": [],
      "suspected_errors": [],
      "strongest_answer_parts": [{"model": "m1", "part": "answer", "reason": "clear"}],
      "recommended_final_position": "Merged",
      "confidence": "high"
    }
    """.trimIndent()

    @Test
    fun parseValidJSON() {
        val analysis = FusionJudgeParser.parse(validJSON)
        assertNotNull(analysis)
        assertEquals("Merged", analysis!!.recommendedFinalPosition)
        assertEquals(FusionConfidence.high, analysis.confidence)
        assertEquals(listOf("both agree"), analysis.consensus)
    }

    @Test
    fun parseWrappedInMarkdownFence() {
        val wrapped = """
        ```json
        $validJSON
        ```
        """.trimIndent()
        val analysis = FusionJudgeParser.parse(wrapped)
        assertNotNull(analysis)
        assertEquals("Merged", analysis!!.recommendedFinalPosition)
    }

    @Test
    fun parseInvalidJSONReturnsNull() {
        assertNull(FusionJudgeParser.parse("not json"))
        assertNull(FusionJudgeParser.parse("{invalid"))
    }

    @Test
    fun extractJSONFindsObjectBoundaries() {
        val text = "Here is the result:\n$validJSON\nDone."
        val extracted = FusionJudgeParser.extractJSON(text)
        assertTrue(extracted.startsWith("{"))
        assertTrue(extracted.endsWith("}"))
        assertNotNull(FusionJudgeParser.parse(extracted))
    }
}
