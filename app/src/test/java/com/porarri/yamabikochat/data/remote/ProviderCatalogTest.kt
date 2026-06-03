package com.porarri.yamabikochat.data.remote

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ProviderCatalogTest {
    @Test
    fun options_matchIosProviderOrderWithoutAppleIntelligence() {
        assertEquals(
            listOf(
                "GEMINI",
                "OPENROUTER",
                "OPENCODE_GO",
                "ALIBABA_CODING_PLAN",
                "ZAI",
                "MINIMAX",
                "OPENAI",
                "CODEX_AUTH",
                "OPENAI_COMPAT"
            ),
            ProviderCatalog.options.map { it.key }
        )
    }

    @Test
    fun newProvidersExposeDefaultModels() {
        assertEquals(OpenCodeGoModelCatalog.defaultModel, ProviderCatalog.defaultModel("OPENCODE_GO"))
        assertEquals(
            AlibabaCodingPlanModelCatalog.defaultModel,
            ProviderCatalog.defaultModel("ALIBABA_CODING_PLAN")
        )
        assertTrue(OpenCodeGoModelCatalog.modelFor("opencode-go/qwen3.7-max")?.endpointKind == OpenCodeGoEndpointKind.MESSAGES)
    }

    @Test
    fun alibabaCodingPlanBaseUrlTargetsAnthropicV1Messages() {
        assertEquals(
            "https://coding-intl.dashscope.aliyuncs.com/apps/anthropic/v1/",
            ProviderCatalog.defaultAlibabaCodingPlanBaseUrl
        )
    }
}
