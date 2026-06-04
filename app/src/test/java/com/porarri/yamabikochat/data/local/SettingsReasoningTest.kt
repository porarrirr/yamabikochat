package com.porarri.yamabikochat.data.local

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class SettingsReasoningTest {

    @Test
    fun buildThinkingConfigFor_effortMode_setsEffortOnly() {
        val settings = Settings().copy(
            openRouterThinkingEnabled = true,
            openRouterReasoningMode = "effort",
            openRouterReasoningEffort = "high",
            openRouterReasoningExclude = false
        )

        val config = settings.buildThinkingConfigFor("OPENROUTER", "anthropic/claude-3.7-sonnet")

        assertNotNull(config)
        config!!
        assertEquals("high", config.effort)
        assertNull(config.thinkingBudget)
        assertNull(config.enabled)
        assertNull(config.exclude)
        assertTrue(config.includeThoughts)
    }

    @Test
    fun buildThinkingConfigFor_disabledReasoning_setsEnabledFalse() {
        val settings = Settings().copy(
            openRouterThinkingEnabled = false,
            openRouterReasoningMode = "auto",
            openRouterReasoningExclude = false
        )

        val config = settings.buildThinkingConfigFor("OPENROUTER", "deepseek/deepseek-r1")

        assertNotNull(config)
        config!!
        assertEquals(false, config.enabled)
        assertEquals(true, config.exclude)
    }

    @Test
    fun buildThinkingConfigFor_budgetMode_mapsTokensAndExclude() {
        val settings = Settings().copy(
            openRouterThinkingEnabled = true,
            openRouterThinkingBudget = 4096,
            openRouterReasoningMode = "budget",
            openRouterReasoningExclude = true
        )

        val config = settings.buildThinkingConfigFor("OPENROUTER", "anthropic/claude-3.7-sonnet")

        assertNotNull(config)
        config!!
        assertEquals(4096, config.thinkingBudget)
        assertEquals(true, config.exclude)
        assertEquals(false, config.includeThoughts)
    }

    @Test
    fun buildThinkingConfigFor_autoMode_enablesReasoning() {
        val settings = Settings().copy(
            openRouterThinkingEnabled = true,
            openRouterReasoningMode = "auto",
            openRouterReasoningExclude = false
        )

        val config = settings.buildThinkingConfigFor("OPENROUTER", "mistralai/mistral-large")

        assertNotNull(config)
        config!!
        assertEquals(true, config.enabled)
        assertNull(config.thinkingBudget)
        assertNull(config.effort)
    }

    @Test
    fun buildThinkingConfigFor_dualOverridesUseContextValues() {
        val settings = Settings().copy(
            openRouterThinkingEnabled = false,
            openRouterThinkingBudget = 0,
            openRouterReasoningMode = "auto",
            dualOpenRouterThinkingEnabledA = true,
            dualOpenRouterThinkingBudgetA = 2048,
            dualOpenRouterReasoningModeA = "budget",
            dualOpenRouterReasoningExcludeA = false
        )

        val config = settings.buildThinkingConfigFor(
            provider = "OPENROUTER",
            model = "openai/gpt-5-mini",
            context = Settings.ReasoningContext.DUAL_A
        )

        assertNotNull(config)
        config!!
        assertEquals(2048, config.thinkingBudget)
        assertNull(config.enabled)
        assertNull(config.effort)
        assertNull(config.exclude)
        assertTrue(config.includeThoughts)
    }

    @Test
    fun buildThinkingConfigFor_alibabaUsesAnthropicBudget() {
        val settings = Settings().copy(
            geminiThinkingEnabled = true,
            geminiThinkingBudget = 2048
        )

        val config = settings.buildThinkingConfigFor(
            provider = "ALIBABA_CODING_PLAN",
            model = "qwen3.5-plus"
        )

        assertNotNull(config)
        config!!
        assertEquals(true, config.enabled)
        assertEquals(2048, config.thinkingBudget)
        assertTrue(config.includeThoughts)
    }

    @Test
    fun buildThinkingConfigFor_openCodeGoMessagesUsesAnthropicBudget() {
        val settings = Settings().copy(
            geminiThinkingEnabled = true,
            geminiThinkingBudget = 2048
        )

        val config = settings.buildThinkingConfigFor(
            provider = "OPENCODE_GO",
            model = "qwen3.5-plus"
        )

        assertNotNull(config)
        config!!
        assertEquals(true, config.enabled)
        assertEquals(2048, config.thinkingBudget)
        assertTrue(config.includeThoughts)
    }

    @Test
    fun buildThinkingConfigFor_openCodeGoChatCompletionsUsesOpenAiBudget() {
        val settings = Settings().copy(
            geminiThinkingEnabled = true,
            geminiThinkingBudget = 4096
        )

        val config = settings.buildThinkingConfigFor(
            provider = "OPENCODE_GO",
            model = "glm-5.1"
        )

        assertNotNull(config)
        config!!
        assertNull(config.enabled)
        assertEquals(4096, config.thinkingBudget)
        assertTrue(config.includeThoughts)
    }

    @Test
    fun buildCodexRequestConfig_carriesPromptCacheDisabledState() {
        val settings = Settings().copy(
            codexReasoningEnabled = false,
            codexPromptCacheEnabled = false
        )

        val config = settings.buildCodexRequestConfig("unsupported-model")

        assertNotNull(config)
        config!!
        assertEquals(false, config.promptCacheEnabled)
    }
}
