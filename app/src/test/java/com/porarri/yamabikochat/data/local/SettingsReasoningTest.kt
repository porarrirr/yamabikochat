package com.porarri.yamabikochat.data.local

import com.porarri.yamabikochat.data.remote.OpenRouterModelService
import com.porarri.yamabikochat.data.remote.OpenRouterReasoningCapabilities
import com.porarri.yamabikochat.data.remote.SimpleModel
import com.porarri.yamabikochat.data.repositories.ProviderRequestSettingsResolver
import com.porarri.yamabikochat.data.repositories.ProviderRequestToolScope
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SettingsReasoningTest {

    private fun createResolver(
        supportedEfforts: List<String>? = listOf("high", "medium", "low"),
        supportsMaxTokens: Boolean = true,
        mandatory: Boolean = false
    ): ProviderRequestSettingsResolver {
        val modelService = mockk<OpenRouterModelService>(relaxed = true)
        every { modelService.getModelById(any()) } answers {
            val modelId = firstArg<String>()
            SimpleModel(
                id = modelId,
                name = modelId,
                provider = modelId.substringBefore('/'),
                topProvider = null,
                contextLength = 128000,
                promptPricePerMillion = 1.0,
                completionPricePerMillion = 1.0,
                isFree = false,
                reasoning = OpenRouterReasoningCapabilities(
                    supportedEfforts = supportedEfforts,
                    exposesEffortSelection = supportedEfforts != null,
                    supportsMaxTokens = supportsMaxTokens,
                    mandatory = mandatory
                )
            )
        }
        return ProviderRequestSettingsResolver(
            modelService = modelService,
            skillRepository = mockk(relaxed = true)
        )
    }

    @Test
    fun buildThinkingConfigFor_effortMode_setsEffortOnly() = runBlocking {
        val settings = Settings(
            openRouterThinkingEnabled = true,
            openRouterReasoningMode = "effort",
            openRouterReasoningEffort = "high",
            openRouterReasoningExclude = false
        )
        val resolver = createResolver(supportedEfforts = listOf("high", "medium", "low"))
        val resolved = resolver.resolve(
            settings = settings,
            provider = "OPENROUTER",
            model = "anthropic/claude-3.7-sonnet",
            toolScope = ProviderRequestToolScope.None
        )

        val config = resolved.thinking
        assertNotNull(config)
        config!!
        assertEquals("high", config.effort)
        assertNull(config.budget)
        assertNull(config.enabled)
        assertNull(config.exclude)
        assertEquals(true, config.includeThoughts)
    }

    @Test
    fun buildThinkingConfigFor_disabledReasoning_setsEnabledFalse() = runBlocking {
        val settings = Settings(
            openRouterThinkingEnabled = false,
            openRouterReasoningMode = "auto",
            openRouterReasoningExclude = false
        )
        val resolver = createResolver()
        val resolved = resolver.resolve(
            settings = settings,
            provider = "OPENROUTER",
            model = "deepseek/deepseek-r1",
            toolScope = ProviderRequestToolScope.None
        )

        val config = resolved.thinking
        assertNotNull(config)
        config!!
        assertEquals(false, config.enabled)
        assertEquals(true, config.exclude)
    }

    @Test
    fun buildThinkingConfigFor_budgetMode_mapsTokensAndExclude() = runBlocking {
        val settings = Settings(
            openRouterThinkingEnabled = true,
            openRouterThinkingBudget = 4096,
            openRouterReasoningMode = "budget",
            openRouterReasoningExclude = true
        )
        val resolver = createResolver(supportsMaxTokens = true)
        val resolved = resolver.resolve(
            settings = settings,
            provider = "OPENROUTER",
            model = "anthropic/claude-3.7-sonnet",
            toolScope = ProviderRequestToolScope.None
        )

        val config = resolved.thinking
        assertNotNull(config)
        config!!
        assertEquals(4096, config.budget)
        assertEquals(true, config.exclude)
        assertEquals(false, config.includeThoughts)
    }

    @Test
    fun buildThinkingConfigFor_autoMode_enablesReasoning() = runBlocking {
        val settings = Settings(
            openRouterThinkingEnabled = true,
            openRouterReasoningMode = "auto",
            openRouterReasoningExclude = false
        )
        val resolver = createResolver()
        val resolved = resolver.resolve(
            settings = settings,
            provider = "OPENROUTER",
            model = "mistralai/mistral-large",
            toolScope = ProviderRequestToolScope.None
        )

        val config = resolved.thinking
        assertNotNull(config)
        config!!
        assertEquals(true, config.enabled)
        assertNull(config.budget)
        assertNull(config.effort)
    }

    @Test
    fun buildThinkingConfigFor_dualOverridesUseContextValues() = runBlocking {
        val settings = Settings(
            openRouterThinkingEnabled = false,
            openRouterThinkingBudget = 0,
            openRouterReasoningMode = "auto",
            dualOpenRouterThinkingEnabledA = true,
            dualOpenRouterThinkingBudgetA = 2048,
            dualOpenRouterReasoningModeA = "budget",
            dualOpenRouterReasoningExcludeA = false
        )
        val resolver = createResolver(supportsMaxTokens = true)
        val resolved = resolver.resolve(
            settings = settings,
            provider = "OPENROUTER",
            model = "openai/gpt-5-mini",
            context = Settings.ReasoningContext.DUAL_A,
            toolScope = ProviderRequestToolScope.None
        )

        val config = resolved.thinking
        assertNotNull(config)
        config!!
        assertEquals(2048, config.budget)
        assertNull(config.enabled)
        assertNull(config.effort)
        assertNull(config.exclude)
        assertEquals(true, config.includeThoughts)
    }
}
