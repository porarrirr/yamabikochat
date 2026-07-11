package com.porarri.yamabikochat.utils

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CodexModelPresetsTest {
    @Test
    fun visiblePresetsMatchReferenceCatalogAndDefault() {
        val preset = CodexModelPresets.visiblePresets()
            .firstOrNull { it.model == "gpt-5.6-sol" }

        assertNotNull(preset)
        preset!!
        assertEquals("GPT-5.6-Sol", preset.displayName)
        assertEquals("low", preset.defaultReasoningEffort)
        assertEquals(listOf("low", "medium", "high", "xhigh", "max", "ultra"), preset.supportedReasoningEfforts.map { it.effort })
        assertEquals("gpt-5.6-sol", CodexModelPresets.defaultModel())
        assertEquals(listOf("gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "gpt-5.2"), CodexModelPresets.visiblePresets().map { it.model })
        assertTrue(CodexModelPresets.supportsReasoningSummary(preset.model))
        assertTrue(CodexModelPresets.supportsTextVerbosity(preset.model))
    }

    @Test
    fun findPresetMatchesGpt56SolCaseInsensitively() {
        val preset = CodexModelPresets.findPreset(" GPT-5.6-SOL ")

        assertNotNull(preset)
        assertEquals("gpt-5.6-sol", preset?.model)
    }
}
