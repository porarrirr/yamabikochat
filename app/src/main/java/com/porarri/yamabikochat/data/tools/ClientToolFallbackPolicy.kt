package com.porarri.yamabikochat.data.tools

import com.porarri.yamabikochat.data.remote.Tool

object ClientToolFallbackPolicy {
    private val CLIENT_FUNCTION_NAMES = setOf("web_search", "fetch_url")
    private val RETRY_STATUSES = setOf(400, 404, 422)
    private val EXPLICITLY_UNSUPPORTED = listOf(
        "not support",
        "unsupported",
        "does not support",
        "unknown field",
        "unrecognized field",
        "unknown parameter",
        "unrecognized parameter",
        "cannot find field",
        "unknown name"
    )

    fun shouldRetryWithoutClientTools(
        httpStatus: Int,
        body: String,
        tools: List<Tool>,
        round: Int
    ): Boolean {
        return shouldRetryWithoutClientTools(
            httpStatus = httpStatus,
            body = body,
            hasClientFunctionTools = hasClientFunctionTools(tools),
            round = round
        )
    }

    fun shouldRetryWithoutClientTools(
        httpStatus: Int,
        body: String,
        hasClientFunctionTools: Boolean,
        round: Int
    ): Boolean {
        if (round != 1 || !hasClientFunctionTools || httpStatus !in RETRY_STATUSES) {
            return false
        }
        val normalized = body.lowercase()
        val mentionsTools = normalized.contains("tool") || normalized.contains("function")
        val explicitlyUnsupported = EXPLICITLY_UNSUPPORTED.any { normalized.contains(it) }
        return mentionsTools && explicitlyUnsupported
    }

    fun hasClientFunctionTools(tools: List<Tool>): Boolean {
        return tools.any { tool ->
            tool.function_declarations.orEmpty().any { declaration ->
                declaration.name in CLIENT_FUNCTION_NAMES
            }
        }
    }

    /**
     * Strips `web_search` / `fetch_url` function declarations from [tools],
     * and drops Tool shells that become empty afterward.
     */
    fun removingClientTools(tools: List<Tool>): List<Tool> {
        return tools.mapNotNull { tool ->
            val declarations = tool.function_declarations
            if (declarations == null) {
                return@mapNotNull tool
            }
            val filtered = declarations.filterNot { it.name in CLIENT_FUNCTION_NAMES }
            val updated = tool.copy(function_declarations = filtered.takeIf { it.isNotEmpty() })
            if (isEmptyToolShell(updated)) null else updated
        }
    }

    private fun isEmptyToolShell(tool: Tool): Boolean {
        return tool.google_search == null &&
            tool.code_execution == null &&
            tool.url_context == null &&
            tool.google_maps == null &&
            tool.computer_use == null &&
            tool.function_declarations.isNullOrEmpty() &&
            tool.mcp_toolset == null
    }
}
