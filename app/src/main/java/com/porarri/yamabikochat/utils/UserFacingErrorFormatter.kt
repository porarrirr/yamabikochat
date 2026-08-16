package com.porarri.yamabikochat.utils

data class UserFacingError(
    val title: String,
    val summary: String,
    val detail: String
) {
    val hasDetail: Boolean
        get() {
            val trimmed = detail.trim()
            return trimmed.isNotEmpty() && trimmed != summary && trimmed != title
        }
}

data class UserFacingErrorCopy(
    val genericTitle: String = "エラー",
    val quotaTitle: String = "利用上限に達しました",
    val quotaSummary: String = "プランまたは課金設定を確認してください。",
    val authTitle: String = "認証に失敗しました",
    val authSummary: String = "ログインまたはAPIキーを確認してください。",
    val serverTitle: String = "サーバーエラー",
    val serverSummary: String = "しばらくしてから再試行してください。",
    val fallbackSummary: String = "応答を取得できませんでした",
    val details: String = "詳細",
    val dismiss: String = "閉じる",
    val errorPrefix: String = "エラー"
) {
    companion object {
        val Default = UserFacingErrorCopy()
    }
}

object UserFacingErrorFormatter {
    private val wrapperPrefixes = listOf(
        "Response parse failed:",
        "Pi provider failed:",
        "Pi agent failed:"
    )
    private val chatErrorPrefixes = listOf(
        "错误：",
        "错误:",
        "エラー:",
        "erreur :",
        "erreur:",
        "error:"
    )
    private val quotaSummaries = setOf(
        "プランまたは課金設定を確認してください。",
        "Check your plan or billing settings.",
        "Revisa tu plan o la configuración de facturación.",
        "Vérifiez votre forfait ou les paramètres de facturation.",
        "请检查套餐或账单设置。"
    )
    private val authSummaries = setOf(
        "ログインまたはAPIキーを確認してください。",
        "Check your sign-in or API key.",
        "Revisa el inicio de sesión o la clave API.",
        "Vérifiez la connexion ou la clé API.",
        "请检查登录或 API 密钥。"
    )
    private val serverSummaries = setOf(
        "しばらくしてから再試行してください。",
        "Please try again in a moment.",
        "Inténtalo de nuevo en un momento.",
        "Veuillez réessayer dans un instant.",
        "请稍后再试。"
    )
    private val fallbackSummaries = setOf(
        "応答を取得できませんでした",
        "Couldn't get a response",
        "No se pudo obtener una respuesta",
        "Impossible d’obtenir une réponse",
        "无法获取回复"
    )
    private const val HUMAN_READABLE_LIMIT = 220
    private val messageRegex = Regex("\"message\"\\s*:\\s*\"((?:\\\\.|[^\"\\\\])*)\"", RegexOption.DOT_MATCHES_ALL)
    private val codeRegex = Regex("\"code\"\\s*:\\s*\"?([0-9A-Za-z_.]+)\"?")
    private val statusRegex = Regex("\"status\"\\s*:\\s*\"([^\"]+)\"")
    private val httpStatusRegex = Regex("HTTP\\s+(\\d{3})", RegexOption.IGNORE_CASE)
    private val leadingHttpStatusRegex = Regex("^HTTP\\s+\\d{3}\\b", RegexOption.IGNORE_CASE)

    fun format(error: Throwable, copy: UserFacingErrorCopy = UserFacingErrorCopy.Default): UserFacingError =
        format(error.message, copy)

    fun format(raw: String?, copy: UserFacingErrorCopy = UserFacingErrorCopy.Default): UserFacingError {
        val original = raw?.trim().orEmpty()
        if (original.isEmpty()) {
            return fallback(copy, detail = "")
        }

        val stripped = stripWrappers(stripChatErrorPrefix(original))
        val fields = extractFields(original, stripped)
        mapKnown(fields, copy)?.let { mapped ->
            return UserFacingError(mapped.first, mapped.second, original)
        }

        mapKnownSummary(stripped, copy)?.let { mapped ->
            return UserFacingError(mapped.first, mapped.second, extraDetail(original, mapped.second, copy))
        }

        fields.message?.trim()?.takeIf { isAlreadyHumanReadable(it) }?.let { message ->
            return UserFacingError(copy.genericTitle, message, extraDetail(original, message, copy))
        }

        if (isAlreadyHumanReadable(stripped)) {
            return UserFacingError(
                title = copy.genericTitle,
                summary = stripped,
                detail = extraDetail(original, stripped, copy)
            )
        }

        return fallback(copy, original)
    }

    fun placeholder(error: Throwable, copy: UserFacingErrorCopy = UserFacingErrorCopy.Default): String =
        placeholder(error.message, copy)

