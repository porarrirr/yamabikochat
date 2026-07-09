package com.porarri.yamabikochat.data.auth

import android.content.Context
import android.content.Intent
import android.net.Uri
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import com.porarri.yamabikochat.utils.SecurePreferencesManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.ServerSocket
import java.security.MessageDigest
import java.security.SecureRandom
import java.time.Instant
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import java.util.Base64

class SuperGrokAuthRepository(
    private val context: Context,
    private val httpClient: OkHttpClient = OkHttpClient()
) {
    data class BearerToken(
        val token: String
    )

    private data class PkceCodes(
        val verifier: String,
        val challenge: String
    )

    private val json = Json { ignoreUnknownKeys = true }
    private val securePrefs = SecurePreferencesManager.getInstance(context)
    private val _state = MutableStateFlow(readState())
    val state: StateFlow<SuperGrokAuthState> = _state.asStateFlow()
    /** Serializes refresh so concurrent 401 retries do not burn a single-use refresh token. */
    private val refreshMutex = Mutex()

    suspend fun loginWithBrowser(): Result<SuperGrokAuthState> = withContext(Dispatchers.IO) {
        runCatching {
            DiagnosticsLogger.log("SuperGrok auth browser login start")
            val pkce = generatePkce()
            val stateToken = generateState()
            val nonce = generateState()
            val (server, actualPort) = bindServer(SuperGrokAuthConstants.OAUTH_PORT)
            if (actualPort != SuperGrokAuthConstants.OAUTH_PORT) {
                server.close()
                throw SuperGrokAuthCallbackError.portMismatch(SuperGrokAuthConstants.OAUTH_PORT, actualPort)
            }
            val redirectUri = SuperGrokAuthConstants.REDIRECT_URI
            val authUrl = buildAuthorizeUrl(
                redirectUri = redirectUri,
                pkce = pkce,
                state = stateToken,
                nonce = nonce
            )

            withContext(Dispatchers.Main) {
                launchBrowser(authUrl)
            }

            val code = withTimeout(5 * 60 * 1000L) {
                awaitAuthCode(server, stateToken)
            }

            val tokens = exchangeCodeForTokens(code, redirectUri, pkce.verifier)
            persistAuth(tokens)
            val updated = readState()
            _state.value = updated
            DiagnosticsLogger.log("SuperGrok auth browser login completed")
            updated
        }.onFailure { err ->
            DiagnosticsLogger.log("SuperGrok auth browser login failed", err)
        }
    }

    suspend fun loginWithDeviceCode(): Result<SuperGrokAuthState> = withContext(Dispatchers.IO) {
        runCatching {
            val device = requestDeviceCode()
            val challenge = SuperGrokDeviceCodeChallenge(
                verificationUri = device.verificationUri,
                userCode = device.userCode,
                browserUrl = device.verificationUriComplete ?: device.verificationUri
            )
            var pending = readState()
            pending = pending.copy(pendingDeviceCode = challenge)
            _state.value = pending

            withContext(Dispatchers.Main) {
                launchBrowser(challenge.browserUrl)
            }

            val tokens = pollDeviceCodeToken(device)
            persistAuth(tokens)
            val updated = readState()
            _state.value = updated
            DiagnosticsLogger.log("SuperGrok auth device-code login completed")
            updated
        }.onFailure { err ->
            val cleared = readState().copy(pendingDeviceCode = null)
            _state.value = cleared
            DiagnosticsLogger.log("SuperGrok auth device-code login failed", err)
        }
    }

    suspend fun logout(): Result<SuperGrokAuthState> = withContext(Dispatchers.IO) {
        runCatching {
            securePrefs.clearSuperGrokAuth()
            val updated = readState()
            _state.value = updated
            DiagnosticsLogger.log("SuperGrok auth logout completed")
            updated
        }
    }

    suspend fun refreshIfNeeded(force: Boolean = false): Result<SuperGrokAuthState> = withContext(Dispatchers.IO) {
        refreshMutex.withLock {
            runCatching {
                if (!hasAuthToken()) {
                    val current = readState()
                    _state.value = current
                    return@runCatching current
                }

                val auth = readAuthJson()
                val tokens = auth?.tokens
                if (auth == null || tokens == null) {
                    val current = readState()
                    _state.value = current
                    return@runCatching current
                }

                if (tokens.refreshToken.isBlank()) {
                    if (force) throw SuperGrokAuthRefreshError.MissingRefreshToken
                    val current = readState()
                    _state.value = current
                    return@runCatching current
                }

                if (force || shouldRefresh(auth, tokens.accessToken)) {
                    try {
                        val refreshed = refreshAccessToken(tokens.refreshToken)
                        val updatedTokens = tokens.copy(
                            accessToken = refreshed.accessToken,
                            refreshToken = refreshed.refreshToken.takeIf { it.isNotBlank() } ?: tokens.refreshToken,
                            idToken = refreshed.idToken ?: tokens.idToken,
                            tokenType = refreshed.tokenType ?: tokens.tokenType,
                            scope = refreshed.scope ?: tokens.scope
                        )
                        val expiresAtEpochMs = expiresAtEpochMs(refreshed.expiresIn)
                        persistAuth(updatedTokens, expiresAtEpochMs)
                    } catch (err: SuperGrokAuthRefreshError) {
                        if (err.isUnrecoverable) {
                            clearOAuthTokens()
                            val updated = readState()
                            _state.value = updated
                            throw err
                        }
                        throw err
                    }
                }

                val updated = readState()
                _state.value = updated
                updated
            }.onFailure { err ->
                if (err is SuperGrokAuthRefreshError) {
                    DiagnosticsLogger.log("SuperGrok auth refresh failed message=${err.message}")
                }
            }
        }
    }

    fun hasAuthToken(): Boolean {
        if (!securePrefs.getSuperGrokAccessToken().isNullOrBlank()) return true
        return readAuthJson()?.tokens?.accessToken?.isNotBlank() == true
    }

    suspend fun getBearerToken(): BearerToken? = withContext(Dispatchers.IO) {
        refreshIfNeeded()
        val token = securePrefs.getSuperGrokAccessToken()?.trim().orEmpty()
        if (token.isNotBlank()) return@withContext BearerToken(token)
        null
    }

    companion object {
        fun buildAuthorizeUrl(
            redirectUri: String,
            verifier: String,
            challenge: String,
            state: String,
            nonce: String
        ): String {
            val params = listOf(
                "response_type" to "code",
                "client_id" to SuperGrokAuthConstants.CLIENT_ID,
                "redirect_uri" to redirectUri,
                "scope" to SuperGrokAuthConstants.SCOPE,
                "code_challenge" to challenge,
                "code_challenge_method" to "S256",
                "state" to state,
                "nonce" to nonce,
                "plan" to "generic",
                "referrer" to "opencode"
            )
            val qs = params.joinToString("&") { (k, v) ->
                "$k=${URLEncoder.encode(v, StandardCharsets.UTF_8.name())}"
            }
            return "${SuperGrokAuthConstants.AUTHORIZE_URL}?$qs"
        }

        fun accessTokenIsExpiring(
            token: String?,
            skewMs: Long = SuperGrokAuthConstants.ACCESS_TOKEN_REFRESH_SKEW_MS
        ): Boolean = SuperGrokJwtParser.accessTokenIsExpiring(token, skewMs)
    }

    private fun shouldRefresh(auth: SuperGrokAuthJson, accessToken: String): Boolean {
        if (SuperGrokJwtParser.accessTokenIsExpiring(accessToken)) return true
        val expiresAtEpochMs = auth.expiresAtEpochMs ?: return true
        val nowMs = System.currentTimeMillis()
        return expiresAtEpochMs - nowMs <= SuperGrokAuthConstants.ACCESS_TOKEN_REFRESH_SKEW_MS
    }

    private fun readAuthJson(): SuperGrokAuthJson? {
        val raw = securePrefs.getSuperGrokAuthJson() ?: return null
        return runCatching { json.decodeFromString(SuperGrokAuthJson.serializer(), raw) }.getOrNull()
    }

    private fun readState(): SuperGrokAuthState {
        val token = securePrefs.getSuperGrokAccessToken()
        val email = securePrefs.getSuperGrokEmail()
        val lastRefresh = securePrefs.getSuperGrokLastRefresh()
        return SuperGrokAuthState(
            isLoggedIn = !token.isNullOrBlank(),
            email = email,
            lastRefreshIso8601 = lastRefresh,
            pendingDeviceCode = null
        )
    }

    private fun persistAuth(tokens: SuperGrokTokenResponse) {
        val tokenData = SuperGrokTokenData(
            idToken = tokens.idToken,
            accessToken = tokens.accessToken,
            refreshToken = tokens.refreshToken,
            tokenType = tokens.tokenType,
            scope = tokens.scope
        )
        persistAuth(tokenData, expiresAtEpochMs(tokens.expiresIn))
    }

    private fun persistAuth(tokens: SuperGrokTokenData, expiresAtEpochMs: Long?) {
        val payload = SuperGrokAuthJson(
            tokens = tokens,
            expiresAtEpochMs = expiresAtEpochMs,
            lastRefresh = Instant.now().toString()
        )
        val raw = json.encodeToString(SuperGrokAuthJson.serializer(), payload)
        securePrefs.storeSuperGrokAuthJson(raw)
        securePrefs.storeSuperGrokAccessToken(tokens.accessToken)
        val idInfo = tokens.idToken?.let { SuperGrokJwtParser.parseIdToken(it) }
        securePrefs.storeSuperGrokEmail(idInfo?.email)
        securePrefs.storeSuperGrokLastRefresh(payload.lastRefresh)
    }

    private fun clearOAuthTokens() {
        securePrefs.storeSuperGrokAccessToken(null)
        securePrefs.clearSuperGrokAuthJsonOnly()
        securePrefs.storeSuperGrokEmail(null)
        securePrefs.storeSuperGrokLastRefresh(Instant.now().toString())
    }

    private fun requestDeviceCode(): SuperGrokDeviceCodeResponse {
        val form = listOf(
            "client_id" to SuperGrokAuthConstants.CLIENT_ID,
            "scope" to SuperGrokAuthConstants.SCOPE
        ).joinToString("&") { (k, v) -> "$k=${encode(v)}" }
        val request = Request.Builder()
            .url(SuperGrokAuthConstants.DEVICE_AUTHORIZATION_URL)
            .header("Content-Type", "application/x-www-form-urlencoded")
            .header("Accept", "application/json")
            .header("User-Agent", buildUserAgent())
            .post(form.toRequestBody("application/x-www-form-urlencoded".toMediaType()))
            .build()
        val response = httpClient.newCall(request).execute()
        val body = response.body?.string().orEmpty()
        if (!response.isSuccessful) {
            throw IllegalStateException("device code endpoint returned status ${response.code}: $body")
        }
        val decoded = json.decodeFromString(SuperGrokDeviceCodeResponse.serializer(), body)
        if (decoded.deviceCode.isBlank() || decoded.userCode.isBlank() || decoded.verificationUri.isBlank()) {
            throw IllegalStateException("xAI device code response is missing required fields")
        }
        return decoded
    }

    private suspend fun pollDeviceCodeToken(device: SuperGrokDeviceCodeResponse): SuperGrokTokenResponse {
        val expiresInMs = positiveSecondsToMs(device.expiresIn, SuperGrokAuthConstants.DEVICE_CODE_DEFAULT_EXPIRES_MS)
        val deadlineMs = System.currentTimeMillis() + expiresInMs
        var intervalMs = maxOf(
            positiveSecondsToMs(device.interval, SuperGrokAuthConstants.DEVICE_CODE_DEFAULT_INTERVAL_MS),
            SuperGrokAuthConstants.DEVICE_CODE_MIN_INTERVAL_MS
        )

        while (System.currentTimeMillis() < deadlineMs) {
            val form = listOf(
                "grant_type" to SuperGrokAuthConstants.DEVICE_CODE_GRANT_TYPE,
                "client_id" to SuperGrokAuthConstants.CLIENT_ID,
                "device_code" to device.deviceCode
            ).joinToString("&") { (k, v) -> "$k=${encode(v)}" }
            val request = Request.Builder()
                .url(SuperGrokAuthConstants.TOKEN_URL)
                .header("Content-Type", "application/x-www-form-urlencoded")
                .header("Accept", "application/json")
                .header("User-Agent", buildUserAgent())
                .post(form.toRequestBody("application/x-www-form-urlencoded".toMediaType()))
                .build()
            val response = httpClient.newCall(request).execute()
            val body = response.body?.string().orEmpty()
            if (response.isSuccessful) {
                return json.decodeFromString(SuperGrokTokenResponse.serializer(), body)
            }

            val errorBody = runCatching {
                json.decodeFromString(SuperGrokDeviceTokenErrorBody.serializer(), body)
            }.getOrNull()
            val remainingMs = maxOf(0L, deadlineMs - System.currentTimeMillis())
            when (errorBody?.error) {
                "authorization_pending" -> {
                    delay(minOf(intervalMs + SuperGrokAuthConstants.DEVICE_CODE_POLLING_SAFETY_MARGIN_MS, remainingMs))
                    continue
                }
                "slow_down" -> {
                    intervalMs += SuperGrokAuthConstants.DEVICE_CODE_SLOW_DOWN_INCREMENT_MS
                    delay(minOf(intervalMs + SuperGrokAuthConstants.DEVICE_CODE_POLLING_SAFETY_MARGIN_MS, remainingMs))
                    continue
                }
                "access_denied", "authorization_denied" ->
                    throw IllegalStateException("xAI device authorization was denied")
                "expired_token" ->
                    throw IllegalStateException("xAI device code expired - please re-run login")
                else -> {
                    val detail = errorBody?.errorDescription ?: errorBody?.error ?: body
                    throw IllegalStateException("device token endpoint returned status ${response.code}: $detail")
                }
            }
        }
        throw IllegalStateException("xAI device authorization timed out")
    }

    private fun exchangeCodeForTokens(
        code: String,
        redirectUri: String,
        codeVerifier: String
    ): SuperGrokTokenResponse {
        val form = listOf(
            "grant_type" to "authorization_code",
            "code" to code,
            "redirect_uri" to redirectUri,
            "client_id" to SuperGrokAuthConstants.CLIENT_ID,
            "code_verifier" to codeVerifier
        ).joinToString("&") { (k, v) -> "$k=${encode(v)}" }
        val request = Request.Builder()
            .url(SuperGrokAuthConstants.TOKEN_URL)
            .header("Content-Type", "application/x-www-form-urlencoded")
            .header("Accept", "application/json")
            .header("User-Agent", buildUserAgent())
            .post(form.toRequestBody("application/x-www-form-urlencoded".toMediaType()))
            .build()
        val response = httpClient.newCall(request).execute()
        val body = response.body?.string().orEmpty()
        if (!response.isSuccessful) {
            throw IllegalStateException("token endpoint returned status ${response.code}: $body")
        }
        return json.decodeFromString(SuperGrokTokenResponse.serializer(), body)
    }

    private fun refreshAccessToken(refreshToken: String): SuperGrokTokenResponse {
        val form = listOf(
            "grant_type" to "refresh_token",
            "refresh_token" to refreshToken,
            "client_id" to SuperGrokAuthConstants.CLIENT_ID
        ).joinToString("&") { (k, v) -> "$k=${encode(v)}" }
        val request = Request.Builder()
            .url(SuperGrokAuthConstants.TOKEN_URL)
            .header("Content-Type", "application/x-www-form-urlencoded")
            .header("Accept", "application/json")
            .header("User-Agent", buildUserAgent())
            .post(form.toRequestBody("application/x-www-form-urlencoded".toMediaType()))
            .build()
        val response = httpClient.newCall(request).execute()
        val body = response.body?.string().orEmpty()
        if (!response.isSuccessful) {
            if (response.code == 401 || response.code == 400) {
                throw SuperGrokAuthRefreshError.classified(body)
            }
            throw IllegalStateException("refresh token endpoint returned status ${response.code}: $body")
        }
        return json.decodeFromString(SuperGrokTokenResponse.serializer(), body)
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
                        val uri = Uri.parse("http://127.0.0.1$path")
                        val returnedState = uri.getQueryParameter("state")
                        val code = uri.getQueryParameter("code")
                        val error = uri.getQueryParameter("error")
                        if (uri.path == SuperGrokAuthConstants.OAUTH_REDIRECT_PATH) {
                            if (!error.isNullOrBlank()) {
                                val description = uri.getQueryParameter("error_description") ?: error
                                throw IllegalStateException(description)
                            }
                            if (returnedState == expectedState && !code.isNullOrBlank()) {
                                respondHtml(socket, "SuperGrok Auth login completed. You can return to the app.")
                                result = code
                            } else {
                                respondHtml(socket, "Invalid login state or missing code.")
                            }
                        } else {
                            respondStatus(socket, 404, "Not Found")
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

    private fun bindServer(preferredPort: Int): Pair<ServerSocket, Int> {
        val server = ServerSocket()
        server.reuseAddress = true
        val loopback = InetAddress.getByName(SuperGrokAuthConstants.OAUTH_HOST)
        val bound = runCatching {
            server.bind(InetSocketAddress(loopback, preferredPort))
        }
        if (bound.isFailure) {
            server.close()
            throw SuperGrokAuthCallbackError.portInUse()
        }
        return server to server.localPort
    }

    private fun launchBrowser(url: String) {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        context.startActivity(intent)
    }

    private fun buildAuthorizeUrl(
        redirectUri: String,
        pkce: PkceCodes,
        state: String,
        nonce: String
    ): String = SuperGrokAuthRepository.buildAuthorizeUrl(
        redirectUri = redirectUri,
        verifier = pkce.verifier,
        challenge = pkce.challenge,
        state = state,
        nonce = nonce
    )

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

    private fun buildUserAgent(): String = "YamabikoChat/Android"

    private fun expiresAtEpochMs(expiresIn: Int?): Long? {
        if (expiresIn == null || expiresIn <= 0) return null
        return System.currentTimeMillis() + expiresIn * 1_000L
    }

    private fun positiveSecondsToMs(value: Int?, defaultMs: Long): Long {
        if (value == null || value <= 0) return defaultMs
        return value * 1_000L
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
}