package com.porarri.yamabikochat.data.auth

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.util.Base64

@Serializable
data class CodexAuthJson(
    @SerialName("OPENAI_API_KEY")
    val openaiApiKey: String? = null,
    val tokens: CodexTokenData? = null,
    @SerialName("last_refresh")
    val lastRefresh: String? = null
)

@Serializable
data class CodexTokenData(
    @SerialName("id_token")
    val idToken: String,
    @SerialName("access_token")
    val accessToken: String,
    @SerialName("refresh_token")
    val refreshToken: String,
    @SerialName("account_id")
    val accountId: String? = null
)

data class CodexIdTokenInfo(
    val email: String? = null,
    val planType: String? = null,
    val accountId: String? = null,
    val rawJwt: String
)

object CodexJwtParser {
    private val json = Json { ignoreUnknownKeys = true }

    fun parseIdToken(rawJwt: String): CodexIdTokenInfo? {
        val payloadJson = parsePayload(rawJwt) ?: return null
        val email = payloadJson["email"]?.jsonPrimitive?.contentOrNull
        val auth = payloadJson["https://api.openai.com/auth"]?.jsonObject
        val planType = auth?.get("chatgpt_plan_type")?.jsonPrimitive?.contentOrNull
        val accountId = auth?.get("chatgpt_account_id")?.jsonPrimitive?.contentOrNull

        return CodexIdTokenInfo(
            email = email,
            planType = planType,
            accountId = accountId,
            rawJwt = rawJwt
        )
    }

    fun extractAccountId(rawJwt: String): String? {
        val payloadJson = parsePayload(rawJwt) ?: return null
        val auth = payloadJson["https://api.openai.com/auth"]?.jsonObject
        return auth?.get("chatgpt_account_id")?.jsonPrimitive?.contentOrNull
    }

    private fun parsePayload(rawJwt: String): JsonObject? {
        val parts = rawJwt.split('.')
        if (parts.size < 3) return null
        val payload = parts[1]
        val decoded = runCatching { base64UrlDecode(payload) }.getOrNull() ?: return null
        return runCatching {
            json.parseToJsonElement(decoded.decodeToString()).jsonObject
        }.getOrNull()
    }

    private fun base64UrlDecode(input: String): ByteArray {
        val padding = (4 - input.length % 4) % 4
        val padded = input + "=".repeat(padding)
        return Base64.getUrlDecoder().decode(padded)
    }
}

data class CodexAuthState(
    val isLoggedIn: Boolean = false,
    val email: String? = null,
    val planType: String? = null,
    val accountId: String? = null,
    val hasApiKey: Boolean = false,
    val lastRefreshISO8601: String? = null
)

data class CodexBearerToken(
    val token: String,
    val isApiKey: Boolean = false,
    val accountId: String? = null
)

data class CodexRateLimitWindow(
    val usedPercent: Double? = null,
    val limitWindowSeconds: Int? = null,
    val resetAtEpochSeconds: Long? = null
)

data class CodexCreditsStatus(
    val hasCredits: Boolean = false,
    val unlimited: Boolean = false,
    val balance: String? = null
)

data class CodexUsageStatus(
    val planType: String? = null,
    val primaryWindow: CodexRateLimitWindow? = null,
    val secondaryWindow: CodexRateLimitWindow? = null,
    val credits: CodexCreditsStatus? = null
)
