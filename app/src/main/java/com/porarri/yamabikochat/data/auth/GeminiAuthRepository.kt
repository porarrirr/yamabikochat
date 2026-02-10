package com.porarri.yamabikochat.data.auth

import android.content.Context
import android.content.Intent
import android.net.Uri
import com.porarri.yamabikochat.BuildConfig
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import com.porarri.yamabikochat.utils.SecurePreferencesManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonPrimitive
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
import java.security.SecureRandom
import java.time.Duration
import java.time.Instant
import java.util.Base64

class GeminiAuthRepository(
    private val context: Context,
    private val httpClient: OkHttpClient = OkHttpClient()
) {
    companion object {
        private const val AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
        private const val TOKEN_URL = "https://oauth2.googleapis.com/token"
        private const val USERINFO_URL = "https://www.googleapis.com/oauth2/v2/userinfo"
        private const val CODE_ASSIST_ENDPOINT = "https://cloudcode-pa.googleapis.com"
        private const val CODE_ASSIST_API_VERSION = "v1internal"
        private const val DEFAULT_PORT = 1456
        private const val TOKEN_REFRESH_BUFFER_SECONDS = 60L
        private const val REFRESH_FALLBACK_MINUTES = 45L
        private val OAUTH_SCOPE = listOf(
            "https://www.googleapis.com/auth/cloud-platform",
            "https://www.googleapis.com/auth/userinfo.email",
            "https://www.googleapis.com/auth/userinfo.profile"
        )
    }

    private val json = Json { ignoreUnknownKeys = true }
    private val securePrefs = SecurePreferencesManager.getInstance(context)
    private val _state = MutableStateFlow(readState())
    val state: StateFlow<GeminiAuthState> = _state.asStateFlow()
    private val authDns: Dns by lazy { buildAuthDns(httpClient) }
    private val authHttpClient: OkHttpClient by lazy {
        httpClient.newBuilder()
            .dns(authDns)
            .build()
    }

    private fun oauthClientId(): String = BuildConfig.GEMINI_OAUTH_CLIENT_ID.trim()

    private fun oauthClientSecret(): String = BuildConfig.GEMINI_OAUTH_CLIENT_SECRET.trim()

    private fun requireOauthConfig() {
        val clientId = oauthClientId()
        val clientSecret = oauthClientSecret()
        require(clientId.isNotBlank()) {
            "GEMINI_OAUTH_CLIENT_ID is not set. Add it to local.properties (see local.properties.example)."
        }
        require(clientSecret.isNotBlank()) {
            "GEMINI_OAUTH_CLIENT_SECRET is not set. Add it to local.properties (see local.properties.example)."
        }
    }

    suspend fun login(): Result<GeminiAuthState> = withContext(Dispatchers.IO) {
        runCatching {
            requireOauthConfig()
            val stateToken = generateState()
            val (server, actualPort) = bindServer(DEFAULT_PORT)
            val redirectUri = "http://127.0.0.1:$actualPort/oauth2callback"
            val authUrl = buildAuthorizeUrl(redirectUri, stateToken)
            DiagnosticsLogger.log("Gemini auth login start port=$actualPort")
            ensureAuthHostsResolvable()

            withContext(Dispatchers.Main) {
                launchBrowser(authUrl)
            }

            val code = withTimeout(5 * 60 * 1000L) {
                awaitAuthCode(server, stateToken)
            }

            val tokenResponse = exchangeCodeForTokens(code, redirectUri)
            persistTokens(tokenResponse)
            _state.value = readState()

            val email = fetchUserEmail(tokenResponse.accessToken)
            val userDataResult = runCatching {
                resolveUserData(tokenResponse.accessToken)
            }
            email?.let { updateAuthMetadata(email = it) }
            userDataResult.onSuccess { data ->
                updateAuthMetadata(
                    projectId = data.projectId,
                    userTier = data.userTier,
                    userTierName = data.userTierName
                )
            }.onFailure { err ->
                DiagnosticsLogger.log("Gemini auth user setup failed", err)
            }

            val updated = readState()
            _state.value = updated

            userDataResult.getOrNull()?.let {
                DiagnosticsLogger.log("Gemini auth login completed projectId=${it.projectId} tier=${it.userTier}")
            }

            if (userDataResult.isFailure) {
                throw userDataResult.exceptionOrNull() ?: IllegalStateException("Gemini auth setup failed")
            }

            updated
        }.onFailure { err ->
            DiagnosticsLogger.log("Gemini auth login failed", err)
        }
    }

    suspend fun logout(): Result<GeminiAuthState> = withContext(Dispatchers.IO) {
        securePrefs.clearGeminiAuthJson()
        val updated = readState()
        _state.value = updated
        DiagnosticsLogger.log("Gemini auth logout completed")
        Result.success(updated)
    }

    suspend fun refreshIfNeeded(force: Boolean = false): Result<GeminiAuthState> = withContext(Dispatchers.IO) {
        val auth = readAuthJson() ?: return@withContext Result.success(readState())
        val tokens = auth.tokens ?: return@withContext Result.success(readState())
        val now = Instant.now()

        val expiresAt = auth.accessExpiresAt?.let { runCatching { Instant.parse(it) }.getOrNull() }
        val shouldRefresh = if (force) {
            true
        } else if (expiresAt != null) {
            now.isAfter(expiresAt.minusSeconds(TOKEN_REFRESH_BUFFER_SECONDS))
        } else {
            val lastRefresh = auth.lastRefresh?.let { runCatching { Instant.parse(it) }.getOrNull() }
            lastRefresh == null || Duration.between(lastRefresh, now).toMinutes() >= REFRESH_FALLBACK_MINUTES
        }

        if (!shouldRefresh) return@withContext Result.success(readState())

        val refreshToken = tokens.refreshToken?.takeIf { it.isNotBlank() }
            ?: return@withContext Result.failure(IllegalStateException("Refresh token is missing. Please sign in again."))

        val refreshResult = refreshTokens(refreshToken)
        return@withContext refreshResult.map {
            val updated = readState()
            _state.value = updated
            DiagnosticsLogger.log("Gemini auth refresh completed")
            updated
        }
    }

    suspend fun getAccessToken(): String? = withContext(Dispatchers.IO) {
        refreshIfNeeded()
        val auth = readAuthJson() ?: return@withContext null
        auth.tokens?.accessToken?.trim()?.takeIf { it.isNotBlank() }
    }

    suspend fun getBearerToken(): GeminiBearerToken? = withContext(Dispatchers.IO) {
        refreshIfNeeded()
        val auth = readAuthJson() ?: return@withContext null
        val token = auth.tokens?.accessToken?.trim().orEmpty()
        if (token.isBlank()) return@withContext null
        GeminiBearerToken(
            token = token,
            projectId = auth.projectId,
            userTier = auth.userTier,
            userEmail = auth.userEmail
        )
    }

    fun hasAuthToken(): Boolean {
        val auth = readAuthJson() ?: return false
        return auth.tokens?.accessToken?.isNotBlank() == true
    }

    fun saveProjectId(projectId: String?): Boolean {
        val normalized = projectId?.trim()?.takeIf { it.isNotBlank() }
        updateAuthMetadata(projectId = normalized)
        return true
    }

    suspend fun retrieveUserQuota(): Result<GeminiUserQuota> = withContext(Dispatchers.IO) {
        refreshIfNeeded()
        val auth = readAuthJson()
            ?: return@withContext Result.failure(IllegalStateException("Not signed in."))
        val token = auth.tokens?.accessToken?.trim().orEmpty()
        if (token.isBlank()) {
            return@withContext Result.failure(IllegalStateException("Access token is missing. Please sign in again."))
        }
        val projectId = auth.projectId?.trim().orEmpty()
        if (projectId.isBlank()) {
            return@withContext Result.failure(
                IllegalStateException("Project ID is required to retrieve rate limits. Please set it in settings.")
            )
        }

        val payload = RetrieveUserQuotaRequest(project = projectId)
        val body = json.encodeToString(RetrieveUserQuotaRequest.serializer(), payload)
            .toRequestBody("application/json".toMediaType())
        val httpRequest = Request.Builder()
            .url(codeAssistUrl("retrieveUserQuota"))
            .header("Authorization", "Bearer $token")
            .header("Content-Type", "application/json")
            .post(body)
            .build()

        val response = authHttpClient.newCall(httpRequest).execute()
        response.use { resp ->
            val raw = resp.body?.string().orEmpty()
            if (!resp.isSuccessful) {
                DiagnosticsLogger.log(
                    "Gemini auth retrieveUserQuota failed status=${resp.code} body=${sanitizeLogBody(raw)}"
                )
                val message = extractGoogleErrorMessage(raw)
                    ?: "retrieveUserQuota failed with status ${resp.code}"
                return@withContext Result.failure(IllegalStateException(message))
            }
            val decoded = json.decodeFromString(RetrieveUserQuotaResponse.serializer(), raw)
            val buckets = decoded.buckets.orEmpty().map { bucket ->
                GeminiQuotaBucket(
                    modelId = bucket.modelId,
                    tokenType = bucket.tokenType,
                    remainingAmount = bucket.remainingAmount,
                    remainingFraction = bucket.remainingFraction,
                    resetTime = bucket.resetTime
                )
            }
            Result.success(GeminiUserQuota(buckets))
        }
    }

    private fun readAuthJson(): GeminiAuthJson? {
        val raw = securePrefs.getGeminiAuthJson() ?: return null
        return runCatching { json.decodeFromString(GeminiAuthJson.serializer(), raw) }.getOrNull()
    }

    private fun readState(): GeminiAuthState {
        val auth = readAuthJson()
        val tokens = auth?.tokens
        return GeminiAuthState(
            isLoggedIn = tokens != null,
            email = auth?.userEmail,
            projectId = auth?.projectId,
            userTier = auth?.userTier,
            userTierName = auth?.userTierName,
            hasAccessToken = tokens?.accessToken?.isNotBlank() == true,
            lastRefresh = auth?.lastRefresh
        )
    }

    private fun persistTokens(tokens: GeminiTokenData) {
        val existing = readAuthJson()
        val expiresAt = tokens.expiresIn?.let { Instant.now().plusSeconds(it.toLong()).toString() }
        val payload = GeminiAuthJson(
            tokens = tokens,
            lastRefresh = Instant.now().toString(),
            accessExpiresAt = expiresAt ?: existing?.accessExpiresAt,
            userEmail = existing?.userEmail,
            projectId = existing?.projectId,
            userTier = existing?.userTier,
            userTierName = existing?.userTierName
        )
        val raw = json.encodeToString(GeminiAuthJson.serializer(), payload)
        securePrefs.storeGeminiAuthJson(raw)
    }

    private fun updateAuthMetadata(
        email: String? = null,
        projectId: String? = null,
        userTier: String? = null,
        userTierName: String? = null
    ) {
        val current = readAuthJson() ?: GeminiAuthJson()
        val updated = current.copy(
            userEmail = email ?: current.userEmail,
            projectId = projectId ?: current.projectId,
            userTier = userTier ?: current.userTier,
            userTierName = userTierName ?: current.userTierName
        )
        val raw = json.encodeToString(GeminiAuthJson.serializer(), updated)
        securePrefs.storeGeminiAuthJson(raw)
        _state.value = readState()
    }

    private fun buildAuthorizeUrl(redirectUri: String, state: String): String {
        val params = listOf(
            "client_id" to oauthClientId(),
            "redirect_uri" to redirectUri,
            "response_type" to "code",
            "access_type" to "offline",
            "scope" to OAUTH_SCOPE.joinToString(" "),
            "state" to state
        )
        val qs = params.joinToString("&") { (k, v) -> "$k=${encode(v)}" }
        return "$AUTH_URL?$qs"
    }

    private fun exchangeCodeForTokens(code: String, redirectUri: String): GeminiTokenData {
        requireOauthConfig()
        val form = "grant_type=authorization_code" +
            "&code=${encode(code)}" +
            "&redirect_uri=${encode(redirectUri)}" +
            "&client_id=${encode(oauthClientId())}" +
            "&client_secret=${encode(oauthClientSecret())}"
        val requestBody = form.toRequestBody("application/x-www-form-urlencoded".toMediaType())
        val request = Request.Builder()
            .url(TOKEN_URL)
            .header("Content-Type", "application/x-www-form-urlencoded")
            .post(requestBody)
            .build()
        val response = authHttpClient.newCall(request).execute()
        response.use { resp ->
            val payload = resp.body?.string().orEmpty()
            if (!resp.isSuccessful) {
                DiagnosticsLogger.log("Gemini auth token exchange failed status=${resp.code} body=${sanitizeLogBody(payload)}")
                throw IllegalStateException("token endpoint returned status ${resp.code}")
            }
            return json.decodeFromString(GeminiTokenData.serializer(), payload)
        }
    }

    private fun refreshTokens(refreshToken: String): Result<Unit> {
        requireOauthConfig()
        val form = "grant_type=refresh_token" +
            "&refresh_token=${encode(refreshToken)}" +
            "&client_id=${encode(oauthClientId())}" +
            "&client_secret=${encode(oauthClientSecret())}"
        val requestBody = form.toRequestBody("application/x-www-form-urlencoded".toMediaType())
        val request = Request.Builder()
            .url(TOKEN_URL)
            .header("Content-Type", "application/x-www-form-urlencoded")
            .post(requestBody)
            .build()
        val response = authHttpClient.newCall(request).execute()
        response.use { resp ->
            val payload = resp.body?.string().orEmpty()
            if (!resp.isSuccessful) {
                val message = extractGoogleErrorMessage(payload) ?: "Failed to refresh token: ${resp.code}"
                DiagnosticsLogger.log("Gemini auth refresh failed code=${resp.code} message=$message")
                return Result.failure(IllegalStateException(message))
            }
            val refreshed = json.decodeFromString(GeminiTokenData.serializer(), payload)
            val merged = mergeTokens(refreshed)
            persistTokens(merged)
            return Result.success(Unit)
        }
    }

    private fun mergeTokens(refreshed: GeminiTokenData): GeminiTokenData {
        val current = readAuthJson()?.tokens ?: return refreshed
        return current.copy(
            accessToken = refreshed.accessToken.ifBlank { current.accessToken },
            refreshToken = refreshed.refreshToken ?: current.refreshToken,
            idToken = refreshed.idToken ?: current.idToken,
            expiresIn = refreshed.expiresIn ?: current.expiresIn,
            scope = refreshed.scope ?: current.scope,
            tokenType = refreshed.tokenType ?: current.tokenType
        )
    }

    private fun fetchUserEmail(accessToken: String): String? {
        val request = Request.Builder()
            .url(USERINFO_URL)
            .header("Authorization", "Bearer $accessToken")
            .build()
        val response = authHttpClient.newCall(request).execute()
        response.use { resp ->
            if (!resp.isSuccessful) {
                DiagnosticsLogger.log("Gemini auth userinfo failed status=${resp.code}")
                return null
            }
            val payload = resp.body?.string().orEmpty()
            return runCatching {
                val obj = JSONObject(payload)
                obj.optString("email").takeIf { it.isNotBlank() }
            }.getOrNull()
        }
    }

    private data class UserData(
        val projectId: String,
        val userTier: String,
        val userTierName: String?
    )

    private fun resolveUserData(accessToken: String): UserData {
        val projectOverride = readAuthJson()?.projectId
        val metadata = ClientMetadata(
            ideType = "IDE_UNSPECIFIED",
            platform = "PLATFORM_UNSPECIFIED",
            pluginType = "GEMINI",
            duetProject = projectOverride
        )
        val loadResponse = loadCodeAssist(accessToken, LoadCodeAssistRequest(projectOverride, metadata))
        loadResponse.currentTier?.let { tier ->
            val projectId = loadResponse.cloudaicompanionProject
                ?: projectOverride
                ?: throw IllegalStateException(
                    "Google Workspace account requires a Cloud project ID. Please set it in Gemini Auth settings."
                )
            return UserData(
                projectId = projectId,
                userTier = tier.id,
                userTierName = tier.name
            )
        }

        val tier = loadResponse.allowedTiers?.firstOrNull { it.isDefault == true }
            ?: GeminiUserTier(id = "legacy-tier")

        val isFreeTier = tier.id == "free-tier"
        val projectId = if (isFreeTier) null else projectOverride
        if (!isFreeTier && projectId.isNullOrBlank()) {
            throw IllegalStateException(
                "Google Workspace account requires a Cloud project ID. Please set it in Gemini Auth settings."
            )
        }

        val onboardRequest = OnboardUserRequest(
            tierId = tier.id,
            cloudaicompanionProject = projectId,
            metadata = metadata
        )
        val operation = onboardUser(accessToken, onboardRequest)
        val finalOp = if (operation.done == true || operation.name.isNullOrBlank()) {
            operation
        } else {
            pollOperation(accessToken, operation.name)
        }
        val finalProjectId = finalOp.response?.cloudaicompanionProject?.id
            ?: projectId
            ?: throw IllegalStateException("Failed to obtain Cloud project ID for Gemini Auth.")

        return UserData(
            projectId = finalProjectId,
            userTier = tier.id,
            userTierName = tier.name
        )
    }

    private fun loadCodeAssist(accessToken: String, request: LoadCodeAssistRequest): LoadCodeAssistResponse {
        val body = json.encodeToString(LoadCodeAssistRequest.serializer(), request)
            .toRequestBody("application/json".toMediaType())
        val httpRequest = Request.Builder()
            .url(codeAssistUrl("loadCodeAssist"))
            .header("Authorization", "Bearer $accessToken")
            .header("Content-Type", "application/json")
            .post(body)
            .build()
        val response = authHttpClient.newCall(httpRequest).execute()
        response.use { resp ->
            val payload = resp.body?.string().orEmpty()
            if (!resp.isSuccessful) {
                DiagnosticsLogger.log(
                    "Gemini auth loadCodeAssist failed status=${resp.code} body=${sanitizeLogBody(payload)}"
                )
                throw IllegalStateException("loadCodeAssist failed with status ${resp.code}")
            }
            return json.decodeFromString(LoadCodeAssistResponse.serializer(), payload)
        }
    }

    private fun onboardUser(accessToken: String, request: OnboardUserRequest): LongRunningOperationResponse {
        val body = json.encodeToString(OnboardUserRequest.serializer(), request)
            .toRequestBody("application/json".toMediaType())
        val httpRequest = Request.Builder()
            .url(codeAssistUrl("onboardUser"))
            .header("Authorization", "Bearer $accessToken")
            .header("Content-Type", "application/json")
            .post(body)
            .build()
        val response = authHttpClient.newCall(httpRequest).execute()
        response.use { resp ->
            val payload = resp.body?.string().orEmpty()
            if (!resp.isSuccessful) {
                DiagnosticsLogger.log(
                    "Gemini auth onboardUser failed status=${resp.code} body=${sanitizeLogBody(payload)}"
                )
                throw IllegalStateException("onboardUser failed with status ${resp.code}")
            }
            return json.decodeFromString(LongRunningOperationResponse.serializer(), payload)
        }
    }

    private fun pollOperation(accessToken: String, name: String): LongRunningOperationResponse {
        var current = getOperation(accessToken, name)
        var attempts = 0
        while (current.done != true && attempts < 6) {
            Thread.sleep(5000)
            attempts += 1
            current = getOperation(accessToken, name)
        }
        return current
    }

    private fun getOperation(accessToken: String, name: String): LongRunningOperationResponse {
        val httpRequest = Request.Builder()
            .url(codeAssistUrl(name, isOperation = true))
            .header("Authorization", "Bearer $accessToken")
            .header("Content-Type", "application/json")
            .get()
            .build()
        val response = authHttpClient.newCall(httpRequest).execute()
        response.use { resp ->
            val payload = resp.body?.string().orEmpty()
            if (!resp.isSuccessful) {
                DiagnosticsLogger.log(
                    "Gemini auth getOperation failed status=${resp.code} body=${sanitizeLogBody(payload)}"
                )
                throw IllegalStateException("getOperation failed with status ${resp.code}")
            }
            return json.decodeFromString(LongRunningOperationResponse.serializer(), payload)
        }
    }

    private fun codeAssistUrl(method: String, isOperation: Boolean = false): String {
        val base = "${CODE_ASSIST_ENDPOINT}/${CODE_ASSIST_API_VERSION}"
        return if (isOperation) {
            "$base/$method"
        } else {
            "$base:$method"
        }
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
                        val error = uri.getQueryParameter("error")
                        val errorDescription = uri.getQueryParameter("error_description")
                        if (uri.path == "/oauth2callback" && !error.isNullOrBlank()) {
                            respondHtml(socket, "Login failed: $errorDescription")
                            throw IllegalStateException("OAuth error: $error ($errorDescription)")
                        }
                        if (uri.path == "/oauth2callback" && state == expectedState && !code.isNullOrBlank()) {
                            respondHtml(socket, "Gemini Auth login completed. You can return to the app.")
                            result = code
                        } else if (uri.path == "/oauth2callback") {
                            respondHtml(socket, "Invalid login state or missing code.")
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

    private fun generateState(): String {
        val bytes = ByteArray(32)
        SecureRandom().nextBytes(bytes)
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)
    }

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

    private fun sanitizeLogBody(body: String, maxChars: Int = 400): String {
        val trimmed = body.trim()
        if (trimmed.isBlank()) return ""
        val sanitized = sanitizeSecrets(trimmed)
        return if (sanitized.length <= maxChars) sanitized else sanitized.take(maxChars) + "..."
    }

    private fun sanitizeSecrets(raw: String): String {
        val jsonSanitized = runCatching {
            val element = json.parseToJsonElement(raw)
            val sanitized = sanitizeJsonElement(element)
            json.encodeToString(JsonElement.serializer(), sanitized)
        }.getOrNull()

        return sanitizeTokenLikeStrings(jsonSanitized ?: raw)
    }

    private fun sanitizeJsonElement(element: JsonElement): JsonElement {
        val redactedKeys = setOf(
            "access_token",
            "refresh_token",
            "id_token",
            "client_secret",
            "token",
            "api_key",
            "authorization"
        )

        return when (element) {
            is JsonObject -> {
                val updated = element.mapValues { (key, value) ->
                    if (key.lowercase() in redactedKeys) {
                        val replacement = if (value is JsonPrimitive && value.isString) {
                            "<redacted:${value.jsonPrimitive.content.length}>"
                        } else {
                            "<redacted>"
                        }
                        JsonPrimitive(replacement)
                    } else {
                        sanitizeJsonElement(value)
                    }
                }
                JsonObject(updated)
            }
            is JsonArray -> JsonArray(element.map { sanitizeJsonElement(it) })
            else -> element
        }
    }

    private fun sanitizeTokenLikeStrings(value: String): String {
        var sanitized = value
        sanitized = sanitized.replace(Regex("(?i)\\bBearer\\s+[-._A-Za-z0-9]+\\b"), "Bearer <redacted>")
        sanitized = sanitized.replace(
            Regex("eyJ[-_A-Za-z0-9]{10,}\\.[-_A-Za-z0-9]{10,}\\.[-_A-Za-z0-9]{10,}"),
            "<redacted_jwt>"
        )
        return sanitized
    }

    private fun ensureAuthHostsResolvable() {
        val hosts = listOf(AUTH_URL, TOKEN_URL, USERINFO_URL, CODE_ASSIST_ENDPOINT)
            .mapNotNull { Uri.parse(it).host }
            .distinct()
        hosts.forEach { host ->
            runCatching { authDns.lookup(host) }.onFailure { err ->
                throw IllegalStateException(buildNetworkErrorMessage(host, err), err)
            }
        }
    }

    private fun buildNetworkErrorMessage(host: String, err: Throwable): String {
        val root = generateSequence(err) { it.cause }.last()
        val isUnknownHost = root is UnknownHostException ||
            root.javaClass.name.contains("GaiException") ||
            root.message?.contains("Unable to resolve host", ignoreCase = true) == true
        return if (isUnknownHost) {
            "Network error: unable to resolve $host. Check Private DNS/VPN or set Private DNS to dns.google or 1dot1dot1dot1.cloudflare-dns.com."
        } else {
            "Network error during Gemini auth. Please check your connection and try again."
        }
    }

    private fun extractGoogleErrorMessage(body: String): String? {
        if (body.isBlank()) return null
        return runCatching {
            val obj = JSONObject(body)
            val error = obj.opt("error")
            when (error) {
                is JSONObject -> error.optString("message")
                is String -> error
                else -> obj.optString("error_description")
            }.takeIf { it.isNotBlank() }
        }.getOrNull()
    }

    data class GeminiBearerToken(
        val token: String,
        val projectId: String? = null,
        val userTier: String? = null,
        val userEmail: String? = null
    )

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
                    DiagnosticsLogger.log("Gemini auth DNS fallback succeeded index=$index host=$hostname")
                    return result
                } catch (err: Exception) {
                    errors.add(err)
                }
            }
            if (primaryFailure is UnknownHostException) {
                errors.drop(1).forEach { primaryFailure.addSuppressed(it) }
            }
            DiagnosticsLogger.log("Gemini auth DNS fallback failed host=$hostname attempts=${errors.size}")
            throw primaryFailure
        }
    }

    @Serializable
    private data class LoadCodeAssistRequest(
        @SerialName("cloudaicompanionProject")
        val cloudaicompanionProject: String? = null,
        val metadata: ClientMetadata
    )

    @Serializable
    private data class ClientMetadata(
        val ideType: String? = null,
        val platform: String? = null,
        val pluginType: String? = null,
        val duetProject: String? = null
    )

    @Serializable
    private data class LoadCodeAssistResponse(
        val currentTier: GeminiUserTier? = null,
        val allowedTiers: List<GeminiUserTier>? = null,
        @SerialName("cloudaicompanionProject")
        val cloudaicompanionProject: String? = null
    )

    @Serializable
    private data class GeminiUserTier(
        val id: String,
        val name: String? = null,
        val isDefault: Boolean? = null,
        val userDefinedCloudaicompanionProject: Boolean? = null
    )

    @Serializable
    private data class OnboardUserRequest(
        val tierId: String?,
        @SerialName("cloudaicompanionProject")
        val cloudaicompanionProject: String? = null,
        val metadata: ClientMetadata? = null
    )

    @Serializable
    private data class LongRunningOperationResponse(
        val name: String? = null,
        val done: Boolean? = null,
        val response: OnboardUserResponse? = null
    )

    @Serializable
    private data class OnboardUserResponse(
        @SerialName("cloudaicompanionProject")
        val cloudaicompanionProject: CloudProject? = null
    )

    @Serializable
    private data class CloudProject(
        val id: String? = null,
        val name: String? = null
    )

    @Serializable
    private data class RetrieveUserQuotaRequest(
        val project: String,
        val userAgent: String? = null
    )

    @Serializable
    private data class RetrieveUserQuotaResponse(
        val buckets: List<GeminiQuotaBucketResponse>? = null
    )

    @Serializable
    private data class GeminiQuotaBucketResponse(
        val remainingAmount: String? = null,
        val remainingFraction: Double? = null,
        val resetTime: String? = null,
        val tokenType: String? = null,
        val modelId: String? = null
    )
}
