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
                "SUPERGROK",
                "CLINEPASS",
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
        assertEquals(SuperGrokModelCatalog.defaultModel, ProviderCatalog.defaultModel("SUPERGROK"))
        assertEquals(ClinePassModelCatalog.defaultModel, ProviderCatalog.defaultModel("CLINEPASS"))
        assertEquals(
            AlibabaCodingPlanModelCatalog.defaultModel,
            ProviderCatalog.defaultModel("ALIBABA_CODING_PLAN")
        )
        assertTrue(OpenCodeGoModelCatalog.modelFor("opencode-go/qwen3.7-max")?.endpointKind == OpenCodeGoEndpointKind.MESSAGES)
        assertEquals(
            "cline-pass/glm-5.2",
            ClinePassModelCatalog.modelFor("glm-5.2")?.id
        )
        assertEquals("cline-pass/kimi-k3", ClinePassModelCatalog.modelFor("cline-pass/kimi-k3")?.id)
        assertEquals("glm-5.2", ProviderCatalog.defaultModel("ZAI"))
        assertEquals(
            listOf("glm-5.2", "glm-5-turbo", "glm-4.7"),
            ZaiCodingPlanModelCatalog.supportedModels
        )
        assertEquals("glm-5.2", ProviderCatalog.migrateLegacyModelId("ZAI", "glm-5.1"))
        assertEquals("glm-5.1", ProviderCatalog.migrateLegacyModelId("OPENCODE_GO", "glm-5.1"))
        assertTrue(AlibabaCodingPlanModelCatalog.supportedModels.contains("qwen3.7-plus"))
        assertTrue(OpenCodeGoModelCatalog.modelFor("qwen3.8-max")?.endpointKind == OpenCodeGoEndpointKind.MESSAGES)
        assertEquals(
            "muse-spark-1.2-contributor",
            OpenCodeGoModelCatalog.modelFor("muse-spark-1.2")?.id
        )
        assertTrue(OpenCodeGoModelCatalog.modelFor("muse-spark-1.2")?.endpointKind == OpenCodeGoEndpointKind.RESPONSES)
    }

    @Test
    fun alibabaCodingPlanBaseUrlTargetsAnthropicV1Messages() {
        assertEquals(
            "https://coding-intl.dashscope.aliyuncs.com/apps/anthropic/v1/",
            ProviderCatalog.defaultAlibabaCodingPlanBaseUrl
        )
    }

    @Test
    fun zaiDisplayNameIdentifiesCodingPlanEndpointContract() {
        assertEquals("Z.ai Coding Plan", ProviderCatalog.displayName("ZAI"))
    }
}
