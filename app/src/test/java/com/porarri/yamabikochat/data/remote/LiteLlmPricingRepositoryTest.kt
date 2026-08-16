package com.porarri.yamabikochat.data.remote

import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class LiteLlmPricingRepositoryTest {

    private val repository = LiteLlmPricingRepository(apiService = DummyLiteLlmApi())

    @Test
    fun parseCatalogReadsSupportsVisionAndSkipsSampleSpec() {
        val root = buildJsonObject {
            put("sample_spec", buildJsonObject { put("input_cost_per_token", 1.0) })
            put("openai/gpt-4o", buildJsonObject {
                put("input_cost_per_token", 0.0000025)
                put("output_cost_per_token", 0.00001)
                put("supports_vision", true)
            })
            put("openai/o1-mini", buildJsonObject {
                put("input_cost_per_token", 0.000003)
                put("supports_vision", false)
            })
            put("vision-only/model", buildJsonObject {
                put("supports_vision", true)
            })
        }

        val parsed = repository.parseCatalog(root)
        assertFalse(parsed.catalog.containsKey("sample_spec"))
        assertEquals(true, parsed.catalog["openai/gpt-4o"]?.supportsVision)
        assertEquals(false, parsed.catalog["openai/o1-mini"]?.supportsVision)
        assertEquals(true, parsed.catalog["vision-only/model"]?.supportsVision)
        assertEquals(true, parsed.visionByBasename["gpt-4o"])
        assertFalse(parsed.visionByBasename.containsKey("o1-mini"))
    }

    @Test
    fun modelSupportsVisionUsesCatalogThenSuperGrokFallback() = runBlocking {
        repository.replaceCatalogForTests(
            catalog = mapOf(
                "openai/gpt-4o" to LiteLlmModelCatalogEntry(
                    price = LiteLlmModelPrice(0.1, 0.2, null),
                    supportsVision = true
                )
            )
        )

        assertTrue(repository.modelSupportsVision("OPENAI", "gpt-4o"))
        assertTrue(repository.modelSupportsVision("SUPERGROK", "grok-4.5"))
        assertFalse(repository.modelSupportsVision("SUPERGROK", "grok-build-0.1"))
    }

    @Test
    fun modelSupportsVisionIsFalseWhenCatalogEmpty() = runBlocking {
        repository.replaceCatalogForTests(catalog = emptyMap())
        assertFalse(repository.modelSupportsVision("SUPERGROK", "grok-4.5"))
        assertFalse(repository.modelSupportsVision("OPENAI", "gpt-4o"))
    }

    private class DummyLiteLlmApi : LiteLlmPricingApiService {
        override suspend fun getModelPriceCatalog() =
            throw UnsupportedOperationException("network should not be used in this test")
    }
}