    fun placeholder(raw: String?, copy: UserFacingErrorCopy = UserFacingErrorCopy.Default): String {
        val formatted = format(raw, copy)
        if (looksLikeChatError(formatted.summary)) {
            return formatted.summary
        }
        return "${copy.errorPrefix}: ${formatted.summary}"
    }

    fun looksLikeChatError(text: String): Boolean {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return false
        if (hasChatErrorPrefix(trimmed)) return true
        if (hasWrapperPrefix(trimmed)) return true
        if (trimmed.startsWith("{") && extractErrorPayload(trimmed) != null) return true
        if (startsWithHttpStatus(trimmed)) return true
        return false
    }

    private fun fallback(copy: UserFacingErrorCopy, detail: String): UserFacingError =
        UserFacingError(copy.genericTitle, copy.fallbackSummary, detail)

    private fun mapKnown(
        fields: ExtractedFields,
        copy: UserFacingErrorCopy
    ): Pair<String, String>? {
        val code = fields.code?.uppercase().orEmpty()
        val status = fields.status?.uppercase().orEmpty()
        val message = fields.message?.lowercase().orEmpty()
        val http = fields.httpStatus ?: code.toIntOrNull()

        if (http == 429 ||
            code == "429" ||
            status == "RESOURCE_EXHAUSTED" ||
            "quota" in message ||
            "resource has been exhausted" in message ||
            "resource_exhausted" in message
        ) {
            return copy.quotaTitle to copy.quotaSummary
        }

        if (http == 401 ||
            http == 403 ||
            code == "401" ||
            code == "403" ||
            status == "UNAUTHENTICATED" ||
            status == "PERMISSION_DENIED" ||
            status == "UNAUTHORIZED" ||
            "unauthenticated" in message ||
            "unauthorized" in message ||
            "api key" in message ||
            "permission denied" in message
        ) {
            return copy.authTitle to copy.authSummary
        }

        if (http == 500 ||
            http == 502 ||
            http == 503 ||
            http == 529 ||
            status == "INTERNAL" ||
            status == "UNAVAILABLE" ||
            status == "DEADLINE_EXCEEDED" ||
            "internal server" in message
        ) {
            return copy.serverTitle to copy.serverSummary
        }

        return null
    }

    private fun mapKnownSummary(stripped: String, copy: UserFacingErrorCopy): Pair<String, String>? {
        val text = stripped.trim()
        if (text.isEmpty()) return null
        if (text == copy.quotaSummary || text in quotaSummaries) {
            return copy.quotaTitle to copy.quotaSummary
        }
        if (text == copy.authSummary || text in authSummaries) {
            return copy.authTitle to copy.authSummary
        }
        if (text == copy.serverSummary || text in serverSummaries) {
            return copy.serverTitle to copy.serverSummary
        }
        if (text == copy.fallbackSummary || text in fallbackSummaries) {
            return copy.genericTitle to copy.fallbackSummary
        }
        return null
    }

    private fun extraDetail(original: String, summary: String, copy: UserFacingErrorCopy): String {
        if (original == summary) return ""
        val strippedPrefix = stripChatErrorPrefix(original)
        if (strippedPrefix == summary) return ""
        val fullyStripped = stripWrappers(strippedPrefix)
        if (fullyStripped == summary) return ""
        if (mapKnownSummary(strippedPrefix, copy) != null || mapKnownSummary(fullyStripped, copy) != null) {
            return ""
        }
        return original
    }

    private fun extractFields(original: String, stripped: String): ExtractedFields {
        var fields = ExtractedFields(httpStatus = httpStatus(original) ?: httpStatus(stripped))
        val candidates = linkedSetOf(original, stripped, unescapeJson(stripped), unescapeJson(unescapeJson(stripped)))
            .map { it.trim() }
            .filter { it.isNotEmpty() }

        for (candidate in candidates) {
            val payload = extractErrorPayload(candidate) ?: continue
            fields = fields.copy(
                message = fields.message ?: payload.message,
                code = fields.code ?: payload.code,
                status = fields.status ?: payload.status
            )
            if (fields.message != null || fields.code != null || fields.status != null) {
                break
            }
        }

        val nestedMessage = fields.message
        if (nestedMessage != null && nestedMessage.contains("{")) {
            val nested = extractErrorPayload(unescapeJson(nestedMessage))
            fields = fields.copy(
                message = nested?.message ?: fields.message,
                code = fields.code ?: nested?.code,
                status = fields.status ?: nested?.status
            )
        }
        return fields
    }

