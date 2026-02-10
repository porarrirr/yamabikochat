package com.porarri.yamabikochat.data.auth

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

@Serializable
data class GeminiAuthJson(
    val tokens: GeminiTokenData? = null,
    @SerialName("last_refresh")
    val lastRefresh: String? = null,
    @SerialName("access_expires_at")
    val accessExpiresAt: String? = null,
    @SerialName("user_email")
    val userEmail: String? = null,
    @SerialName("project_id")
    val projectId: String? = null,
    @SerialName("user_tier")
    val userTier: String? = null,
    @SerialName("user_tier_name")
    val userTierName: String? = null
)

@Serializable
data class GeminiTokenData(
    @SerialName("access_token")
    val accessToken: String,
    @SerialName("refresh_token")
    val refreshToken: String? = null,
    @SerialName("id_token")
    val idToken: String? = null,
    @SerialName("expires_in")
    val expiresIn: Int? = null,
    val scope: String? = null,
    @SerialName("token_type")
    val tokenType: String? = null
)

data class GeminiAuthState(
    val isLoggedIn: Boolean = false,
    val email: String? = null,
    val projectId: String? = null,
    val userTier: String? = null,
    val userTierName: String? = null,
    val hasAccessToken: Boolean = false,
    val lastRefresh: String? = null
)

data class GeminiQuotaBucket(
    val modelId: String? = null,
    val tokenType: String? = null,
    val remainingAmount: String? = null,
    val remainingFraction: Double? = null,
    val resetTime: String? = null
)

data class GeminiUserQuota(
    val buckets: List<GeminiQuotaBucket> = emptyList()
)
