package com.porarri.yamabikochat.data.repositories

import com.porarri.yamabikochat.data.auth.CodexAuthRepository
import com.porarri.yamabikochat.data.auth.CodexBearerToken
import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.data.model.*
import com.porarri.yamabikochat.pi.PiAgentConfiguration
import com.porarri.yamabikochat.utils.SecurePreferencesManager
import io.mockk.*
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.test.runTest
import org.junit.Assert.*
import org.junit.Test

class ProviderGatewayChatGPTTest {
    @Test
    fun chatGPTPlanUsesOfficialPiProviderWithoutCodexHeaders() = runTest {
        val auth = mockk<CodexAuthRepository>()
        coEvery { auth.getBearerToken() } returns CodexBearerToken("official-token", accountId = "client-id")
        var captured: PiAgentConfiguration? = null
        val gateway = ProviderGateway(
            settingsProvider = { Settings() },
            securePreferences = mockk<SecurePreferencesManager>(relaxed = true),
            codexAuthRepository = auth,
            piStream = { _, config, _ ->
                captured = config
                flowOf(ProviderStreamEvent.Completed(ProviderResponse(text = "ok")))
            }
        )
        gateway.stream(ProviderRequest(model = "gpt-6-sol", messages = listOf(ProviderRequestMessage(role = "user", content = "hello"))), "CODEX_AUTH")
        assertEquals("openai-chatgpt", captured?.provider)
        assertEquals("official-token", captured?.apiKey)
        assertFalse(captured?.headers.orEmpty().containsKey("ChatGPT-Account-ID"))
        assertFalse(captured?.headers.orEmpty().containsKey("originator"))
    }
}
