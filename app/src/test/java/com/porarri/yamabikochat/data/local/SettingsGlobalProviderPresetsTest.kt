package com.porarri.yamabikochat.data.local

import org.junit.Assert.assertEquals
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

    @Test
    fun buildGlobalProviderPresets_ordersNewProvidersLikeCatalog() {
        val settings = Settings(
            providerDefaultModels = """
                {
                  "OPENAI": "gpt-4.1-mini",
                  "ALIBABA_CODING_PLAN": "qwen3.5-plus",
                  "GEMINI": "gemini-2.5-flash",
                  "OPENCODE_GO": "glm-5.1",
                  "OPENROUTER": "deepseek/deepseek-chat"
                }
            """.trimIndent()
        )

        val providers = settings.buildGlobalProviderPresets().map { it.apiProvider }

        assertEquals(
            listOf(
                "GEMINI",
                "OPENROUTER",
                "OPENCODE_GO",
                "ALIBABA_CODING_PLAN",
                "OPENAI"
            ),
            providers
        )
    }
}
