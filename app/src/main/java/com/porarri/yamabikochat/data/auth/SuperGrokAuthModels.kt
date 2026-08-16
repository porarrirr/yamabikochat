package com.porarri.yamabikochat.data.auth

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.util.Base64

data class SuperGrokIdTokenInfo(
    val email: String? = null
)

object SuperGrokJwtParser {
    private val json = Json { ignoreUnknownKeys = true }

    fun parseIdToken(rawJwt: String): SuperGrokIdTokenInfo? {
        val payloadJson = parsePayload(rawJwt) ?: return null
        val email = payloadJson["email"]?.jsonPrimitive?.contentOrNull
        return SuperGrokIdTokenInfo(email = email)
    }

    fun accessTokenIsExpiring(
        token: String?,
        skewMs: Long = SuperGrokAuthConstants.ACCESS_TOKEN_REFRESH_SKEW_MS
    ): Boolean {
        if (token.isNullOrBlank()) return false
        val parts = token.split('.')
        if (parts.size < 2) return false
        val payloadJson = parsePayload(parts[1]) ?: return false
        val exp = payloadJson["exp"]?.jsonPrimitive?.contentOrNull?.toLongOrNull() ?: return false
        val expiresAtMs = exp * 1_000L
        val nowMs = System.currentTimeMillis()
        return expiresAtMs <= nowMs + maxOf(0L, skewMs)
    }

    private fun parsePayload(rawJwt: String): JsonObject? {
        val parts = rawJwt.split('.')
        val payload = if (parts.size >= 3) parts[1] else rawJwt
        val decoded = runCatching { base64UrlDecode(payload) }.getOrNull() ?: return null
        return runCatching {
            json.parseToJsonElement(decoded.decodeToString()).jsonObject
        }.getOrNull()
    }

    private fun base64UrlDecode(input: String): ByteArray {
        var normalized = input.replace('-', '+').replace('_', '/')
        val padding = (4 - normalized.length % 4) % 4
        normalized += "=".repeat(padding)
        return Base64.getDecoder().decode(normalized)
    }
}

object SuperGrokAuthConstants {
    const val CLIENT_ID = "b1a00492-073a-47ea-816f-4c329264a828"
    const val AUTHORIZE_URL = "https://auth.x.ai/oauth2/authorize"
    const val TOKEN_URL = "https://auth.x.ai/oauth2/token"
    const val DEVICE_AUTHORIZATION_URL = "https://auth.x.ai/oauth2/device/code"
    const val DEVICE_CODE_GRANT_TYPE = "urn:ietf:params:oauth:grant-type:device_code"
    const val SCOPE = "openid profile email offline_access grok-cli:access api:access"
    const val OAUTH_HOST = "127.0.0.1"
    const val OAUTH_PORT = 56_121
    const val OAUTH_REDIRECT_PATH = "/callback"
    const val REDIRECT_URI = "http://$OAUTH_HOST:$OAUTH_PORT$OAUTH_REDIRECT_PATH"
    const val AUTH_STORAGE_KEY = "supergrok_auth_json"
    const val API_BASE_URL = "https://api.x.ai/v1/"
    const val ACCESS_TOKEN_REFRESH_SKEW_MS = 120_000L
    const val DEVICE_CODE_DEFAULT_INTERVAL_MS = 5_000L
    const val DEVICE_CODE_MIN_INTERVAL_MS = 1_000L
    const val DEVICE_CODE_SLOW_DOWN_INCREMENT_MS = 5_000L
    const val DEVICE_CODE_DEFAULT_EXPIRES_MS = 5 * 60 * 1_000L
    const val DEVICE_CODE_POLLING_SAFETY_MARGIN_MS = 3_000L
}

sealed class SuperGrokAuthRefreshError(
    override val message: String
) : Exception(message) {
    val isUnrecoverable: Boolean
        get() = this is Expired || this is Reused || this is Invalidated

    data object Expired : SuperGrokAuthRefreshError(
        "Your access token could not be refreshed because your refresh token has expired. Please log out and sign in again."
    )

    data object Reused : SuperGrokAuthRefreshError(
        "Your access token could not be refreshed because your refresh token was already used. Please log out and sign in again."
    )

    data object Invalidated : SuperGrokAuthRefreshError(
        "Your access token could not be refreshed because your refresh token was revoked. Please log out and sign in again."
    )

    data object MissingRefreshToken : SuperGrokAuthRefreshError(
        "Refresh token is missing. Please sign in again."
    )

    data object Unknown : SuperGrokAuthRefreshError(
        "Your access token could not be refreshed. Please log out and sign in again."
    )

    companion object {
        private val errorJson = Json { ignoreUnknownKeys = true }

        fun classified(body: String): SuperGrokAuthRefreshError {
            return when (extractErrorCode(body)?.lowercase()) {
                "invalid_grant", "refresh_token_expired" -> Expired
                "refresh_token_reused" -> Reused
                "refresh_token_invalidated" -> Invalidated
                else -> Unknown
            }
        }

        fun extractErrorCode(body: String): String? {
            if (body.isBlank()) return null
            return runCatching {
                val obj = errorJson.parseToJsonElement(body).jsonObject
                obj["error"]?.jsonPrimitive?.contentOrNull
                    ?: obj["code"]?.jsonPrimitive?.contentOrNull
            }.getOrNull()?.takeIf { it.isNotBlank() }
        }
    }
}

data class SuperGrokDeviceCodeChallenge(
    val verificationUri: String,
    val userCode: String,
    val browserUrl: String
)

data class SuperGrokAuthState(
    val isLoggedIn: Boolean = false,
    val email: String? = null,
    val lastRefreshIso8601: String? = null,
    val pendingDeviceCode: SuperGrokDeviceCodeChallenge? = null
)
