package com.porarri.yamabikochat.data.remote

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.Transient
import kotlinx.serialization.json.JsonElement
import com.porarri.yamabikochat.data.skills.SkillRequestContext

@Serializable
data class GenerateContentRequest(
    val contents: List<Content>,
    val system_instruction: SystemInstruction? = null,
    val generationConfig: GenerationConfig? = null,
    val tools: List<Tool>? = null,
    @SerialName("toolConfig")
    val toolConfig: ToolConfig? = null,
    @Transient
    val codexConfig: CodexRequestConfig? = null,
    @Transient
    val promptCacheKey: String? = null,
    @Transient
    val skillContext: SkillRequestContext? = null
)

@Serializable
data class Content(
    val role: String? = null,
    val parts: List<Part>
)

@Serializable
data class Part(
    val text: String? = null,
    val inlineData: InlineData? = null,
    val fileData: FileData? = null,
    val functionCall: FunctionCall? = null,
    val functionResponse: FunctionResponse? = null
)

@Serializable
data class InlineData(
    val mimeType: String,
    val data: String
)

@Serializable
data class SystemInstruction(
    val parts: List<Part>
)

@Serializable
data class GenerationConfig(
    val temperature: Float? = null,
    val topK: Int? = null,
    val topP: Float? = null,
    val maxOutputTokens: Int? = null,
    val stopSequences: List<String>? = null,
    val thinkingConfig: ThinkingConfig? = null,
    @SerialName("responseMimeType")
    val responseMimeType: String? = null,
    @SerialName("responseJsonSchema")
    val responseJsonSchema: JsonElement? = null
)

@Serializable
data class ThinkingConfig(
    val thinkingBudget: Int? = null,
    val thinkingLevel: String? = null,
    val includeThoughts: Boolean = true,
    val effort: String? = null,
    val enabled: Boolean? = null,
    val exclude: Boolean? = null
)

data class CodexRequestConfig(
    val reasoningSummary: String? = null,
    val verbosity: String? = null,
    val webSearchEnabled: Boolean = false,
    val webSearchContextSize: String? = null,
    val promptCacheEnabled: Boolean = false,
    val promptCacheMinLength: Int? = null,
    val promptCacheType: String? = null
)

@Serializable
data class Tool(
    val google_search: GoogleSearch? = null,
    val code_execution: CodeExecution? = null,
    val url_context: UrlContext? = null,
    val google_maps: GoogleMaps? = null,
    val computer_use: ComputerUse? = null,
    val function_declarations: List<FunctionDeclaration>? = null,
    val mcp_toolset: McpToolset? = null
)

@Serializable
class GoogleSearch

@Serializable
class CodeExecution

@Serializable
class UrlContext

@Serializable
class GoogleMaps

@Serializable
class ComputerUse

@Serializable
data class ToolConfig(
    @SerialName("functionCallingConfig")
    val functionCallingConfig: FunctionCallingConfig? = null
)

@Serializable
data class FunctionCallingConfig(
    val mode: String? = null,
    @SerialName("allowedFunctionNames")
    val allowedFunctionNames: List<String>? = null
)

@Serializable
data class FunctionDeclaration(
    val name: String,
    val description: String? = null,
    val parameters: JsonElement? = null
)

@Serializable
data class McpToolset(
    val serverUrl: String,
    val serverName: String,
    val allowedTools: List<String> = emptyList()
)

@Serializable
data class FunctionCall(
    val name: String,
    val args: JsonElement? = null
)

@Serializable
data class FunctionResponse(
    val name: String,
    val response: JsonElement? = null,
    val parts: List<FunctionResponsePart>? = null,
    /** Optional OpenAI tool_call_id for OpenRouter/OpenAI conversion. */
    val id: String? = null
)

@Serializable
data class FunctionResponsePart(
    val inlineData: InlineData? = null,
    val fileData: FunctionResponseFileData? = null
)

@Serializable
data class FunctionResponseFileData(
    val mimeType: String? = null,
    val displayName: String? = null,
    val fileUri: String? = null
)

@Serializable
data class FileData(
    val mimeType: String? = null,
    val displayName: String? = null,
    val fileUri: String? = null
)
