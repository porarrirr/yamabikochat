package com.porarri.yamabikochat.utils

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

class CodexModelPresetsTest {
    @Test
    fun visiblePresetsIncludeGpt53CodexSpark() {
        val preset = CodexModelPresets.visiblePresets()
            .firstOrNull { it.model == "gpt-5.3-codex-spark" }

        assertNotNull(preset)
        preset!!
        assertEquals("gpt-5.3-codex-spark", preset.displayName)
        assertEquals("medium", preset.defaultReasoningEffort)
        assertEquals(listOf("medium", "high"), preset.supportedReasoningEfforts.map { it.effort })
        assertTrue(CodexModelPresets.supportsReasoningSummary(preset.model))
        assertTrue(CodexModelPresets.supportsTextVerbosity(preset.model))
    }

    @Test
    fun findPresetMatchesGpt53CodexSparkCaseInsensitively() {
        val preset = CodexModelPresets.findPreset(" GPT-5.3-CODEX-SPARK ")

        assertNotNull(preset)
        assertEquals("gpt-5.3-codex-spark", preset?.model)
    }
}
