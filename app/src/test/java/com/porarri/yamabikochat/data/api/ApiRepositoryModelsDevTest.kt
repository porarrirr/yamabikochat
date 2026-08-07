package com.porarri.yamabikochat.data.api

import android.util.Log
import com.porarri.yamabikochat.data.auth.CodexAuthRepository
import com.porarri.yamabikochat.data.auth.SuperGrokAuthRepository
import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.data.local.Settings.ReasoningContext
import com.porarri.yamabikochat.data.local.SettingsManager
import com.porarri.yamabikochat.data.model.ModelRepository
import com.porarri.yamabikochat.data.modelsdev.CatalogModel
import com.porarri.yamabikochat.data.modelsdev.CatalogProvider
import com.porarri.yamabikochat.data.modelsdev.CatalogReasoningOption
import com.porarri.yamabikochat.data.modelsdev.ModelsDevReasoningPreference
import com.porarri.yamabikochat.data.modelsdev.ModelsDevCatalogRepository
import com.porarri.yamabikochat.data.remote.AlibabaCodingPlanProvider
import com.porarri.yamabikochat.data.remote.AnthropicCompatibleProvider
import com.porarri.yamabikochat.data.remote.CodexResponsesProvider
import com.porarri.yamabikochat.data.remote.Content
import com.porarri.yamabikochat.data.remote.GenerateContentRequest
import com.porarri.yamabikochat.data.remote.GenerateContentResponse
import com.porarri.yamabikochat.data.remote.GeminiProvider
import com.porarri.yamabikochat.data.remote.OpenAiProvider
import com.porarri.yamabikochat.data.remote.OpenCodeGoProvider
import com.porarri.yamabikochat.data.remote.OpenRouterProvider
import com.porarri.yamabikochat.data.remote.Part
import com.porarri.yamabikochat.data.remote.ZaiProvider
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.mockk.mockkStatic
import io.mockk.unmockkStatic
import io.mockk.verify
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import retrofit2.Response

class ApiRepositoryModelsDevTest {
    private val settingsManager = mockk<SettingsManager>(relaxed = true)
    private val openAiProvider = mockk<OpenAiProvider>(relaxed = true)
    private val anthropicProvider = mockk<AnthropicCompatibleProvider>(relaxed = true)
    private val catalogRepository = mockk<ModelsDevCatalogRepository>(relaxed = true)

    private val repository = ApiRepository(
        geminiProvider = mockk<GeminiProvider>(relaxed = true),
        openRouterProvider = mockk<OpenRouterProvider>(relaxed = true),
        openAiProvider = openAiProvider,
        openCodeGoProvider = mockk<OpenCodeGoProvider>(relaxed = true),
        alibabaCodingPlanProvider = mockk<AlibabaCodingPlanProvider>(relaxed = true),
        anthropicCompatibleProvider = anthropicProvider,
        codexResponsesProvider = mockk<CodexResponsesProvider>(relaxed = true),
        zaiProvider = mockk<ZaiProvider>(relaxed = true),
        settingsManager = settingsManager,
        codexAuthRepository = mockk<CodexAuthRepository>(relaxed = true),
        superGrokAuthRepository = mockk<SuperGrokAuthRepository>(relaxed = true),
        modelRepository = mockk<ModelRepository>(relaxed = true),
        modelsDevCatalogRepository = catalogRepository,
        settingsProvider = { Settings() }
    )

    @Before
    fun mockAndroidLog() {
        mockkStatic(Log::class)
        every { Log.d(any(), any()) } returns 0
    }

    @After
    fun restoreAndroidLog() {
        unmockkStatic(Log::class)
    }

    @Test
    fun autoConversationUsesModelsDevCredentialWithoutRequiringGeminiKey() = runBlocking {
        val provider = catalogProvider(
            id = "example",
            npm = "@ai-sdk/openai-compatible",
            api = "https://example.com/v1",
            env = listOf("EXAMPLE_API_KEY")
        )
        coEvery { catalogRepository.providerOrLoad(any()) } returns provider
        every { settingsManager.getModelsDevField("example", "EXAMPLE_API_KEY") } returns "dynamic-key"
        coEvery {
            openAiProvider.generateContent(any(), any(), any(), any(), any(), any(), any(), any(), any())
        } returns Response.success(GenerateContentResponse(text = "ok"))

        val response = repository.generateAutoConversationResponse(
            model = "openai/gpt-oss-120b",
            provider = "MODELS_DEV:example",
            systemPrompt = "system",
            conversationHistory = listOf(Content(role = "user", parts = listOf(Part(text = "hello")))),
            reasoningContext = ReasoningContext.AUTO_A
        )

        assertTrue(response.isSuccessful)
        verify(exactly = 0) { settingsManager.getApiKey("GEMINI") }
        coVerify {
            openAiProvider.generateContent(
                "dynamic-key", "openai/gpt-oss-120b", any(), "https://example.com/v1",
                null, false, false, false, null
            )
        }
    }

