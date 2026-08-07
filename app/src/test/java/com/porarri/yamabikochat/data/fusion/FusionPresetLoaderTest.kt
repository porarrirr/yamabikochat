package com.porarri.yamabikochat.data.fusion

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FusionPresetLoaderTest {
    @Test
    fun defaultPresetHasFourPanelsAndRequiredModels() {
        val preset = FusionPresetLoader.defaultFusionCustomPreset()
        assertEquals(4, preset.panelModels.size)
        assertEquals("gemini-2.5-pro", preset.panelModels[0].modelId)
        assertEquals("GEMINI", preset.panelModels[0].provider)
        assertEquals("anthropic/claude-sonnet-4", preset.panelModels[1].modelId)
        assertEquals("OPENROUTER", preset.panelModels[1].provider)
        assertEquals("openai/gpt-4.1", preset.panelModels[2].modelId)
        assertEquals("deepseek/deepseek-chat", preset.panelModels[3].modelId)
        assertEquals("anthropic/claude-sonnet-4", preset.judgeModel.modelId)
        assertEquals("gemini-2.5-pro", preset.synthesizerModel.modelId)
        assertEquals("gemini-2.5-flash", preset.fallbackModel?.modelId)
        FusionPresetLoader.validatePreset(preset)
    }

    @Test
    fun emptyCustomJSONUsesDefault() {
        val request = FusionPresetLoader.buildRequest(
            userPrompt = "hello",
            customPresetJSON = ""
        )
        assertEquals("custom", request.preset)
        assertEquals(4, request.panelModels.size)
        assertEquals(FusionTaskType.research, request.taskType)
    }

    @Test
    fun taskTypeOverrideWinsOverPreset() {
        val request = FusionPresetLoader.buildRequest(
            userPrompt = "hello",
            taskTypeOverride = FusionTaskType.coding,
            customPresetJSON = ""
        )
        assertEquals(FusionTaskType.coding, request.taskType)
    }

    @Test
    fun normalizeUppercasesProviders() {
        val raw = FusionPresetDefinition(
            taskType = FusionTaskType.research,
            panelModels = listOf(
                PanelModelConfig(modelId = " m ", provider = " gemini ")
            ),
            judgeModel = PanelModelConfig(modelId = "j", provider = "openrouter"),
            synthesizerModel = PanelModelConfig(modelId = "s", provider = "gemini")
        )
        val normalized = FusionPresetLoader.normalizedFusionPresetDefinition(raw)
        assertEquals("GEMINI", normalized.panelModels[0].provider)
        assertEquals("m", normalized.panelModels[0].modelId)
        assertEquals("OPENROUTER", normalized.judgeModel.provider)
        assertTrue(normalized.fallbackModel != null)
    }

    @Test
    fun normalizeMigratesLegacyZaiModelWithoutChangingOpenCodeGoModel() {
        val raw = FusionPresetDefinition(
            panelModels = listOf(
                PanelModelConfig(modelId = "glm-5.1", provider = "ZAI"),
                PanelModelConfig(modelId = "glm-5.1", provider = "OPENCODE_GO")
            ),
            judgeModel = PanelModelConfig(modelId = "glm-5.1", provider = "ZAI"),
            synthesizerModel = PanelModelConfig(modelId = "glm-5.1", provider = "OPENCODE_GO")
        )

        val normalized = FusionPresetLoader.normalizedFusionPresetDefinition(raw)

        assertEquals("glm-5.2", normalized.panelModels[0].modelId)
        assertEquals("glm-5.1", normalized.panelModels[1].modelId)
        assertEquals("glm-5.2", normalized.judgeModel.modelId)
        assertEquals("glm-5.1", normalized.synthesizerModel.modelId)
    }
}
