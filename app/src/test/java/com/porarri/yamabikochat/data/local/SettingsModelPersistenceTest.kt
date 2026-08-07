package com.porarri.yamabikochat.data.local

import org.junit.Assert.assertEquals
import org.junit.Test

class SettingsModelPersistenceTest {
    @Test
    fun normalizationMigratesOnlyZaiLegacyModelIds() {
        val normalized = Settings(
            apiProvider = "ZAI",
            defaultModel = "glm-5.1",
            dualProviderA = "ZAI",
            dualModelA = "glm-5.1",
            dualProviderB = "OPENCODE_GO",
            dualModelB = "glm-5.1",
            autoProviderA = "ZAI",
            autoModelA = "glm-5.1",
            providerDefaultModels = """{"ZAI":"glm-5.1","OPENCODE_GO":"glm-5.1"}"""
        ).normalizedForPersistence()

        assertEquals("glm-5.2", normalized.defaultModel)
        assertEquals("glm-5.2", normalized.dualModelA)
        assertEquals("glm-5.1", normalized.dualModelB)
        assertEquals("glm-5.2", normalized.autoModelA)
        assertEquals("glm-5.2", normalized.getModelForProvider("ZAI"))
        assertEquals("glm-5.1", normalized.getModelForProvider("OPENCODE_GO"))
    }


    @Test
    fun withModelForProvider_persistsPreviousProviderModel() {
        val currentSettings = Settings(
            apiProvider = "GEMINI",
            defaultModel = "gemini-2.5-flash"
        )

        val updateBase = currentSettings.copy(apiProvider = "OPENROUTER")

        val updated = updateBase.withModelForProvider(
            provider = "OPENROUTER",
            model = "deepseek/deepseek-chat",
            previousProvider = currentSettings.apiProvider,
            previousModel = currentSettings.getModelForProvider(currentSettings.apiProvider)
        )

        assertEquals("deepseek/deepseek-chat", updated.getModelForProvider("OPENROUTER"))
        assertEquals("gemini-2.5-flash", updated.getModelForProvider("GEMINI"))
    }

    @Test
    fun withModelForProvider_retainsStoredModelsForMultipleProviders() {
        val initial = Settings(
            apiProvider = "GEMINI",
            defaultModel = "gemini-2.5-flash"
        )

        val openRouterBase = initial.copy(apiProvider = "OPENROUTER")
        val afterOpenRouter = openRouterBase.withModelForProvider(
            provider = "OPENROUTER",
            model = "qwen/qwq-32b",
            previousProvider = initial.apiProvider,
            previousModel = initial.getModelForProvider(initial.apiProvider)
        )

        val geminiBase = afterOpenRouter.copy(apiProvider = "GEMINI")
        val afterGemini = geminiBase.withModelForProvider(
            provider = "GEMINI",
            model = "gemini-2.5-pro",
            previousProvider = afterOpenRouter.apiProvider,
            previousModel = afterOpenRouter.getModelForProvider(afterOpenRouter.apiProvider)
        )

        assertEquals("gemini-2.5-pro", afterGemini.getModelForProvider("GEMINI"))
        assertEquals("qwen/qwq-32b", afterGemini.getModelForProvider("OPENROUTER"))
    }

    @Test
    fun withModelForProvider_mergesAdditionalModelsFromUi() {
        val initial = Settings(
            apiProvider = "GEMINI",
            defaultModel = "gemini-2.5-flash"
        )

        val openAiBase = initial.copy(apiProvider = "OPENAI")
        val updated = openAiBase.withModelForProvider(
            provider = "OPENAI",
            model = "gpt-4.1-mini",
            additionalModels = mapOf(
                "GEMINI" to "gemini-2.0-flash",
                "OPENROUTER" to "qwen/qwq-32b"
            ),
            previousProvider = initial.apiProvider,
            previousModel = initial.getModelForProvider(initial.apiProvider)
        )

        assertEquals("gpt-4.1-mini", updated.getModelForProvider("OPENAI"))
        assertEquals("gemini-2.0-flash", updated.getModelForProvider("GEMINI"))
        assertEquals("qwen/qwq-32b", updated.getModelForProvider("OPENROUTER"))
    }
}
