package com.porarri.yamabikochat.data.remote

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SimpleModelSearchTest {
    private val model = SimpleModel(
        id = "deepseek/deepseek-v4-flash-0731",
        name = "DeepSeek V4 Flash 0731",
        provider = "deepseek",
        contextLength = 131_072,
        promptPricePerMillion = 0.0,
        completionPricePerMillion = 0.0,
        isFree = true
    )

    @Test
    fun matchesNonAdjacentSearchTerms() {
        assertTrue(model.matchesSearchQuery("v4 0731"))
        assertTrue(model.matchesSearchQuery("0731 DEEPSEEK"))
        assertTrue(model.matchesSearchQuery("deepseek-v4"))
        assertFalse(model.matchesSearchQuery("v4 0801"))
    }
}
