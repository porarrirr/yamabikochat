package com.porarri.yamabikochat.data.modelsdev

import android.content.Context
import android.content.SharedPreferences
import com.porarri.yamabikochat.data.remote.OpenAiProvider
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.nio.file.Files

class ModelsDevCatalogTest {
    @Test
    fun parserExcludesOpenRouterDeprecatedAndNonTextModels() {
        val directory = Files.createTempDirectory("models-dev-test").toFile()
        val preferences = mockk<SharedPreferences>(relaxed = true)
        val context = mockk<Context> {
            every { filesDir } returns directory
            every { getSharedPreferences(any(), any()) } returns preferences
        }
        val repository = ModelsDevCatalogRepository(context)

        val providers = repository.parseCatalog(FIXTURE)

        assertEquals(listOf("example"), providers.map { it.id })
        assertEquals(listOf("chat"), providers.single().models.map { it.id })
        assertTrue(providers.single().models.single().toolCall)
        assertEquals(listOf("low", "high"), providers.single().models.single().supportedReasoningEfforts)
    }

    @Test
    fun savedReasoningEffortKeepsPreferenceVisibleWhenCatalogOptionsDisappear() {
        val model = CatalogModel(id = "reasoner", name = "Reasoner")

        assertTrue(model.shouldShowReasoningEffortPreference("high"))
        assertFalse(model.shouldShowReasoningEffortPreference(""))
    }

    @Test
    fun allCurrentNpmKindsResolveWithoutUnverifiedCompatibility() {
        CURRENT_NPM_KINDS.forEach { npm ->
            val provider = CatalogProvider(
                id = "fixture", name = "Fixture", npm = npm,
                models = listOf(CatalogModel(id = "chat", name = "Chat", outputModalities = listOf("text")))
            )
            assertTrue("npm kind must be mapped: $npm", ModelsDevProviderAdapterRegistry.profile(provider).isVerifiedMapping)
        }
        assertFalse(ModelsDevProviderAdapterRegistry.profile(
            CatalogProvider(id = "future", name = "Future", npm = "future-sdk", api = "https://example.com/v1", models = listOf(CatalogModel("m", "M")))
        ).isVerifiedMapping)
    }

    @Test
    fun providerReferenceRoundTripsWithoutDefaultingToGemini() {
        val reference = ProviderReference.modelsDev("Acme")
        assertEquals("MODELS_DEV:acme", reference.persistedId)
        assertEquals("acme", ProviderReference(reference.persistedId).modelsDevId)
        assertFalse(ProviderReference("UNKNOWN_PROVIDER").isModelsDev)
    }

    @Test
    fun builtInProvidersDoNotMergeWithDifferentProductsOrProtocols() {
        assertEquals(null, ModelsDevMergedProvider.catalogIdFor("OPENCODE_GO"))
        assertEquals(null, ModelsDevMergedProvider.catalogIdFor("ALIBABA_CODING_PLAN"))
        assertEquals(null, ModelsDevMergedProvider.catalogIdFor("MINIMAX"))
        assertEquals(null, ModelsDevMergedProvider.catalogIdFor("ZAI"))
        assertEquals("opencode", ModelsDevMergedProvider.catalogIdFor("MODELS_DEV:opencode"))
        assertEquals("zai", ModelsDevMergedProvider.catalogIdFor("MODELS_DEV:zai"))
    }

    @Test
    fun providerOrLoadHydratesFreshDiskCacheBeforeResolvingProvider() = runBlocking {
        val directory = Files.createTempDirectory("models-dev-cache-test").toFile()
        directory.resolve("models_dev_catalog_cache.json").writeText(
            """[{"id":"example","name":"Example","npm":"@ai-sdk/openai-compatible","models":[{"id":"chat","name":"Chat"}]}]"""
        )
        val preferences = mockk<SharedPreferences>(relaxed = true) {
            every { getLong("fetched_at", 0L) } returns 1_000L
        }
        val context = mockk<Context> {
            every { filesDir } returns directory
            every { getSharedPreferences(any(), any()) } returns preferences
        }
        val repository = ModelsDevCatalogRepository(context, now = { 1_000L })

        val provider = repository.providerOrLoad(ProviderReference.modelsDev("example"))

        assertEquals("example", provider?.id)
        assertEquals(CatalogAvailability.READY, repository.state.value.availability)
    }

    @Test
    fun openAiCompatibleModelNamespaceCanBePreserved() {
        val provider = OpenAiProvider { error("service must not be created") }

        assertEquals("openai/gpt-oss-120b", provider.normalizeOpenAiModel(" openai/gpt-oss-120b ", false))
        assertEquals("gpt-oss-120b", provider.normalizeOpenAiModel("openai/gpt-oss-120b", true))
    }

    private companion object {
        val CURRENT_NPM_KINDS = listOf(
            "@ai-sdk/amazon-bedrock", "@ai-sdk/anthropic", "@ai-sdk/azure", "@ai-sdk/cerebras",
            "@ai-sdk/cohere", "@ai-sdk/deepinfra", "@ai-sdk/gateway", "@ai-sdk/google",
            "@ai-sdk/google-vertex", "@ai-sdk/google-vertex/anthropic", "@ai-sdk/groq",
            "@ai-sdk/mistral", "@ai-sdk/openai", "@ai-sdk/openai-compatible", "@ai-sdk/perplexity",
            "@ai-sdk/togetherai", "@ai-sdk/vercel", "@ai-sdk/xai", "@aihubmix/ai-sdk-provider",
            "@jerome-benoit/sap-ai-provider-v2", "@qvac/ai-sdk-provider", "ai-gateway-provider",
            "gitlab-ai-provider", "merge-gateway-ai-sdk-provider", "venice-ai-sdk-provider"
        )

        val FIXTURE = """
            {"providers":{
              "openrouter":{"name":"OpenRouter","npm":"@ai-sdk/openai-compatible","models":{"or":{"name":"OR","modalities":{"output":["text"]}}}},
              "example":{"name":"Example","npm":"@ai-sdk/openai-compatible","env":["EXAMPLE_API_KEY"],"models":{
                "chat":{"name":"Chat","tool_call":true,"reasoning":true,"reasoning_options":[{"type":"effort","values":["low","high"]}],"modalities":{"input":["text"],"output":["text"]}},
                "old":{"name":"Old","status":"deprecated","modalities":{"output":["text"]}},
                "image":{"name":"Image","modalities":{"output":["image"]}}
              }}
            }}
        """.trimIndent()
    }
}
