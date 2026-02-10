package com.porarri.yamabikochat.data.local

import org.junit.Assert.assertTrue
import org.junit.Test

class SettingsGlobalProviderPresetsTest {
    @Test
    fun buildGlobalProviderPresets_defaultExcludesSystemPrompt() {
        val base = Settings(
            apiProvider = "GEMINI",
            defaultModel = "gemini-2.5-flash",
            systemPrompt = "GLOBAL"
        )

        val withModels = base.copy(apiProvider = "OPENROUTER").withModelForProvider(
            provider = "OPENROUTER",
            model = "qwen/qwq-32b",
            previousProvider = base.apiProvider,
            previousModel = base.getModelForProvider(base.apiProvider)
        )

        val presets = withModels.buildGlobalProviderPresets()
        assertTrue(presets.isNotEmpty())
        assertTrue(presets.all { it.systemPrompt == null })
    }

    @Test
    fun buildGlobalProviderPresets_includeSystemPromptIncludesPrompt() {
        val base = Settings(
            apiProvider = "GEMINI",
            defaultModel = "gemini-2.5-flash",
            systemPrompt = "GLOBAL"
        )

        val withModels = base.copy(apiProvider = "OPENROUTER").withModelForProvider(
            provider = "OPENROUTER",
            model = "qwen/qwq-32b",
            previousProvider = base.apiProvider,
            previousModel = base.getModelForProvider(base.apiProvider)
        )

        val presets = withModels.buildGlobalProviderPresets(includeSystemPrompt = true)
        assertTrue(presets.isNotEmpty())
        assertTrue(presets.all { it.systemPrompt == "GLOBAL" })
    }
}