    private fun extractErrorPayload(text: String): ExtractedFields? {
        val jsonSlice = firstJsonObject(text) ?: text
        val message = messageRegex.find(jsonSlice)?.groupValues?.getOrNull(1)?.let(::unescapeJsonStringValue)
        val code = codeRegex.find(jsonSlice)?.groupValues?.getOrNull(1)
        val status = statusRegex.find(jsonSlice)?.groupValues?.getOrNull(1)
        if (message == null && code == null && status == null) return null
        return ExtractedFields(message = message, code = code, status = status)
    }

    private fun firstJsonObject(text: String): String? {
        val start = text.indexOf('{')
        if (start < 0) return null
        var depth = 0
        var inString = false
        var escaped = false
        for (index in start until text.length) {
            val character = text[index]
            if (inString) {
                when {
                    escaped -> escaped = false
                    character == '\\' -> escaped = true
                    character == '"' -> inString = false
                }
            } else when (character) {
                '"' -> inString = true
                '{' -> depth++
                '}' -> {
                    depth--
                    if (depth == 0) {
                        return text.substring(start, index + 1)
                    }
                }
            }
        }
        return null
    }

    private fun stripChatErrorPrefix(text: String): String {
        val trimmed = text.trim()
        val prefix = matchingChatErrorPrefix(trimmed) ?: return trimmed
        return trimmed.substring(prefix.length).trim()
    }

    private fun stripWrappers(text: String): String {
        var current = text.trim()
        var changed = true
        while (changed) {
            changed = false
            for (prefix in wrapperPrefixes) {
                if (current.startsWith(prefix, ignoreCase = true)) {
                    current = current.substring(prefix.length).trim()
                    changed = true
                }
            }
            httpStatus(current)?.let { status ->
                val stripped = current.replaceFirst(Regex("^HTTP\\s+$status\\s*:\\s*", RegexOption.IGNORE_CASE), "")
                if (stripped != current) {
                    current = stripped.trim()
                    changed = true
                }
            }
        }
        return current
    }

    private fun hasChatErrorPrefix(text: String): Boolean =
        matchingChatErrorPrefix(text) != null

    private fun matchingChatErrorPrefix(text: String): String? =
        chatErrorPrefixes.firstOrNull { text.startsWith(it, ignoreCase = true) }

    private fun startsWithHttpStatus(text: String): Boolean =
        leadingHttpStatusRegex.containsMatchIn(text)

    private fun hasWrapperPrefix(text: String): Boolean {
        val lowered = text.lowercase()
        return wrapperPrefixes.any { lowered.startsWith(it.lowercase()) }
    }

    private fun isAlreadyHumanReadable(text: String): Boolean {
        val trimmed = text.trim()
        if (trimmed.isEmpty() || trimmed.length > HUMAN_READABLE_LIMIT) return false
        if (hasWrapperPrefix(trimmed)) return false
        if ('{' in trimmed && '}' in trimmed) return false
        return true
    }

    private fun httpStatus(text: String): Int? =
        httpStatusRegex.find(text)?.groupValues?.getOrNull(1)?.toIntOrNull()

    private fun unescapeJson(text: String): String {
        var current = text.trim()
        if (current.length >= 2 && current.startsWith("\"") && current.endsWith("\"")) {
            current = current.substring(1, current.length - 1)
        }
        return unescapeJsonStringValue(current)
    }

    private fun unescapeJsonStringValue(text: String): String {
        val result = StringBuilder(text.length)
        var index = 0
        while (index < text.length) {
            val character = text[index]
            if (character != '\\' || index == text.lastIndex) {
                result.append(character)
                index++
                continue
            }
            when (val next = text[index + 1]) {
                'n' -> {
                    result.append('\n')
                    index += 2
                }
                'r' -> {
                    result.append('\r')
                    index += 2
                }
                't' -> {
                    result.append('\t')
                    index += 2
                }
                '"' -> {
                    result.append('"')
                    index += 2
                }
                '\\' -> {
                    result.append('\\')
                    index += 2
                }
                '/' -> {
                    result.append('/')
                    index += 2
                }
                'u' -> {
                    val hex = text.substring(index + 2, (index + 6).coerceAtMost(text.length))
                    val value = hex.toIntOrNull(16)
                    if (hex.length == 4 && value != null) {
                        result.append(value.toChar())
                        index += 6
                    } else {
                        result.append('\\').append('u').append(hex)
                        index += 2 + hex.length
                    }
                }
                else -> {
                    result.append(next)
                    index += 2
                }
            }
        }
        return result.toString()
    }

    private data class ExtractedFields(
        val message: String? = null,
        val code: String? = null,
        val status: String? = null,
        val httpStatus: Int? = null
    )
}
