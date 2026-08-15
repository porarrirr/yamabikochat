package com.porarri.yamabikochat.data.auth

import android.content.Context
import com.porarri.yamabikochat.data.model.ProviderClientError
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
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.time.Instant
import java.util.concurrent.TimeUnit

class CodexAuthRepository(
    private val context: Context,
    private val securePrefs: SecurePreferencesManager = SecurePreferencesManager.getInstance(context),
    private val piRuntime: PiAgentRuntime = PiAgentRuntime.getInstance(context),
    private val httpClient: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .build()
) {
    companion object {
        const val CREDENTIAL_KEY = "codex_auth_json"
        const val USAGE_URL = "https://chatgpt.com/backend-api/wham/usage"
        const val ORIGINATOR = "codex_cli_rs"
    }

    private val _state = MutableStateFlow(readState())
    val state: StateFlow<CodexAuthState> = _state.asStateFlow()

    fun currentState(): CodexAuthState = _state.value

    suspend fun loginWithBrowser(): Result<CodexAuthState> = withContext(Dispatchers.IO) {
        runCatching {
            DiagnosticsLogger.log("Codex auth delegated to Pi")
            val resolution = piRuntime.loginOAuth(PiOAuthProvider.CODEX, PiOAuthLoginMethod.BROWSER)
            persist(resolution)
            val updated = readState()
            _state.value = updated
            DiagnosticsLogger.log("Pi Codex auth login completed email=${updated.email}")
            updated
        }.onFailure { err ->
            DiagnosticsLogger.log("Pi Codex auth login failed", err)
        }
    }

    suspend fun logout(): Result<CodexAuthState> = withContext(Dispatchers.IO) {
        runCatching {
            listOf(
                CREDENTIAL_KEY,
                "codex_email",
                "codex_plan_type",
                "codex_account_id",
                "codex_last_refresh",
                "codex_auth_json_v2",
                "codex_access_token"
            ).forEach { key ->
                securePrefs.deleteSecret(key)
            }
            val updated = readState()
            _state.value = updated
            DiagnosticsLogger.log("Codex auth logout completed")
            updated
        }
    }

    suspend fun refreshIfNeeded(force: Boolean = false): Result<CodexAuthState> = withContext(Dispatchers.IO) {
        runCatching {
            val credential = securePrefs.readSecret(CREDENTIAL_KEY)?.takeIf { it.isNotBlank() }
                ?: return@withContext Result.success(readState()).also { _state.value = readState() }
            val resolution = piRuntime.resolveOAuth(PiOAuthProvider.CODEX, credential, force)
            persist(resolution)
            val updated = readState()
            _state.value = updated
            DiagnosticsLogger.log("Pi Codex auth refresh completed")
            updated
        }.onFailure { err ->
            DiagnosticsLogger.log("Pi Codex auth refresh failed", err)
        }
    }

    fun hasAuthToken(): Boolean {
        return !securePrefs.readSecret(CREDENTIAL_KEY).isNullOrBlank()
    }

    suspend fun getApiKey(): String? = null

    suspend fun getBearerToken(): CodexBearerToken? = withContext(Dispatchers.IO) {
        val credential = securePrefs.readSecret(CREDENTIAL_KEY)?.takeIf { it.isNotBlank() } ?: return@withContext null
        try {
            val resolution = piRuntime.resolveOAuth(PiOAuthProvider.CODEX, credential, false)
            persist(resolution)
            _state.value = readState()
            CodexBearerToken(
                token = resolution.accessToken,
                isApiKey = false,
                accountId = resolution.accountId ?: resolution.profile.accountId
            )
        } catch (e: Exception) {
            DiagnosticsLogger.log("Pi Codex credential resolution failed", e)
            null
        }
    }

    suspend fun retrieveUsageStatus(): Result<CodexUsageStatus> = withContext(Dispatchers.IO) {
        runCatching {
            val auth = getBearerToken()
                ?: throw ProviderClientError.MissingCredential("CODEX_AUTH access token")
            val accountId = auth.accountId?.takeIf { it.isNotBlank() }
                ?: throw ProviderClientError.ParseFailure("Codex account ID is required for usage API")

            val request = Request.Builder()
                .url(USAGE_URL)
                .get()
                .header("Authorization", "Bearer ${auth.token}")
                .header("ChatGPT-Account-ID", accountId)
                .header("originator", ORIGINATOR)
                .header("User-Agent", "codex-cli/0.1.0 (Android)")
                .build()

            val response = httpClient.newCall(request).execute()
            val body = response.body?.string().orEmpty()
            if (!response.isSuccessful) {
                throw ProviderClientError.HttpStatus(response.code, body)
            }

            parseUsage(body)
        }
    }

    private fun persist(resolution: PiOAuthResolution) {
        securePrefs.saveSecret(CREDENTIAL_KEY, PiAgentRuntime.credentialJSONString(resolution.credential))
        securePrefs.saveSecret("codex_email", resolution.profile.email)
        securePrefs.saveSecret("codex_plan_type", resolution.profile.planType)
        securePrefs.saveSecret("codex_account_id", resolution.accountId ?: resolution.profile.accountId)
        securePrefs.saveSecret("codex_last_refresh", Instant.now().toString())
        securePrefs.deleteSecret("codex_auth_json_v2")
        securePrefs.deleteSecret("codex_access_token")
    }

    private fun readState(): CodexAuthState {
        val credential = securePrefs.readSecret(CREDENTIAL_KEY)
        return CodexAuthState(
            isLoggedIn = !credential.isNullOrBlank(),
            email = securePrefs.readSecret("codex_email"),
            planType = securePrefs.readSecret("codex_plan_type"),
            accountId = securePrefs.readSecret("codex_account_id"),
            hasApiKey = false,
            lastRefreshISO8601 = securePrefs.readSecret("codex_last_refresh")
        )
    }

    private fun parseUsage(jsonString: String): CodexUsageStatus {
        val root = JSONObject(jsonString)
        val rateLimit = root.optJSONObject("rate_limit")
        return CodexUsageStatus(
            planType = root.optString("plan_type").takeIf { it.isNotEmpty() },
            primaryWindow = parseWindow(rateLimit?.optJSONObject("primary_window")),
            secondaryWindow = parseWindow(rateLimit?.optJSONObject("secondary_window"))
        )
    }

    private fun parseWindow(obj: JSONObject?): CodexRateLimitWindow? {
        if (obj == null) return null
        return CodexRateLimitWindow(
            usedPercent = if (obj.has("used_percent")) obj.getDouble("used_percent") else null,
            limitWindowSeconds = if (obj.has("limit_window_seconds")) obj.getInt("limit_window_seconds") else null,
            resetAtEpochSeconds = if (obj.has("reset_at_epoch_seconds")) obj.getLong("reset_at_epoch_seconds") else null
        )
    }
}
