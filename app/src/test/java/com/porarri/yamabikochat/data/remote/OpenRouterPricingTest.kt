package com.porarri.yamabikochat.data.remote

import org.junit.Assert.assertEquals
import org.junit.Test

class OpenRouterPricingTest {
    @Test
    fun `SimpleModel converts per-token to per-million correctly`() {
        val model = OpenRouterModel(
            id = "openai/gpt-4o",
            name = "GPT-4o",
            pricing = ModelPricing(
                prompt = "0.0000020",        // $2.00 per 1M
                completion = "0.0000100"     // $10.00 per 1M
            ),
            contextLength = 128000,
            architecture = null,
            topProvider = null,
            created = null
        )

        val simple = SimpleModel.fromOpenRouterModel(model)
        assertEquals(2.0, simple.promptPricePerMillion, 1e-6)
        assertEquals(10.0, simple.completionPricePerMillion, 1e-6)

        // Back-compat helpers (per-token)
        assertEquals(0.000002, simple.promptPrice, 1e-12)
        assertEquals(0.00001, simple.completionPrice, 1e-12)
    }

    @Test
    fun `SimpleModel falls back to completion price when prompt missing`() {
        val model = OpenRouterModel(
            id = "openrouter/phi-3",
            name = "Phi-3",
            pricing = ModelPricing(
                completion = "0.0000015"     // $1.50 per 1M, prompt omitted by API
            ),
            contextLength = 128000,
            architecture = null,
            topProvider = null,
            created = null
        )

        val simple = SimpleModel.fromOpenRouterModel(model)
        assertEquals(1.5, simple.promptPricePerMillion, 1e-6)
        assertEquals(1.5, simple.completionPricePerMillion, 1e-6)
    }

    @Test
    fun `SimpleModel falls back to request price when completion missing`() {
        val model = OpenRouterModel(
            id = "openrouter/some-model",
            name = "Some Model",
            pricing = ModelPricing(
                request = "0.0000008"        // $0.80 per 1M, only request field provided
            ),
            contextLength = 32000,
            architecture = null,
            topProvider = null,
            created = null
        )

        val simple = SimpleModel.fromOpenRouterModel(model)
        assertEquals(0.8, simple.promptPricePerMillion, 1e-6)
        assertEquals(0.8, simple.completionPricePerMillion, 1e-6)
    }
}
