package com.porarri.yamabikochat.data.auth

import android.content.Context
import com.porarri.yamabikochat.pi.PiAgentRuntime
import com.porarri.yamabikochat.pi.PiOAuthLoginMethod
import com.porarri.yamabikochat.pi.PiOAuthProvider
import com.porarri.yamabikochat.pi.PiOAuthResolution
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import com.porarri.yamabikochat.utils.SecurePreferencesManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import java.time.Instant

class SuperGrokAuthRepository(
    private val context: Context,
    private val securePrefs: SecurePreferencesManager = SecurePreferencesManager.getInstance(context),
    private val piRuntime: PiAgentRuntime = PiAgentRuntime.getInstance(context)
) {
    data class BearerToken(
        val token: String
    )

    companion object {
        const val CREDENTIAL_KEY = "pi_oauth_supergrok_v1"
    }

    private val _state = MutableStateFlow(readState())
    val state: StateFlow<SuperGrokAuthState> = _state.asStateFlow()

    fun currentState(): SuperGrokAuthState = _state.value

    suspend fun loginWithBrowser(): Result<SuperGrokAuthState> = login(PiOAuthLoginMethod.BROWSER)

    suspend fun loginWithDeviceCode(): Result<SuperGrokAuthState> = login(PiOAuthLoginMethod.DEVICE)

    private suspend fun login(method: PiOAuthLoginMethod): Result<SuperGrokAuthState> = withContext(Dispatchers.IO) {
        runCatching {
            DiagnosticsLogger.log("SuperGrok auth delegated to pi-grok")
            val resolution = piRuntime.loginOAuth(
                provider = PiOAuthProvider.SUPERGROK,
                method = method,
                onDeviceCode = { challenge ->
                    _state.value = _state.value.copy(
                        pendingDeviceCode = SuperGrokDeviceCodeChallenge(
                            verificationUri = challenge.verificationURI,
                            userCode = challenge.userCode,
                            browserUrl = challenge.browserURL
                        )
                    )
                }
            )
            persist(resolution)
            val updated = readState()
            _state.value = updated
            DiagnosticsLogger.log("pi-grok login succeeded email=${updated.email}")
            updated
        }.onFailure { err ->
            _state.value = readState().copy(pendingDeviceCode = null)
            DiagnosticsLogger.log("pi-grok login failed", err)
        }
    }

    suspend fun logout(): Result<SuperGrokAuthState> = withContext(Dispatchers.IO) {
        runCatching {
            listOf(
                CREDENTIAL_KEY,
                "supergrok_email",
                "supergrok_last_refresh",
                "supergrok_auth_json_v1",
                "supergrok_access_token"
            ).forEach { key ->
                securePrefs.deleteSecret(key)
            }
            val updated = readState()
            _state.value = updated
            DiagnosticsLogger.log("SuperGrok auth logout completed")
            updated
        }
    }

    suspend fun refreshIfNeeded(force: Boolean = false): Result<SuperGrokAuthState> = withContext(Dispatchers.IO) {
        runCatching {
            val credential = securePrefs.readSecret(CREDENTIAL_KEY)?.takeIf { it.isNotBlank() }
                ?: return@withContext Result.success(readState()).also { _state.value = readState() }
            val resolution = piRuntime.resolveOAuth(PiOAuthProvider.SUPERGROK, credential, force)
            persist(resolution)
            val updated = readState()
            _state.value = updated
            DiagnosticsLogger.log("pi-grok refresh completed")
            updated
        }.onFailure { err ->
            DiagnosticsLogger.log("pi-grok token refresh failed", err)
        }
    }

    fun hasAuthToken(): Boolean {
        return !securePrefs.readSecret(CREDENTIAL_KEY).isNullOrBlank()
    }

    suspend fun getBearerToken(): BearerToken? = withContext(Dispatchers.IO) {
        val credential = securePrefs.readSecret(CREDENTIAL_KEY)?.takeIf { it.isNotBlank() } ?: return@withContext null
        try {
            val resolution = piRuntime.resolveOAuth(PiOAuthProvider.SUPERGROK, credential, false)
            persist(resolution)
            _state.value = readState()
            BearerToken(token = resolution.accessToken)
        } catch (e: Exception) {
            DiagnosticsLogger.log("pi-grok credential resolution failed", e)
            null
        }
    }

    private fun persist(resolution: PiOAuthResolution) {
        securePrefs.saveSecret(CREDENTIAL_KEY, PiAgentRuntime.credentialJSONString(resolution.credential))
        securePrefs.saveSecret("supergrok_email", resolution.profile.email)
        securePrefs.saveSecret("supergrok_last_refresh", Instant.now().toString())
        securePrefs.deleteSecret("supergrok_auth_json_v1")
        securePrefs.deleteSecret("supergrok_access_token")
    }

    private fun readState(): SuperGrokAuthState {
        val credential = securePrefs.readSecret(CREDENTIAL_KEY)
        return SuperGrokAuthState(
            isLoggedIn = !credential.isNullOrBlank(),
            email = securePrefs.readSecret("supergrok_email"),
            lastRefreshIso8601 = securePrefs.readSecret("supergrok_last_refresh"),
            pendingDeviceCode = null
        )
    }
}