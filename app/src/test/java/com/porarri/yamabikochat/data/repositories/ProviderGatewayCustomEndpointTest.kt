package com.porarri.yamabikochat.data.repositories

import com.google.gson.Gson
import com.porarri.yamabikochat.TestLogUtils
import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.data.model.*
import com.porarri.yamabikochat.data.remote.OpenAiCompatPreset
import com.porarri.yamabikochat.pi.PiAgentConfiguration
import com.porarri.yamabikochat.utils.SecurePreferencesManager
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test

class ProviderGatewayCustomEndpointTest {
    @Before fun setup() = TestLogUtils.setup()
    @After fun teardown() = TestLogUtils.tearDown()

    @Test fun customProtocolsKeepExplicitSettingsAndPresetCredential() = runTest {
        for (protocol in listOf("anthropic-messages", "openai-completions", "openai-responses")) {
            val preset = OpenAiCompatPreset("Local", "https://private.example/v1", protocol = protocol,
                modelId = "custom-model", reasoning = true, reasoningEffort = "high", temperature = 0.3)
            val credentials = mockk<SecurePreferencesManager>(relaxed = true)
            every { credentials.getCustomApiKey("Local") } returns "custom-key"
            var captured: PiAgentConfiguration? = null
            val gateway = ProviderGateway(settingsProvider = { Settings(openAiCompatPresets = Gson().toJson(listOf(preset)), selectedOpenAiCompatPreset = "Local") }, securePreferences = credentials,
                piStream = { _, config, _ -> captured = config; flowOf(ProviderStreamEvent.Completed(ProviderResponse(text = "ok"))) })
            gateway.generate(ProviderRequest(model = "custom-model", messages = emptyList()), LLMProvider.OPENAI_COMPAT)
            assertEquals("yamabiko-custom", captured?.provider)
            assertEquals(preset, captured?.customEndpoint)
            assertEquals("custom-key", captured?.apiKey)
            assertEquals("high", captured?.thinkingLevel)
        }
    }

    @Test fun legacyURLOnlyPresetsAreRemovedWithoutAutomaticSelection() {
        val valid = OpenAiCompatPreset("Current", "https://private.example/v1", protocol = "openai-responses", modelId = "custom-model")
        val settings = Settings(openAiCompatPresets = Gson().toJson(listOf(OpenAiCompatPreset("Old", "https://old.example/v1"), valid)), selectedOpenAiCompatPreset = "Old")
        val normalized = settings.normalizedForPersistence()
        assertEquals(listOf(valid), normalized.getOpenAiCompatPresetsList())
        assertNull(normalized.selectedOpenAiCompatPreset)
        assertEquals(normalized, normalized.normalizedForPersistence())
    }

    @Test fun sarashinaUsesDedicatedCredentialForEveryOfficialModel() = runTest {
        val credentials = mockk<SecurePreferencesManager>(relaxed = true)
        every { credentials.readSecret("SARASHINA") } returns "sarashina-key"
        var captured: PiAgentConfiguration? = null
        val gateway = ProviderGateway(settingsProvider = { Settings() }, securePreferences = credentials,
            piStream = { _, config, _ -> captured = config; flowOf(ProviderStreamEvent.Completed(ProviderResponse(text = "ok"))) })
        for (model in listOf("sarashina3-mini", "sarashina3-nano", "sarashina3-guard")) {
            gateway.generate(ProviderRequest(model = model, messages = emptyList()), LLMProvider.SARASHINA)
            assertEquals("sarashina", captured?.provider)
            assertEquals(model, captured?.model)
            assertEquals("sarashina-key", captured?.apiKey)
        }
    }

    @Test fun customEndpointValidationRequiresProtocolAndValidLimits() {
        val preset = OpenAiCompatPreset("Local", "http://localhost:8080/v1", modelId = "custom-model")
        assertNotNull(preset.validationError())
        assertNull(preset.copy(protocol = "openai-completions").validationError())
        assertNotNull(preset.copy(protocol = "anthropic-messages", reasoning = true, reasoningEffort = "high", thinkingBudget = 8192).validationError())
    }
}
