package com.porarri.yamabikochat.data.auth

data class CodexAuthState(
    val isLoggedIn: Boolean = false,
    val email: String? = null,
    val planType: String? = null,
    val accountId: String? = null,
    val hasApiKey: Boolean = false,
    val lastRefreshISO8601: String? = null,
    val planUsageEnabled: Boolean = false,
    val requiresReauthentication: Boolean = false,
    val revocationUnconfirmed: Boolean = false,
    val savedAccounts: List<CodexSavedAccount> = emptyList()
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

data class CodexSavedAccount(val clientID: String, val email: String?) {
    val label: String get() = "${email ?: "ChatGPT"} · ${clientID.takeLast(8)}"
}
