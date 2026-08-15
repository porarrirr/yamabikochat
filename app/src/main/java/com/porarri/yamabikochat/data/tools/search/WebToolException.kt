package com.porarri.yamabikochat.data.tools.search

import org.json.JSONObject

sealed class WebToolException(message: String) : Exception(message) {
    class InvalidUrl(url: String) : WebToolException("Invalid URL: $url")
    class HttpStatus(val code: Int, message: String = "HTTP $code") : WebToolException(message)
    class ParseFailure(message: String) : WebToolException(message)
    class ExecutionFailed(message: String) : WebToolException(message)
}

object ToolArguments {
    fun objectFrom(raw: String): Map<String, Any?> {
        val json = runCatching { JSONObject(raw) }.getOrElse { throw WebToolException.ParseFailure("Invalid JSON arguments: ${it.message}") }
        val map = mutableMapOf<String, Any?>()
        val keys = json.keys()
        while (keys.hasNext()) {
            val key = keys.next()
            map[key] = if (json.isNull(key)) null else json.get(key)
        }
        return map
    }

    fun int(value: Any?): Int? = when (value) {
        is Number -> value.toInt()
        is String -> value.toIntOrNull()
        else -> null
    }
}
