package com.porarri.yamabikochat.data.tools.search

import org.junit.Assert.assertThrows
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
}
