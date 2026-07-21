package com.porarri.yamabikochat.data.tools

import com.porarri.yamabikochat.utils.DiagnosticsLogger
import kotlinx.coroutines.CancellationException
import org.json.JSONObject

interface LocalToolExecutor {
    val definition: ToolDefinition
    suspend fun execute(call: ToolCall): ToolResult
}

class LocalToolRegistry(
    executors: List<LocalToolExecutor>
) {
    private val executors: Map<String, LocalToolExecutor> =
        executors.associateBy { it.definition.name }

    val definitions: List<ToolDefinition>
        get() = executors.values.map { it.definition }.sortedBy { it.name }

    suspend fun execute(call: ToolCall): ToolResult {
        val executor = executors[call.name]
            ?: return ToolResult(
                callId = call.id,
                name = call.name,
                content = errorContent("Unknown local tool: ${call.name}"),
                isError = true
            )

        return try {
            executor.execute(call)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            if (call.name != "web_search") {
                DiagnosticsLogger.log(
                    "Local tool execution failed tool=${call.name}",
                    e
                )
            }
            ToolResult(
                callId = call.id,
                name = call.name,
                content = errorContent(e.message ?: "Local tool execution failed"),
                isError = true
            )
        }
    }

    companion object {
        fun errorContent(message: String): String {
            return runCatching {
                JSONObject().put("error", message).toString()
            }.getOrDefault("""{"error":"Local tool execution failed"}""")
        }
    }
}
