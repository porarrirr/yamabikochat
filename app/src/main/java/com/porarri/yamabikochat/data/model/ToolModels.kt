package com.porarri.yamabikochat.data.model

import kotlinx.serialization.Serializable

@Serializable
data class ToolDefinition(
    val name: String,
    val description: String,
    val parametersJSON: String
) {
    val providerTool: ProviderTool
        get() = ProviderTool(
            type = "function",
            payload = mapOf(
                "name" to name,
                "description" to description,
                "parameters" to parametersJSON
            )
        )
}

@Serializable
data class ToolCall(
    val id: String,
    val name: String,
    val argumentsJSON: String,
    val providerMetadata: Map<String, String>? = null
)

@Serializable
data class ToolSource(
    val title: String,
    val url: String
)

@Serializable
data class ToolArtifact(
    val path: String,
    val name: String,
    val mime: String,
    val size: Long
)

@Serializable
data class ToolResult(
    val callId: String,
    val name: String,
    val content: String,
    val isError: Boolean = false,
    val sources: List<ToolSource> = emptyList(),
    val artifacts: List<ToolArtifact> = emptyList()
)
