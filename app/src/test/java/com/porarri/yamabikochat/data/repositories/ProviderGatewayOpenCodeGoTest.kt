package com.porarri.yamabikochat.data.repositories

import com.porarri.yamabikochat.TestLogUtils
import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.data.model.ProviderRequest
import com.porarri.yamabikochat.data.model.ProviderRequestMessage
import com.porarri.yamabikochat.data.model.ProviderResponse
import com.porarri.yamabikochat.data.model.ProviderStreamEvent
import com.porarri.yamabikochat.data.model.ProviderThinkingConfig
import com.porarri.yamabikochat.data.modelsdev.CatalogLimits
import com.porarri.yamabikochat.data.modelsdev.CatalogModel
import com.porarri.yamabikochat.data.modelsdev.CatalogModelProviderContract
import com.porarri.yamabikochat.data.modelsdev.CatalogProvider
import com.porarri.yamabikochat.data.modelsdev.ModelsDevCatalogRepository
import com.porarri.yamabikochat.pi.PiAgentConfiguration
import com.porarri.yamabikochat.utils.SecurePreferencesManager
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Test

class ProviderGatewayOpenCodeGoTest {
    @Before
    fun setUp() = TestLogUtils.setup()

    @After
    fun tearDown() = TestLogUtils.tearDown()

    @Test
    fun modelsDevMuseSparkUsesOfficialResponsesRoute() = runTest {
        val provider = CatalogProvider(
            id = "opencode-go",
            name = "OpenCode Go",
            npm = "@ai-sdk/openai-compatible",
            api = "https://opencode.ai/zen/go/v1",
            env = listOf("OPENCODE_API_KEY"),
            models = listOf(
                CatalogModel(
                    id = "muse-spark-1.2-contributor",
                    name = "Muse Spark 1.2 Contributor",
                    attachment = true,
                    reasoning = true,
                    toolCall = true,
                    outputModalities = listOf("text"),
                    limits = CatalogLimits(context = 1_048_576, output = 32_768),
                    providerContract = CatalogModelProviderContract(
                        npm = "@ai-sdk/openai",
                        shape = "responses",
                        provenance = "model"
                    )
                )
            )
        )
        val catalog = mockk<ModelsDevCatalogRepository>()
        every { catalog.provider(any()) } returns provider
        val credentials = mockk<SecurePreferencesManager>(relaxed = true)
        every { credentials.readSecret("models_dev_opencode-go_OPENCODE_API_KEY") } returns "test-key"
        var captured: PiAgentConfiguration? = null
        val gateway = ProviderGateway(
            settingsProvider = { Settings() },
            securePreferences = credentials,
            modelsDevCatalogRepository = catalog,
            piStream = { _, configuration, _ ->
                captured = configuration
                flowOf(ProviderStreamEvent.Completed(ProviderResponse(text = "ok")))
            }
        )

        gateway.stream(
            ProviderRequest(
                model = "muse-spark-1.2-contributor",
                messages = listOf(ProviderRequestMessage(role = "user", content = "hello"))
            ),
            "MODELS_DEV:OPENCODE-GO"
        )

        assertEquals("opencode-go", captured?.provider)
        assertEquals("muse-spark-1.2-contributor", captured?.model)
        assertEquals("@ai-sdk/openai", captured?.catalogContract?.npm)
        assertEquals(null, captured?.catalogContract?.api)
        assertEquals("responses", captured?.catalogContract?.shape)
        assertEquals("model", captured?.catalogContract?.provenance)
        assertEquals(true, captured?.catalogContract?.toolCall)
    }

    @Test
    fun modelsDevMuseSparkPassesReasoningEffortAsThinkingLevel() = runTest {
        val provider = CatalogProvider(
            id = "opencode-go",
            name = "OpenCode Go",
            npm = "@ai-sdk/openai-compatible",
            api = "https://opencode.ai/zen/go/v1",
            env = listOf("OPENCODE_API_KEY"),
            models = listOf(
                CatalogModel(
                    id = "muse-spark-1.2-contributor",
                    name = "Muse Spark 1.2 Contributor",
                    attachment = true,
                    reasoning = true,
                    toolCall = true,
                    outputModalities = listOf("text"),
                    limits = CatalogLimits(context = 1_048_576, output = 32_768),
                    providerContract = CatalogModelProviderContract(
                        npm = "@ai-sdk/openai",
                        shape = "responses",
                        provenance = "model"
                    )
                )
            )
        )
        val catalog = mockk<ModelsDevCatalogRepository>()
        every { catalog.provider(any()) } returns provider
        val credentials = mockk<SecurePreferencesManager>(relaxed = true)
        every { credentials.readSecret("models_dev_opencode-go_OPENCODE_API_KEY") } returns "test-key"
        var captured: PiAgentConfiguration? = null
        val gateway = ProviderGateway(
            settingsProvider = { Settings() },
            securePreferences = credentials,
            modelsDevCatalogRepository = catalog,
            piStream = { _, configuration, _ ->
                captured = configuration
                flowOf(ProviderStreamEvent.Completed(ProviderResponse(text = "ok")))
            }
        )

        gateway.stream(
            ProviderRequest(
                model = "muse-spark-1.2-contributor",
                messages = listOf(ProviderRequestMessage(role = "user", content = "hello")),
                thinking = ProviderThinkingConfig(effort = "medium")
            ),
            "MODELS_DEV:OPENCODE-GO"
        )

        assertEquals("opencode-go", captured?.provider)
        assertEquals("muse-spark-1.2-contributor", captured?.model)
        assertEquals("medium", captured?.thinkingLevel)
    }
}