    @Test
    fun modelsDevReasoningEffortIsPassedToOpenAiCompatibleWireAdapter() = runBlocking {
        val modelId = "openai/gpt-oss-120b"
        val provider = catalogProvider(
            id = "example",
            npm = "@ai-sdk/openai-compatible",
            api = "https://example.com/v1",
            env = listOf("EXAMPLE_API_KEY"),
            reasoningOptions = listOf(CatalogReasoningOption("effort", listOf("low", "high")))
        )
        coEvery { catalogRepository.providerOrLoad(any()) } returns provider
        every { settingsManager.getModelsDevField("example", "EXAMPLE_API_KEY") } returns "dynamic-key"
        every {
            settingsManager.getModelsDevField(
                "example",
                ModelsDevReasoningPreference.fieldName(modelId)
            )
        } returns "high"
        coEvery {
            openAiProvider.generateContent(any(), any(), any(), any(), any(), any(), any(), any(), any())
        } returns Response.success(GenerateContentResponse(text = "ok"))

        val response = repository.generateContent(
            model = modelId,
            request = GenerateContentRequest(listOf(Content(role = "user", parts = listOf(Part(text = "hello"))))),
            providerOverride = "MODELS_DEV:example"
        )

        assertTrue(response.isSuccessful)
        coVerify {
            openAiProvider.generateContent(
                "dynamic-key", modelId, any(), "https://example.com/v1",
                null, false, false, false, "high"
            )
        }
    }

    @Test
    fun unsupportedSavedReasoningEffortStopsBeforeProviderRequest() = runBlocking {
        val modelId = "openai/gpt-oss-120b"
        val provider = catalogProvider(
            id = "example",
            npm = "@ai-sdk/openai-compatible",
            api = "https://example.com/v1",
            env = listOf("EXAMPLE_API_KEY"),
            reasoningOptions = listOf(CatalogReasoningOption("effort", listOf("low", "high")))
        )
        coEvery { catalogRepository.providerOrLoad(any()) } returns provider
        every { settingsManager.getModelsDevField("example", "EXAMPLE_API_KEY") } returns "dynamic-key"
        every {
            settingsManager.getModelsDevField(
                "example",
                ModelsDevReasoningPreference.fieldName(modelId)
            )
        } returns "ultra"

        val response = repository.generateContent(
            model = modelId,
            request = GenerateContentRequest(listOf(Content(role = "user", parts = listOf(Part(text = "hello"))))),
            providerOverride = "MODELS_DEV:example"
        )

        assertEquals(400, response.code())
        coVerify(exactly = 0) {
            openAiProvider.generateContent(any(), any(), any(), any(), any(), any(), any(), any(), any())
        }
    }

    @Test
    fun officialAnthropicModelsDevProviderUsesV1MessagesBaseUrl() = runBlocking {
        val provider = catalogProvider(
            id = "anthropic",
            npm = "@ai-sdk/anthropic",
            api = null,
            env = listOf("ANTHROPIC_API_KEY")
        )
        coEvery { catalogRepository.providerOrLoad(any()) } returns provider
        every { settingsManager.getModelsDevField("anthropic", "ANTHROPIC_API_KEY") } returns "anthropic-key"
        coEvery {
            anthropicProvider.generateContent(any(), any(), any(), any(), any(), any(), any())
        } returns Response.success(GenerateContentResponse(text = "ok"))

        val response = repository.generateContent(
            model = "claude-test",
            request = GenerateContentRequest(listOf(Content(role = "user", parts = listOf(Part(text = "hello"))))),
            providerOverride = "MODELS_DEV:anthropic"
        )

        assertTrue(response.isSuccessful)
        coVerify {
            anthropicProvider.generateContent(
                "anthropic-key", "claude-test", any(), "https://api.anthropic.com/v1/", "Anthropic", null, null
            )
        }
    }

    private fun catalogProvider(
        id: String,
        npm: String,
        api: String?,
        env: List<String>,
        reasoningOptions: List<CatalogReasoningOption> = emptyList()
    ) = CatalogProvider(
        id = id,
        name = id.replaceFirstChar { it.uppercase() },
        npm = npm,
        api = api,
        env = env,
        models = listOf(CatalogModel(
            id = if (id == "anthropic") "claude-test" else "openai/gpt-oss-120b",
            name = "Model",
            reasoning = reasoningOptions.isNotEmpty(),
            reasoningOptions = reasoningOptions
        ))
    )
}
