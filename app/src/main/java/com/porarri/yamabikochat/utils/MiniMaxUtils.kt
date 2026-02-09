package com.porarri.yamabikochat.utils

import java.net.URI

object MiniMaxUtils {
    const val INTERNATIONAL_BASE_URL = "https://api.minimax.io/v1/"
    const val CHINA_BASE_URL = "https://api.minimaxi.com/v1/"

    fun isMiniMaxBaseUrl(baseUrl: String): Boolean {
        val trimmed = baseUrl.trim()
        if (trimmed.isBlank()) return false

        val host = runCatching { URI(trimmed).host }.getOrNull()?.lowercase()
        return when {
            host != null -> host.endsWith("minimax.io") || host.endsWith("minimaxi.com")
            else -> trimmed.contains("minimax.io", ignoreCase = true) ||
                trimmed.contains("minimaxi.com", ignoreCase = true)
        }
    }
}
