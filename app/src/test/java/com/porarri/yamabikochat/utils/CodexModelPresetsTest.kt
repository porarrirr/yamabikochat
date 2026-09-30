package com.porarri.yamabikochat.utils

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import com.porarri.yamabikochat.pi.PiCodexModel

class CodexModelPresetsTest {
    @Test
    fun accountCatalogPreservesPermissionAndThinkingLevels() {
        assertTrue(CodexModelPresets.visiblePresets(emptyList()).isEmpty())
        val models = listOf(
            PiCodexModel("gpt-6-sol", "Account label", true, supportedThinkingLevels = listOf("high")),
            PiCodexModel("disabled", "Disabled", false, "plan unavailable")
        )
        val presets = CodexModelPresets.visiblePresets(models)
        assertEquals("Account label", presets[0].displayName)
        assertEquals("high", presets[0].defaultReasoningEffort)
        assertEquals(listOf("high"), presets[0].supportedReasoningEfforts.map { it.effort })
        assertEquals(false, presets[1].isSupported)
        assertEquals("plan unavailable", presets[1].description)
    }

    @Test
    fun visiblePresetsMatchReferenceCatalogAndDefault() {
        val preset = CodexModelPresets.visiblePresets()
            .firstOrNull { it.model == "gpt-5.6-sol" }

        assertNotNull(preset)
        preset!!
        assertEquals("GPT-5.6 Sol", preset.displayName)
        assertEquals("low", preset.defaultReasoningEffort)
        assertEquals(listOf("low", "medium", "high", "xhigh", "max"), preset.supportedReasoningEfforts.map { it.effort })
        assertEquals("gpt-6-sol", CodexModelPresets.defaultModel())
        assertEquals(listOf("gpt-6-sol", "gpt-6-astra", "gpt-6-luna", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5"), CodexModelPresets.visiblePresets().map { it.model })
        assertTrue(CodexModelPresets.supportsReasoningSummary(preset.model))
        assertTrue(CodexModelPresets.supportsTextVerbosity(preset.model))
    }

    @Test
    fun runtimeCatalogCanAddNewPiModelWithoutEditingPresets() {
        val presets = CodexModelPresets.visiblePresets(listOf(PiCodexModel("future-codex-model", "Future Codex Model")))
        assertEquals("future-codex-model", presets.single().model)
        assertEquals("Future Codex Model", presets.single().displayName)
    }

    @Test
    fun savedUltraEffortFallsBackToPiSupportedLevel() {
        assertEquals("medium", CodexModelPresets.resolvedReasoningEffort("ultra", "gpt-6-sol"))
        assertEquals("max", CodexModelPresets.resolvedReasoningEffort("MAX", "gpt-6-sol"))
    }

    @Test
    fun findPresetMatchesGpt56SolCaseInsensitively() {
        val preset = CodexModelPresets.findPreset(" GPT-5.6-SOL ")

        assertNotNull(preset)
        assertEquals("gpt-5.6-sol", preset?.model)
    }
}
