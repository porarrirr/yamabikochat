package com.porarri.yamabikochat.data.auth

import android.content.Context
import com.porarri.yamabikochat.pi.*
import com.porarri.yamabikochat.utils.SecurePreferencesManager
import io.mockk.*
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class CodexAuthRepositoryTest {
    private val secrets = mutableMapOf<String, String>()
    private val prefs = mockk<SecurePreferencesManager> {
        every { readEncryptedSecret(any()) } answers { secrets[firstArg()] }
        every { readSecret(any()) } answers { secrets[firstArg()] }
        every { saveEncryptedSecret(any(), any()) } answers { secrets[firstArg()] = secondArg(); true }
        every { deleteSecret(any()) } answers { secrets.remove(firstArg()); Unit }
    }
    private val runtime = mockk<PiAgentRuntime>()
    private fun repository() = CodexAuthRepository(mockk<Context>(), prefs, runtime)

    @Test
    fun connectedAccountWithoutPlanPermissionCannotExecute() = runBlocking {
        secrets["pi_chatgpt_accounts_v1"] = """{"selectedClientID":"client","registrations":{"client":{"contract":"siwc-v1","clientId":"client","subject":"subject","access":"token","scopes":[]}}}"""
        val repository = repository()
        assertTrue(repository.currentState().isLoggedIn)
        assertFalse(repository.hasAuthToken())
        assertNull(repository.getBearerToken())
        assertTrue(repository.models().isEmpty())
        coVerify(exactly = 0) { runtime.resolveOAuth(any(), any(), any()) }
    }

    @Test
    fun legacyCodexCredentialRequiresReconnectionAndCannotExecute() {
        secrets[CodexAuthRepository.CREDENTIAL_KEY] = "legacy"
        val repository = repository()
        assertTrue(repository.currentState().requiresReauthentication)
        assertFalse(repository.hasAuthToken())
    }

    @Test
    fun officialLoginPersistsRegistrationAndUsesChatGPTProvider() = runBlocking {
        val registration = Json.parseToJsonElement("""{"contract":"siwc-v1","clientId":"client-123","hostId":"host"}""")
        val credential = Json.parseToJsonElement("""{"contract":"siwc-v1","clientId":"client-123","subject":"subject","access":"token","scopes":["chatgpt.tokens.use.direct"]}""")
        coEvery { runtime.loginOAuth(PiOAuthProvider.CHATGPT, PiOAuthLoginMethod.BROWSER, any(), any(), any()) } coAnswers {
            arg<suspend (JsonElement) -> Unit>(4)(registration)
            assertTrue(secrets["pi_chatgpt_accounts_v1"]!!.contains("client-123"))
            PiOAuthResolution(credential, "token", profile = PiOAuthProfile())
        }
        val repository = repository()
        assertTrue(repository.loginWithBrowser().isSuccess)
        assertTrue(repository.hasAuthToken())
        assertEquals("client-123", repository.currentState().savedAccounts.single().clientID)
        coEvery { runtime.revokeChatGPT(any()) } returns Unit
        assertTrue(repository.logout().isSuccess)
        assertFalse(repository.hasAuthToken())
        assertFalse(secrets["pi_chatgpt_accounts_v1"]!!.contains("token"))
        assertEquals("client-123", repository.currentState().savedAccounts.single().clientID)
    }
}
