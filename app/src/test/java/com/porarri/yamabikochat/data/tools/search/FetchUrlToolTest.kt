package com.porarri.yamabikochat.data.tools.search

import org.junit.Assert.assertThrows
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FetchUrlToolTest {
    @Test
    fun recognizesJsonMediaTypes() {
        assertTrue(FetchUrlTool.isJSONContentType("application/json; charset=utf-8"))
        assertTrue(FetchUrlTool.isJSONContentType("application/problem+json"))
        assertTrue(FetchUrlTool.isJSONDocument("application/octet-stream", "/weather.json"))
    }

    @Test
    fun formatsValidJsonForReading() {
        val readable = FetchUrlTool.readableJSON(
            """{"cities":[{"name":"東京","temperature":33}]}"""
        )

        assertTrue(readable.contains("\"cities\""))
        assertTrue(readable.contains("東京"))
        assertTrue(readable.contains("33"))
    }

    @Test
    fun rejectsMalformedJsonWithoutHtmlFallback() {
        assertThrows(WebToolException.ParseFailure::class.java) {
            FetchUrlTool.readableJSON("""{"weather":"sunny"""")
        }
    }

    @Test
    fun rejectsUnrenderedDynamicContentAsEvidence() {
        val selection = RelevantContentSelector.select(
            "東京都の各地の天気\nライブ放送中 {{ content.title }}\n各地の気温変化",
            "東京 今日の天気 最高 最低気温",
            8_000
        )

        assertEquals("dynamic_content_unavailable", selection.status)
        assertEquals("", selection.content)
    }

    @Test
    fun rejectsContentMissingMostGoalTerms() {
        val selection = RelevantContentSelector.select(
            "東京都の各地の天気\n明日は全国的に気温が変化します。",
            "東京 今日の天気 最高 最低気温",
            8_000
        )

        assertEquals("partial_match", selection.status)
    }

    @Test
    fun selectsContentThatCoversTheRequestedFacts() {
        val selection = RelevantContentSelector.select(
            "東京 今日の天気\n最高気温は33℃です。\n最低気温は26℃です。",
            "東京 今日の天気 最高 最低気温",
            8_000
        )

        assertEquals("selected", selection.status)
        assertTrue(selection.content.contains("33℃"))
    }
}
