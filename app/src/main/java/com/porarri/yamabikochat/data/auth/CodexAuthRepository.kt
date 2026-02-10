package com.porarri.yamabikochat.data.auth

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import com.porarri.yamabikochat.utils.SecurePreferencesManager
import com.porarri.yamabikochat.BuildConfig
import com.porarri.yamabikochat.utils.CodexUserAgentUtils
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.Dns
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import okhttp3.dnsoverhttps.DnsOverHttps
import org.json.JSONObject
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.net.UnknownHostException
import java.security.MessageDigest
import java.security.SecureRandom
import java.time.Duration
import java.time.Instant
import java.util.Base64

class CodexAuthRepository(
    private val context: Context,
    private val httpClient: OkHttpClient = OkHttpClient()
) {
    companion object {
        private const val DEFAULT_ISSUER = "https://auth.openai.com"
        private const val DEFAULT_PORT = 1455
        private const val CLIENT_ID = "app_EMoamEEZ73f0CkXaXp7hrann"
        private const val SCOPE = "openid profile email offline_access"
        private const val ORIGINATOR = "codex_cli_rs"
        private const val TOKEN_REFRESH_INTERVAL_DAYS = 8L
        private const val CHATGPT_USAGE_URL = "https://chatgpt.com/backend-api/wham/usage"

        private const val REFRESH_TOKEN_EXPIRED_MESSAGE =
            "Your access token could not be refreshed because your refresh token has expired. Please log out and sign in again."
        private const val REFRESH_TOKEN_REUSED_MESSAGE =
            "Your access token could not be refreshed because your refresh token was already used. Please log out and sign in again."
        private const val REFRESH_TOKEN_INVALIDATED_MESSAGE =
            "Your access token could not be refreshed because your refresh token was revoked. Please log out and sign in again."
        private const val REFRESH_TOKEN_UNKNOWN_MESSAGE =
            "Your access token could not be refreshed. Please log out and sign in again."
    }

    private val json = Json { ignoreUnknownKeys = true }
    private val securePrefs = SecurePreferencesManager.getInstance(context)
    private val _state = MutableStateFlow(readState())
    val state: StateFlow<CodexAuthState> = _state.asStateFlow()
    private val authDns: Dns by lazy { buildAuthDns(httpClient) }
    private val authHttpClient: OkHttpClient by lazy {
        httpClient.newBuilder()
            .dns(authDns)
            .build()
    }

    suspend fun login(): Result<CodexAuthState> = withContext(Dispatchers.IO) {
        runCatching {
            val pkce = generatePkce()
            val stateToken = generateState()
            val (server, actualPort) = bindServer(DEFAULT_PORT)
            val redirectUri = "http://localhost:$actualPort/auth/callback"
            DiagnosticsLogger.log("Codex auth login start port=$actualPort")
            ensureAuthHostResolvable()
            val authUrl = buildAuthorizeUrl(
                issuer = DEFAULT_ISSUER,
                clientId = CLIENT_ID,
                redirectUri = redirectUri,
                pkce = pkce,
                state = stateToken
            )

            withContext(Dispatchers.Main) {
                launchBrowser(authUrl)
            }

            val code = withTimeout(5 * 60 * 1000L) {
                awaitAuthCode(server, stateToken)
            }

            DiagnosticsLogger.log("Codex auth callback received; exchanging tokens")
            val tokens = runCatching {
                exchangeCodeForTokens(DEFAULT_ISSUER, CLIENT_ID, redirectUri, pkce, code)
            }.getOrElse { err ->
                throw IllegalStateException(buildNetworkErrorMessage(err), err)
            }
            // Persist tokens first so the app can show "Signed in" even if API key exchange fails.
            persistAuth(openaiApiKey = null, tokens = tokens)
            _state.value = readState()

            var exchangeTokens = tokens
            val apiKeyResult = runCatching {
                exchangeIdTokenForApiKey(DEFAULT_ISSUER, CLIENT_ID, exchangeTokens.idToken)
            }.recoverCatching { err ->
                if (err is ApiKeyExchangeException && isTokenExpiredError(err.status, err.body)) {
                    DiagnosticsLogger.log("Codex auth api key exchange token_expired; refreshing tokens")
                    refreshTokens(exchangeTokens.refreshToken).getOrThrow()
                    val refreshed = readAuthJson()?.tokens ?: exchangeTokens
                    exchangeTokens = refreshed
                    exchangeIdTokenForApiKey(
                        DEFAULT_ISSUER,
                        CLIENT_ID,
                        refreshed.idToken
                    )
                } else {
                    throw err
                }
            }

            apiKeyResult.onSuccess { apiKey ->
                persistAuth(apiKey, exchangeTokens)
            }.onFailure { err ->
                DiagnosticsLogger.log("Codex auth api key exchange failed; keeping tokens for retry", err)
            }

            val updated = readState()
            _state.value = updated
            DiagnosticsLogger.log("Codex auth login completed hasApiKey=${updated.hasApiKey}")

            updated
        }.onFailure { err ->
            DiagnosticsLogger.log("Codex auth login failed", err)
        }
    }

    suspend fun logout(): Result<CodexAuthState> = withContext(Dispatchers.IO) {
        securePrefs.clearCodexAuthJson()
        val updated = readState()
        _state.value = updated
        DiagnosticsLogger.log("Codex auth logout completed")
        Result.success(updated)
    }

    suspend fun refreshIfNeeded(force: Boolean = false): Result<CodexAuthState> = withContext(Dispatchers.IO) {
        val auth = readAuthJson() ?: return@withContext Result.success(readState())
        val tokens = auth.tokens ?: return@withContext Result.success(readState())

        val lastRefresh = auth.lastRefresh?.let { runCatching { Instant.parse(it) }.getOrNull() }
        val stale = lastRefresh == null ||
            Duration.between(lastRefresh, Instant.now()).toDays() >= TOKEN_REFRESH_INTERVAL_DAYS

        if (!force && !stale) return@withContext Result.success(readState())

        val refreshResult = refreshTokens(tokens.refreshToken)
        return@withContext refreshResult.map {
            val updated = readState()
            _state.value = updated
            DiagnosticsLogger.log("Codex auth refresh completed hasApiKey=${updated.hasApiKey}")
            updated
        }
    }

    suspend fun getApiKey(): String? = withContext(Dispatchers.IO) {
        refreshIfNeeded()
        val auth = readAuthJson() ?: return@withContext null
        val apiKey = auth.openaiApiKey?.trim().orEmpty()
        if (apiKey.isNotBlank()) return@withContext apiKey
        val tokens = auth.tokens ?: return@withContext null
        DiagnosticsLogger.log("Codex auth api key missing; exchanging id_token")
        var exchangeTokens = tokens
        val exchangedResult = runCatching {
            exchangeIdTokenForApiKey(DEFAULT_ISSUER, CLIENT_ID, exchangeTokens.idToken)
        }.recoverCatching { err ->
            if (err is ApiKeyExchangeException && isTokenExpiredError(err.status, err.body)) {
                DiagnosticsLogger.log("Codex auth api key exchange token_expired during getApiKey; refreshing tokens")
                refreshTokens(exchangeTokens.refreshToken).getOrThrow()
                val refreshed = readAuthJson()?.tokens ?: exchangeTokens
                exchangeTokens = refreshed
                exchangeIdTokenForApiKey(
                    DEFAULT_ISSUER,
                    CLIENT_ID,
                    refreshed.idToken
                )
            } else {
                throw err
            }
        }
        exchangedResult.onSuccess { exchanged ->
            persistAuth(exchanged, exchangeTokens)
            val updated = readState()
            _state.value = updated
        }.onFailure { err ->
            DiagnosticsLogger.log("Codex auth api key exchange failed during getApiKey", err)
        }
        exchangedResult.getOrNull()
    }

    fun hasApiKey(): Boolean = readAuthJson()?.openaiApiKey?.isNullOrBlank() == false

    suspend fun getBearerToken(): CodexBearerToken? = withContext(Dispatchers.IO) {
        refreshIfNeeded()
        val auth = readAuthJson() ?: return@withContext null
        val apiKey = auth.openaiApiKey?.trim().orEmpty()
        val accountId = auth.tokens?.accountId
            ?: auth.tokens?.idToken?.let { CodexJwtParser.extractAccountId(it) }
            ?: auth.tokens?.accessToken?.let { CodexJwtParser.extractAccountId(it) }
        if (apiKey.isNotBlank()) {
            return@withContext CodexBearerToken(apiKey, isApiKey = true, accountId = accountId)
        }
        val accessToken = auth.tokens?.accessToken?.trim().orEmpty()
        if (accessToken.isNotBlank()) {
            return@withContext CodexBearerToken(accessToken, isApiKey = false, accountId = accountId)
        }
        null
    }

    suspend fun retrieveUsageStatus(): Result<CodexUsageStatus> = withContext(Dispatchers.IO) {
        refreshIfNeeded()

        var credentials = resolveUsageRequestCredentials().getOrElse { err ->
            return@withContext Result.failure(err)
        }
        var usageResponse = executeUsageRead(credentials.accessToken, credentials.accountId)

        if (usageResponse.statusCode == 401) {
            refreshIfNeeded(force = true)
            credentials = resolveUsageRequestCredentials().getOrElse { err ->
                return@withContext Result.failure(err)
            }
            usageResponse = executeUsageRead(credentials.accessToken, credentials.accountId)
        }

        if (usageResponse.statusCode !in 200..299) {
            DiagnosticsLogger.log(
                "Codex auth usage read failed status=${usageResponse.statusCode} body=${sanitizeLogBody(usageResponse.body)}"
            )
            val message = extractApiErrorMessage(usageResponse.body)
                ?: "Failed to load rate limits (HTTP ${usageResponse.statusCode})"
            return@withContext Result.failure(IllegalStateException(message))
        }

        runCatching { parseUsageStatus(usageResponse.body) }.fold(
            onSuccess = { Result.success(it) },
            onFailure = { err ->
                DiagnosticsLogger.log("Codex auth usage parse failed", err)
                Result.failure(IllegalStateException("Failed to parse rate limits response."))
            }
        )
    }

    fun hasAuthToken(): Boolean {
        val auth = readAuthJson() ?: return false
        if (!auth.openaiApiKey.isNullOrBlank()) return true
        return auth.tokens?.accessToken?.isNotBlank() == true
    }

    fun saveUserAgentPreset(preset: String?): Boolean {
        val normalized = preset?.takeIf { it.isNotBlank() }
        return securePrefs.storeCodexUserAgentPreset(normalized)
    }

    private fun readAuthJson(): CodexAuthJson? {
        val raw = securePrefs.getCodexAuthJson() ?: return null
        return runCatching { json.decodeFromString(CodexAuthJson.serializer(), raw) }.getOrNull()
    }

    private fun readState(): CodexAuthState {
        val auth = readAuthJson()
        val tokens = auth?.tokens
        val idInfo = tokens?.idToken?.let { CodexJwtParser.parseIdToken(it) }
        val fallbackAccountId = tokens?.accessToken?.let { CodexJwtParser.extractAccountId(it) }
        return CodexAuthState(
            isLoggedIn = tokens != null,
            email = idInfo?.email,
            planType = idInfo?.planType,
            accountId = idInfo?.accountId ?: tokens?.accountId ?: fallbackAccountId,
            hasApiKey = auth?.openaiApiKey?.isNotBlank() == true,
            lastRefresh = auth?.lastRefresh
        )
    }

    private fun persistAuth(openaiApiKey: String?, tokens: CodexTokenData) {
        val payload = CodexAuthJson(
            openaiApiKey = openaiApiKey,
            tokens = tokens,
            lastRefresh = Instant.now().toString()
        )
        val raw = json.encodeToString(CodexAuthJson.serializer(), payload)
        securePrefs.storeCodexAuthJson(raw)
    }

    private fun refreshTokens(refreshToken: String): Result<Unit> {
        val body = RefreshRequest(
            clientId = CLIENT_ID,
            grantType = "refresh_token",
            refreshToken = refreshToken,
            scope = "openid profile email"
        )
        val requestBody = json.encodeToString(RefreshRequest.serializer(), body)
            .toRequestBody("application/json".toMediaType())

        val request = Request.Builder()
            .url("$DEFAULT_ISSUER/oauth/token")
            .header("Content-Type", "application/json")
            .header("originator", ORIGINATOR)
            .header("User-Agent", buildUserAgent())
            .post(requestBody)
            .build()

        val response = authHttpClient.newCall(request).execute()
        if (response.isSuccessful) {
            val payload = response.body?.string().orEmpty()
            val refreshResponse = json.decodeFromString(RefreshResponse.serializer(), payload)
            updateStoredTokens(refreshResponse)
            return Result.success(Unit)
        }

        val bodyText = response.body?.string().orEmpty()
        val message = if (response.code == 401) {
            classifyRefreshTokenFailure(bodyText)
        } else {
            "Failed to refresh token: ${response.code}"
        }
        DiagnosticsLogger.log("Codex auth refresh failed code=${response.code} message=$message")
        return Result.failure(IllegalStateException(message))
    }

    private fun updateStoredTokens(response: RefreshResponse) {
        val current = readAuthJson() ?: return
        val existing = current.tokens ?: return
        val updated = existing.copy(
            idToken = response.idToken ?: existing.idToken,
            accessToken = response.accessToken ?: existing.accessToken,
            refreshToken = response.refreshToken ?: existing.refreshToken
        )
        persistAuth(current.openaiApiKey, updated)
    }

    private fun classifyRefreshTokenFailure(body: String): String {
        val code = extractRefreshTokenErrorCode(body)?.lowercase()
        return when (code) {
            "refresh_token_expired" -> REFRESH_TOKEN_EXPIRED_MESSAGE
            "refresh_token_reused" -> REFRESH_TOKEN_REUSED_MESSAGE
            "refresh_token_invalidated" -> REFRESH_TOKEN_INVALIDATED_MESSAGE
            else -> REFRESH_TOKEN_UNKNOWN_MESSAGE
        }
    }

    private fun extractRefreshTokenErrorCode(body: String): String? {
        if (body.isBlank()) return null
        return runCatching {
            val obj = JSONObject(body)
            when (val error = obj.opt("error")) {
                is JSONObject -> error.optString("code")
                is String -> error
                else -> obj.optString("code")
            }.takeIf { it.isNotBlank() }
        }.getOrNull()
    }

    private fun isTokenExpiredError(status: Int, body: String): Boolean {
        if (status != 401 || body.isBlank()) return false
        val code = runCatching {
            val obj = JSONObject(body)
            when (val error = obj.opt("error")) {
                is JSONObject -> error.optString("code")
                is String -> error
                else -> obj.optString("code")
            }
        }.getOrNull()?.lowercase()
        if (code == "token_expired") return true
        val message = runCatching {
            val obj = JSONObject(body)
            when (val error = obj.opt("error")) {
                is JSONObject -> error.optString("message")
                else -> obj.optString("message")
            }
        }.getOrNull()?.lowercase().orEmpty()
        return message.contains("token") && message.contains("expired")
    }

    private fun exchangeCodeForTokens(
        issuer: String,
        clientId: String,
        redirectUri: String,
        pkce: PkceCodes,
        code: String
    ): CodexTokenData {
        val form = "grant_type=authorization_code" +
            "&code=${encode(code)}" +
            "&redirect_uri=${encode(redirectUri)}" +
            "&client_id=${encode(clientId)}" +
            "&code_verifier=${encode(pkce.verifier)}"
        val requestBody = form.toRequestBody("application/x-www-form-urlencoded".toMediaType())
        val request = Request.Builder()
            .url("$issuer/oauth/token")
            .header("Content-Type", "application/x-www-form-urlencoded")
            .post(requestBody)
            .build()
        val response = authHttpClient.newCall(request).execute()
        val payload = response.body?.string().orEmpty()
        if (!response.isSuccessful) {
            DiagnosticsLogger.log(
                "Codex auth token exchange failed status=${response.code} body=${sanitizeLogBody(payload)}"
            )
            throw IllegalStateException("token endpoint returned status ${response.code}")
        }
        return json.decodeFromString(CodexTokenData.serializer(), payload)
    }

    private fun jwtTimeInfo(rawJwt: String): String {
        return runCatching {
            val parts = rawJwt.split('.')
            if (parts.size < 3) return@runCatching "invalid"
            val payload = parts[1]
            val padding = (4 - payload.length % 4) % 4
            val padded = payload + "=".repeat(padding)
            val decoded = Base64.getUrlDecoder().decode(padded)
            val obj = JSONObject(String(decoded))
            val iat = obj.optLong("iat", 0)
            val exp = obj.optLong("exp", 0)
            val iatStr = if (iat > 0) Instant.ofEpochSecond(iat).toString() else "unknown"
            val expStr = if (exp > 0) Instant.ofEpochSecond(exp).toString() else "unknown"
            "iat=" + iatStr + ", exp=" + expStr
        }.getOrElse { "unavailable" }
    }

    private fun exchangeIdTokenForApiKey(
        issuer: String,
        clientId: String,
        idToken: String
    ): String {
        val initial = executeApiKeyExchange(
            issuer = issuer,
            clientId = clientId,
            subjectToken = idToken,
            subjectTokenType = "urn:ietf:params:oauth:token-type:id_token"
        )
        if (initial.apiKey != null) return initial.apiKey

        DiagnosticsLogger.log(
            "Codex auth api key exchange failed status=${initial.status} times " +
                jwtTimeInfo(idToken) +
                " body=${sanitizeLogBody(initial.body)}"
        )
        throw ApiKeyExchangeException(initial.status, initial.body)
    }

    private suspend fun awaitAuthCode(server: ServerSocket, expectedState: String): String =
        withContext(Dispatchers.IO) {
            try {
                var result: String? = null
                while (result == null) {
                    val socket = server.accept()
                    try {
                        val input = socket.getInputStream().bufferedReader()
                        val requestLine = input.readLine() ?: continue
                        val path = requestLine.split(" ").getOrNull(1) ?: continue
                        val uri = Uri.parse("http://localhost$path")
                        val state = uri.getQueryParameter("state")
                        val code = uri.getQueryParameter("code")
                        if (uri.path == "/auth/callback" && state == expectedState && !code.isNullOrBlank()) {
                            runCatching {
                                respondHtml(socket, "Codex Auth login completed. You can return to the app.")
                            }.onFailure { err ->
                                DiagnosticsLogger.log("Codex auth callback response failed", err)
                            }
                            result = code
                        } else if (uri.path == "/auth/callback") {
                            runCatching {
                                respondHtml(socket, "Invalid login state or missing code.")
                            }.onFailure { err ->
                                DiagnosticsLogger.log("Codex auth callback response failed", err)
                            }
                        } else {
                            runCatching {
                                respondStatus(socket, 404, "Not Found")
                            }.onFailure { err ->
                                DiagnosticsLogger.log("Codex auth callback response failed", err)
                            }
                        }
                    } finally {
                        socket.close()
                    }
                }
                result ?: error("Auth code not received")
            } finally {
                server.close()
            }
        }

    private fun respondHtml(client: java.net.Socket, message: String) {
        val body = """
            <html>
              <head><meta charset="utf-8"/></head>
              <body style="font-family:sans-serif;">
                <h2>$message</h2>
              </body>
            </html>
        """.trimIndent()
        val bytes = body.toByteArray()
        val header = "HTTP/1.1 200 OK\r\n" +
            "Content-Type: text/html; charset=utf-8\r\n" +
            "Content-Length: ${bytes.size}\r\n" +
            "Connection: close\r\n\r\n"
        client.getOutputStream().apply {
            write(header.toByteArray())
            write(bytes)
            flush()
        }
    }

    private fun respondStatus(client: java.net.Socket, code: Int, message: String) {
        val body = "$code $message"
        val bytes = body.toByteArray()
        val header = "HTTP/1.1 $code $message\r\n" +
            "Content-Type: text/plain; charset=utf-8\r\n" +
            "Content-Length: ${bytes.size}\r\n" +
            "Connection: close\r\n\r\n"
        client.getOutputStream().apply {
            write(header.toByteArray())
            write(bytes)
            flush()
        }
    }

    private fun launchBrowser(url: String) {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    private fun buildAuthorizeUrl(
        issuer: String,
        clientId: String,
        redirectUri: String,
        pkce: PkceCodes,
        state: String
    ): String {
        val params = listOf(
            "response_type" to "code",
            "client_id" to clientId,
            "redirect_uri" to redirectUri,
            "scope" to SCOPE,
            "code_challenge" to pkce.challenge,
            "code_challenge_method" to "S256",
            "id_token_add_organizations" to "true",
            "codex_cli_simplified_flow" to "true",
            "state" to state,
            "originator" to ORIGINATOR
        )
        val qs = params.joinToString("&") { (k, v) -> "$k=${encode(v)}" }
        return "$issuer/oauth/authorize?$qs"
    }

    private fun generatePkce(): PkceCodes {
        val verifierBytes = ByteArray(64)
        SecureRandom().nextBytes(verifierBytes)
        val verifier = base64Url(verifierBytes)
        val challenge = base64Url(MessageDigest.getInstance("SHA-256").digest(verifier.toByteArray()))
        return PkceCodes(verifier = verifier, challenge = challenge)
    }

    private fun generateState(): String {
        val bytes = ByteArray(32)
        SecureRandom().nextBytes(bytes)
        return base64Url(bytes)
    }

    private fun base64Url(bytes: ByteArray): String =
        Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)

    private fun encode(value: String): String = Uri.encode(value)

    private fun bindServer(preferredPort: Int): Pair<ServerSocket, Int> {
        val server = ServerSocket()
        server.reuseAddress = true
        val loopback = InetAddress.getByName("127.0.0.1")
        val bound = runCatching {
            server.bind(InetSocketAddress(loopback, preferredPort))
        }
        if (bound.isFailure) {
            server.bind(InetSocketAddress(loopback, 0))
        }
        return server to server.localPort
    }

    private fun buildUserAgent(): String {
        val appVersion = BuildConfig.VERSION_NAME.takeIf { it.isNotBlank() } ?: "0.0.0"
        val cliVersion = securePrefs.getCodexUserAgentCliVersion()
            ?.trim()
            ?.takeIf { it.isNotBlank() }
            ?: CodexUserAgentUtils.DEFAULT_CODEX_CLI_VERSION
        val osVersion = Build.VERSION.RELEASE?.takeIf { it.isNotBlank() } ?: "unknown"
        val abi = Build.SUPPORTED_ABIS.firstOrNull()?.takeIf { it.isNotBlank() } ?: "unknown"
        val preset = securePrefs.getCodexUserAgentPreset()
        val candidate = CodexUserAgentUtils.buildUserAgent(
            originator = ORIGINATOR,
            cliVersion = cliVersion,
            preset = preset,
            androidOsVersion = osVersion,
            androidAbi = abi,
            androidAppId = BuildConfig.APPLICATION_ID,
            androidAppVersion = appVersion
        )
        return sanitizeUserAgent(candidate, "${ORIGINATOR}/${cliVersion}")
    }

    private fun executeApiKeyExchange(
        issuer: String,
        clientId: String,
        subjectToken: String,
        subjectTokenType: String
    ): ApiKeyExchangeResult {
        val form = "grant_type=${encode("urn:ietf:params:oauth:grant-type:token-exchange")}" +
            "&client_id=${encode(clientId)}" +
            "&requested_token=${encode("openai-api-key")}" +
            "&subject_token=${encode(subjectToken)}" +
            "&subject_token_type=${encode(subjectTokenType)}"
        val requestBody = form.toRequestBody("application/x-www-form-urlencoded".toMediaType())
        val request = Request.Builder()
            .url("$issuer/oauth/token")
            .header("Content-Type", "application/x-www-form-urlencoded")
            .post(requestBody)
            .build()
        val response = authHttpClient.newCall(request).execute()
        val payload = response.body?.string().orEmpty()
        if (!response.isSuccessful) {
            return ApiKeyExchangeResult(
                apiKey = null,
                status = response.code,
                body = payload
            )
        }
        val result = json.decodeFromString(ApiKeyExchangeResponse.serializer(), payload)
        return ApiKeyExchangeResult(
            apiKey = result.accessToken,
            status = response.code,
            body = payload
        )
    }

    private fun ensureAuthHostResolvable() {
        val host = Uri.parse(DEFAULT_ISSUER).host ?: return
        runCatching { authDns.lookup(host) }.onFailure { err ->
            throw IllegalStateException(buildNetworkErrorMessage(err), err)
        }
    }

    private fun buildNetworkErrorMessage(err: Throwable): String {
        val root = generateSequence(err) { it.cause }.last()
        val isUnknownHost = root is java.net.UnknownHostException ||
            root.javaClass.name.contains("GaiException") ||
            root.message?.contains("Unable to resolve host", ignoreCase = true) == true
        return if (isUnknownHost) {
            "Network error: unable to resolve auth.openai.com. Check Private DNS/VPN or set Private DNS to dns.google or 1dot1dot1dot1.cloudflare-dns.com."
        } else {
            "Network error during Codex auth. Please check your connection and try again."
        }
    }

    private fun sanitizeUserAgent(candidate: String, fallback: String): String {
        val sanitized = candidate.map { ch ->
            if (ch.code in 32..126) ch else '_'
        }.joinToString("")
        return if (sanitized.isNotBlank()) sanitized else fallback
    }

    private fun sanitizeLogBody(body: String, maxChars: Int = 400): String {
        val trimmed = body.trim()
        if (trimmed.isBlank()) return ""
        return if (trimmed.length <= maxChars) trimmed else trimmed.take(maxChars) + "..."
    }

    private fun resolveUsageRequestCredentials(): Result<UsageRequestCredentials> {
        val auth = readAuthJson()
            ?: return Result.failure(IllegalStateException("Not signed in."))
        val accessToken = auth.tokens?.accessToken?.trim().orEmpty()
        if (accessToken.isBlank()) {
            return Result.failure(
                IllegalStateException("Access token is missing. Please sign in again.")
            )
        }
        val accountId = auth.tokens?.accountId
            ?: auth.tokens?.idToken?.let { CodexJwtParser.extractAccountId(it) }
            ?: auth.tokens?.accessToken?.let { CodexJwtParser.extractAccountId(it) }
        val cleanedAccountId = accountId?.trim().orEmpty()
        if (cleanedAccountId.isBlank()) {
            return Result.failure(
                IllegalStateException("Workspace/account ID is required to check rate limits.")
            )
        }
        return Result.success(
            UsageRequestCredentials(
                accessToken = accessToken,
                accountId = cleanedAccountId
            )
        )
    }

    private fun executeUsageRead(accessToken: String, accountId: String): UsageHttpResult {
        val request = Request.Builder()
            .url(CHATGPT_USAGE_URL)
            .header("Authorization", "Bearer $accessToken")
            .header("ChatGPT-Account-ID", accountId)
            .header("originator", ORIGINATOR)
            .header("User-Agent", buildUserAgent())
            .get()
            .build()

        val response = authHttpClient.newCall(request).execute()
        response.use { resp ->
            return UsageHttpResult(
                statusCode = resp.code,
                body = resp.body?.string().orEmpty()
            )
        }
    }

    private fun parseUsageStatus(raw: String): CodexUsageStatus {
        val payload = JSONObject(raw)
        val planType = payload.optString("plan_type").takeIf { it.isNotBlank() }
        val rateLimit = payload.optJSONObject("rate_limit")
        val primaryWindow = parseUsageWindow(rateLimit?.optJSONObject("primary_window"))
        val secondaryWindow = parseUsageWindow(rateLimit?.optJSONObject("secondary_window"))
        val credits = parseUsageCredits(payload.optJSONObject("credits"))
        return CodexUsageStatus(
            planType = planType,
            primaryWindow = primaryWindow,
            secondaryWindow = secondaryWindow,
            credits = credits
        )
    }

    private fun parseUsageWindow(window: JSONObject?): CodexRateLimitWindow? {
        window ?: return null
        val usedPercent = if (window.has("used_percent")) {
            window.optDouble("used_percent").takeIf { !it.isNaN() }
        } else {
            null
        }
        val limitWindowSeconds = window.optInt("limit_window_seconds").takeIf { it > 0 }
        val resetAt = window.optLong("reset_at").takeIf { it > 0L }
        if (usedPercent == null && limitWindowSeconds == null && resetAt == null) return null
        return CodexRateLimitWindow(
            usedPercent = usedPercent,
            limitWindowSeconds = limitWindowSeconds,
            resetAtEpochSeconds = resetAt
        )
    }

    private fun parseUsageCredits(credits: JSONObject?): CodexCreditsStatus? {
        credits ?: return null
        val hasCredits = credits.optBoolean("has_credits", false)
        val unlimited = credits.optBoolean("unlimited", false)
        val balanceRaw = credits.opt("balance")
        val balance = when (balanceRaw) {
            null, JSONObject.NULL -> null
            is String -> balanceRaw.takeIf { it.isNotBlank() }
            else -> balanceRaw.toString().takeIf { it.isNotBlank() }
        }
        return CodexCreditsStatus(
            hasCredits = hasCredits,
            unlimited = unlimited,
            balance = balance
        )
    }

    private fun extractApiErrorMessage(raw: String): String? {
        if (raw.isBlank()) return null
        return runCatching {
            val obj = JSONObject(raw)
            val errorObj = obj.opt("error")
            when (errorObj) {
                is JSONObject -> errorObj.optString("message").takeIf { it.isNotBlank() }
                is String -> errorObj.takeIf { it.isNotBlank() }
                else -> obj.optString("message").takeIf { it.isNotBlank() }
            }
        }.getOrNull()
    }

    private fun buildAuthDns(baseClient: OkHttpClient): Dns {
        val dohClient = baseClient.newBuilder()
            .dns(Dns.SYSTEM)
            .build()
        val cloudflare = buildDohDns(
            baseClient = dohClient,
            url = "https://cloudflare-dns.com/dns-query",
            bootstrapHosts = listOf(ipv4(1, 1, 1, 1), ipv4(1, 0, 0, 1))
        )
        val google = buildDohDns(
            baseClient = dohClient,
            url = "https://dns.google/dns-query",
            bootstrapHosts = listOf(ipv4(8, 8, 8, 8), ipv4(8, 8, 4, 4))
        )
        return FallbackDns(
            primary = Dns.SYSTEM,
            fallbacks = listOf(cloudflare, google)
        )
    }

    private fun buildDohDns(
        baseClient: OkHttpClient,
        url: String,
        bootstrapHosts: List<InetAddress>
    ): Dns = DnsOverHttps.Builder()
        .client(baseClient)
        .url(url.toHttpUrl())
        .bootstrapDnsHosts(bootstrapHosts)
        .build()

    private fun ipv4(a: Int, b: Int, c: Int, d: Int): InetAddress =
        InetAddress.getByAddress(byteArrayOf(a.toByte(), b.toByte(), c.toByte(), d.toByte()))

    private class FallbackDns(
        private val primary: Dns,
        private val fallbacks: List<Dns>
    ) : Dns {
        override fun lookup(hostname: String): List<InetAddress> {
            val primaryFailure = try {
                return primary.lookup(hostname)
            } catch (err: Exception) {
                err
            }
            val errors = mutableListOf<Exception>(primaryFailure)
            fallbacks.forEachIndexed { index, dns ->
                try {
                    val result = dns.lookup(hostname)
                    DiagnosticsLogger.log("Codex auth DNS fallback succeeded index=$index host=$hostname")
                    return result
                } catch (err: Exception) {
                    errors.add(err)
                }
            }
            if (primaryFailure is UnknownHostException) {
                errors.drop(1).forEach { primaryFailure.addSuppressed(it) }
            }
            DiagnosticsLogger.log("Codex auth DNS fallback failed host=$hostname attempts=${errors.size}")
            throw primaryFailure
        }
    }

    private data class PkceCodes(
        val verifier: String,
        val challenge: String
    )

    private data class ApiKeyExchangeResult(
        val apiKey: String?,
        val status: Int,
        val body: String
    )

    private data class UsageRequestCredentials(
        val accessToken: String,
        val accountId: String
    )

    private data class UsageHttpResult(
        val statusCode: Int,
        val body: String
    )

    private class ApiKeyExchangeException(
        val status: Int,
        val body: String
    ) : IllegalStateException("api key exchange failed with status $status")

    data class CodexBearerToken(
        val token: String,
        val isApiKey: Boolean,
        val accountId: String? = null
    )

    @Serializable
    private data class ApiKeyExchangeResponse(
        @SerialName("access_token") val accessToken: String
    )

    @Serializable
    private data class RefreshRequest(
        @SerialName("client_id") val clientId: String,
        @SerialName("grant_type") val grantType: String,
        @SerialName("refresh_token") val refreshToken: String,
        @SerialName("scope") val scope: String
    )

    @Serializable
    private data class RefreshResponse(
        @SerialName("id_token") val idToken: String? = null,
        @SerialName("access_token") val accessToken: String? = null,
        @SerialName("refresh_token") val refreshToken: String? = null
    )
}
