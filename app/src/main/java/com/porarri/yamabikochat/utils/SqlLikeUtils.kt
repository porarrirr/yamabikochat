package com.porarri.yamabikochat.utils

object SqlLikeUtils {
    fun escapeForLike(input: String): String =
        input
            .replace("\\", "\\\\")
            .replace("%", "\\%")
            .replace("_", "\\_")

    fun buildEscapedContainsPattern(rawQuery: String): String {
        val query = rawQuery.trim()
        require(query.isNotEmpty()) { "Query must not be blank." }
        return "%${escapeForLike(query)}%"
    }
}

