package com.porarri.yamabikochat.data.auth

import android.content.Context
import com.porarri.yamabikochat.data.model.ProviderClientError
import com.porarri.yamabikochat.pi.*
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import com.porarri.yamabikochat.utils.SecurePreferencesManager
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.*
import java.time.Instant
import java.util.UUID

/** Official ChatGPT plan authorization is owned by Pi, matching iOS. */
class CodexAuthRepository(
    context: Context,
    private val securePrefs: SecurePreferencesManager = SecurePreferencesManager.getInstance(context),
    private val piRuntime: PiAgentRuntime = PiAgentRuntime.getInstance(context)
) {
    companion object {
        const val CREDENTIAL_KEY = "codex_auth_json"
        private const val ACCOUNTS_KEY = "pi_chatgpt_accounts_v1"
        private const val HOST_KEY = "pi_chatgpt_host_v1"
    }

    private val lock = Any()
    private val resolveMutex = Mutex()
    private var generation = 0
    private var signingOut = false
    private val _state = MutableStateFlow(readState())
    val state: StateFlow<CodexAuthState> = _state.asStateFlow()
    fun currentState(): CodexAuthState = _state.value

    private fun accounts(): JsonObject = securePrefs.readEncryptedSecret(ACCOUNTS_KEY)
        ?.let { Json.parseToJsonElement(it).jsonObject } ?: buildJsonObject {
            put("registrations", buildJsonObject {})
        }

    private fun selected(): JsonObject? {
        val accounts = accounts()
        val id = accounts["selectedClientID"]?.jsonPrimitive?.contentOrNull ?: return null
        return accounts["registrations"]?.jsonObject?.get(id)?.jsonObject
    }

    private fun save(key: String, value: String) {
        check(securePrefs.saveEncryptedSecret(key, value)) { "ChatGPT credential could not be saved securely" }
    }

    private fun saveRegistration(value: JsonObject, select: Boolean) {
        val id = value["clientId"]?.jsonPrimitive?.contentOrNull
        if (id.isNullOrBlank() || id == "dynamic_agent_client" || value["contract"]?.jsonPrimitive?.content != "siwc-v1") {
            throw ProviderClientError.ParseFailure("Pi returned an invalid official ChatGPT registration")
        }
        val accounts = accounts()
        val registrations = accounts["registrations"]!!.jsonObject.toMutableMap()
        if (select || registrations[id]?.jsonObject?.get("access") == null) registrations[id] = value
        save(ACCOUNTS_KEY, buildJsonObject {
            put("registrations", JsonObject(registrations))
            put("selectedClientID", if (select) JsonPrimitive(id) else accounts["selectedClientID"] ?: JsonPrimitive(id))
        }.toString())
    }

    suspend fun loginWithBrowser(clientID: String? = null, newAccount: Boolean = false): Result<CodexAuthState> = withContext(Dispatchers.IO) {
        runCatching {
            val (version, host, registration) = synchronized(lock) {
                check(!signingOut) { "ChatGPT sign-out is in progress" }
                generation++
                val host = securePrefs.readEncryptedSecret(HOST_KEY) ?: "urn:uuid:${UUID.randomUUID()}".also { save(HOST_KEY, it) }
                val registration = if (newAccount) null else if (clientID != null) {
                    accounts()["registrations"]!!.jsonObject[clientID]
                        ?: throw ProviderClientError.ParseFailure("Selected ChatGPT registration is missing")
                } else selected()
                Triple(generation, host, registration)
            }
            DiagnosticsLogger.log("Official ChatGPT authorization delegated to Pi")
            val resolution = piRuntime.loginOAuth(
                PiOAuthProvider.CHATGPT, PiOAuthLoginMethod.BROWSER,
                loginContext = PiChatGPTLoginContext(host, registration),
                onRegistration = { registration -> synchronized(lock) {
                    ensureCurrent(version)
                    saveRegistration(registration.jsonObject, false)
                } }
            )
            synchronized(lock) { commit(resolution, version); currentState() }
        }.onFailure { DiagnosticsLogger.log("Pi ChatGPT authorization failed", it) }
    }

    private fun ensureCurrent(version: Int) {
        if (version != generation || signingOut) throw CancellationException("ChatGPT authorization superseded")
    }

    private fun commit(resolution: PiOAuthResolution, version: Int) {
        ensureCurrent(version)
        val credential = resolution.credential.jsonObject
        if (credential["subject"]?.jsonPrimitive?.contentOrNull.isNullOrBlank() || credential["access"]?.jsonPrimitive?.contentOrNull.isNullOrBlank()) {
            throw ProviderClientError.ParseFailure("Pi returned an incomplete official ChatGPT credential")
        }
        saveRegistration(credential, true)
        save("codex_last_refresh", Instant.now().toString())
        _state.value = readState()
    }

    private suspend fun resolve(force: Boolean): PiOAuthResolution? = resolveMutex.withLock {
        val (version, credential) = synchronized(lock) {
            if (signingOut) throw CancellationException("ChatGPT sign-out is in progress")
            generation to selected()?.takeIf { it["access"] != null }?.toString()
        }
        if (credential == null) return@withLock null
        val resolution = piRuntime.resolveOAuth(PiOAuthProvider.CHATGPT, credential, force)
        synchronized(lock) { commit(resolution, version) }
        resolution
    }

    suspend fun logout(): Result<CodexAuthState> = withContext(Dispatchers.IO) {
        runCatching {
            val credential = synchronized(lock) {
                check(!signingOut) { "ChatGPT sign-out is in progress" }
                generation++
                signingOut = true
                selected()?.takeIf { it["access"] != null }?.toString()
            }
            try {
                var unconfirmed = false
                if (credential != null) {
                    try { piRuntime.revokeChatGPT(credential) }
                    catch (error: Exception) {
                        unconfirmed = true
                        DiagnosticsLogger.log("ChatGPT remote session revocation unconfirmed", error)
                    }
                }
                synchronized(lock) {
                    selected()?.let { registration ->
                        val retained = setOf("contract", "clientId", "hostId", "issuer", "subject", "email")
                        saveRegistration(JsonObject(registration.filterKeys { it in retained }), true)
                    }
                    listOf(CREDENTIAL_KEY, "codex_email", "codex_plan_type", "codex_account_id", "codex_last_refresh", "codex_auth_json_v2", "codex_access_token").forEach(securePrefs::deleteSecret)
                    _state.value = readState().copy(revocationUnconfirmed = unconfirmed)
                    currentState()
                }
            } finally { synchronized(lock) { signingOut = false } }
        }.onFailure { DiagnosticsLogger.log("Pi ChatGPT sign-out failed", it) }
    }

    suspend fun refreshIfNeeded(force: Boolean = false): Result<CodexAuthState> = withContext(Dispatchers.IO) {
        runCatching { resolve(force); currentState() }
            .onFailure { DiagnosticsLogger.log("Pi ChatGPT refresh failed", it) }
    }

    fun hasAuthToken(): Boolean = synchronized(lock) { !signingOut && currentState().isLoggedIn && currentState().planUsageEnabled }
    suspend fun getApiKey(): String? = null
    suspend fun getBearerToken(): CodexBearerToken? = withContext(Dispatchers.IO) {
        if (!hasAuthToken()) return@withContext null
        try { resolve(false)?.let { CodexBearerToken(it.accessToken, accountId = it.accountId) } }
        catch (error: CancellationException) { throw error }
        catch (error: Exception) { DiagnosticsLogger.log("Pi ChatGPT credential resolution failed", error); null }
    }

    suspend fun models(): List<PiCodexModel> {
        if (!hasAuthToken()) return emptyList()
        val version = synchronized(lock) { generation }
        val credential = resolve(false)?.credential ?: return emptyList()
        val models = piRuntime.chatGPTModels(credential.toString())
        return synchronized(lock) { ensureCurrent(version); models }
    }

    private fun readState(): CodexAuthState {
        val registration = selected()
        return CodexAuthState(
            isLoggedIn = registration?.get("contract")?.jsonPrimitive?.content == "siwc-v1" && registration["access"] != null,
            email = registration?.get("email")?.jsonPrimitive?.contentOrNull,
            accountId = registration?.get("clientId")?.jsonPrimitive?.contentOrNull,
            lastRefreshISO8601 = securePrefs.readEncryptedSecret("codex_last_refresh"),
            planUsageEnabled = registration?.get("scopes")?.jsonArray?.any { it.jsonPrimitive.content == "chatgpt.tokens.use.direct" } == true,
            requiresReauthentication = registration?.get("access") == null && !securePrefs.readSecret(CREDENTIAL_KEY).isNullOrBlank(),
            savedAccounts = accounts()["registrations"]!!.jsonObject.entries.sortedBy { it.key }.mapNotNull { (id, value) ->
                value.jsonObject.takeIf { it["subject"] != null }?.let { CodexSavedAccount(id, it["email"]?.jsonPrimitive?.contentOrNull) }
            }
        )
    }
}
