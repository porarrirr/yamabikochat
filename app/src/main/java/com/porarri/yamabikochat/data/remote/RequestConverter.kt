package com.porarri.yamabikochat.data.remote

/**
 * GeminiリクエストとOpenRouterリクエスト間の変換ロジック
 */
import android.util.Log
import java.util.Locale
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject

object RequestConverter {
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    /**
     * GeminiのGenerateContentRequestをOpenRouterRequestに変換
     */
    fun geminiToOpenRouter(geminiRequest: GenerateContentRequest, model: String): OpenRouterPayload {
        return geminiToOpenRouter(geminiRequest, model, null)
    }

    /**
     * GeminiのGenerateContentRequestをOpenRouterRequestに変換（プロバイダー選択対応）
     */
    fun geminiToOpenRouter(
        geminiRequest: GenerateContentRequest,
        model: String,
        providerPreferences: ProviderPreferences?
    ): OpenRouterPayload {
        Log.d("RequestConverter", "Converting request for model: $model")

        // 先頭の不正な'/'を除去
        val cleanModel = model.removePrefix("/").trim()
        Log.d("RequestConverter", "Cleaned model name: $cleanModel")

        val lowerCaseModel = cleanModel.lowercase(Locale.ROOT)

        // OpenRouter用のモデル名に変換（各プロバイダーのプレフィックスが必要）
        val openRouterModel = when {
            // 既にプロバイダープレフィックスがある場合はそのまま使用
            cleanModel.contains("/") -> cleanModel
            // 各プロバイダーのモデル名を正しい形式に変換
            lowerCaseModel.startsWith("gemini") -> "google/$lowerCaseModel"
            lowerCaseModel.startsWith("gpt") -> "openai/$lowerCaseModel"
            lowerCaseModel.startsWith("claude") -> "anthropic/$lowerCaseModel"
            lowerCaseModel.startsWith("deepseek") -> "deepseek/$lowerCaseModel"
            lowerCaseModel.startsWith("llama") -> "meta-llama/$lowerCaseModel"
            lowerCaseModel.startsWith("mixtral") -> "mistralai/$lowerCaseModel"
            lowerCaseModel.startsWith("qwen") -> "qwen/$lowerCaseModel"
            // その他のモデルはそのまま
            else -> cleanModel
        }
        Log.d("RequestConverter", "OpenRouter model name: $openRouterModel")
        
        // マルチモーダルかどうかを判定
        val hasMultiModal = geminiRequest.contents.any { content ->
            content.parts.any { it.inlineData != null || it.fileData != null }
        }

        // Build OpenRouter reasoning config from Gemini thinkingConfig (if present)
        val reasoningConfig: OpenRouterReasoning? = geminiRequest.generationConfig?.thinkingConfig?.let { tc ->
            val sanitizedEffort = tc.effort?.takeIf { it.isNotBlank() }
            val maxTokens = tc.thinkingBudget?.takeIf { it > 0 }
            val explicitExclude = tc.exclude ?: run {
                if (!tc.includeThoughts) true else null
            }
            val explicitEnabled = tc.enabled

            if (sanitizedEffort == null && maxTokens == null && explicitExclude == null && explicitEnabled == null) {
                null
            } else {
                OpenRouterReasoning(
                    enabled = explicitEnabled,
                    effort = sanitizedEffort,
                    max_tokens = maxTokens,
                    exclude = explicitExclude
                )
            }
        }
        val cacheControl = if (shouldEnableOpenRouterPromptCache(openRouterModel)) {
            PromptCacheControl()
        } else {
            null
        }
        val openAiTools = convertGeminiToolsToOpenAi(geminiRequest.tools)

        return if (hasMultiModal) {
            // マルチモーダルリクエスト
            val messages = geminiRequest.contents.flatMap(::convertToMultiModalMessages)

            val allMessages = buildList {
                geminiRequest.system_instruction?.let { systemInstruction ->
                    add(
                        OpenRouterMultiModalMessage(
                            role = "system",
                            content = convertToMultiModalParts(systemInstruction.parts)
                        )
                    )
                }
                addAll(messages)
            }

            OpenRouterMultiModalRequest(
                model = openRouterModel,
                messages = allMessages,
                temperature = geminiRequest.generationConfig?.temperature,
                top_p = geminiRequest.generationConfig?.topP,
                max_tokens = geminiRequest.generationConfig?.maxOutputTokens,
                stop = geminiRequest.generationConfig?.stopSequences,
                provider = providerPreferences,
                reasoning = reasoningConfig,
                cacheControl = cacheControl,
                tools = openAiTools
            )
        } else {
            // シンプルなテキストリクエスト（tool call / tool result 含む）
            val messages = convertContentsToOpenRouterMessages(geminiRequest.contents)

            val allMessages = buildList {
                geminiRequest.system_instruction?.let { systemInstruction ->
                    add(
                        OpenRouterMessage(
                            role = "system",
                            content = systemInstruction.parts.mapNotNull { it.text }.joinToString("\n")
                        )
                    )
                }
                addAll(messages)
            }

            OpenRouterRequest(
                model = openRouterModel,
                messages = allMessages,
                temperature = geminiRequest.generationConfig?.temperature,
                top_p = geminiRequest.generationConfig?.topP,
                max_tokens = geminiRequest.generationConfig?.maxOutputTokens,
                stop = geminiRequest.generationConfig?.stopSequences,
                provider = providerPreferences,
                reasoning = reasoningConfig,
                cacheControl = cacheControl,
                tools = openAiTools
            )
        }
    }

    private fun convertGeminiToolsToOpenAi(tools: List<Tool>?): List<OpenAITool>? {
        val declarations = tools
            ?.flatMap { it.function_declarations.orEmpty() }
            .orEmpty()
        if (declarations.isEmpty()) return null
        return declarations.map { declaration ->
            OpenAITool(
                function = OpenAIFunctionDef(
                    name = declaration.name,
                    description = declaration.description,
                    parameters = declaration.parameters
                )
            )
        }
    }

    private fun convertContentsToOpenRouterMessages(contents: List<Content>): List<OpenRouterMessage> {
        val messages = mutableListOf<OpenRouterMessage>()
        contents.forEach { content ->
            val textContent = content.parts
                .filter { it.thought != true }
                .mapNotNull { it.text }
                .joinToString("\n")
                .ifBlank { null }
            val reasoningContent = content.parts
                .filter { it.thought == true }
                .mapNotNull { it.text }
                .joinToString("\n")
                .ifBlank { null }
            val toolCalls = content.parts.mapNotNull { it.functionCall }.mapIndexed { index, call ->
                OpenAIToolCall(
                    id = call.id ?: "call-$index-${call.name}",
                    function = OpenAIToolCallFunction(
                        name = call.name,
                        arguments = call.args?.toString() ?: "{}"
                    )
                )
            }
            val functionResponses = content.parts.mapNotNull { it.functionResponse }

            when {
                functionResponses.isNotEmpty() -> {
                    functionResponses.forEach { response ->
                        messages.add(
                            OpenRouterMessage(
                                role = "tool",
                                content = response.response?.toString() ?: "{}",
                                toolCallId = response.id ?: "call-0-${response.name}",
                                name = response.name
                            )
                        )
                    }
                }
                toolCalls.isNotEmpty() -> {
                    messages.add(
                        OpenRouterMessage(
                            role = "assistant",
                            content = textContent,
                            tool_calls = toolCalls,
                            reasoningContent = reasoningContent
                        )
                    )
                }
                else -> {
                    messages.add(
                        OpenRouterMessage(
                            role = when (content.role) {
                                "user" -> "user"
                                "model" -> "assistant"
                                else -> content.role ?: "user"
                            },
                            content = textContent.orEmpty(),
                            reasoningContent = reasoningContent
                        )
                    )
                }
            }
        }
        return messages
    }

    private fun shouldEnableOpenRouterPromptCache(model: String): Boolean {
        val normalized = model.trim().lowercase(Locale.ROOT)
        return normalized.startsWith("anthropic/claude") || normalized.startsWith("claude")
    }

    /**
     * GeminiのパートリストをOpenRouterのマルチモーダルパートに変換
     */
    private fun convertToMultiModalParts(parts: List<Part>): List<OpenRouterContentPart> {
        return parts.mapNotNull { part ->
            when {
                part.text != null -> OpenRouterContentPart.TextPart(text = part.text)
                part.inlineData != null -> convertInlineDataToImagePart(part.inlineData)
                else -> null
            }
        }
    }

    private fun convertToMultiModalMessages(content: Content): List<OpenRouterMultiModalMessage> {
        val functionResponses = content.parts.mapNotNull { it.functionResponse }
        if (functionResponses.isNotEmpty()) {
            return functionResponses.map { response ->
                OpenRouterMultiModalMessage(
                    role = "tool",
                    content = listOf(
                        OpenRouterContentPart.TextPart(
                            response.response?.toString() ?: "{}"
                        )
                    ),
                    toolCallId = response.id ?: "call-0-${response.name}",
                    name = response.name
                )
            }
        }

        val role = when (content.role) {
            "model" -> "assistant"
            "user" -> "user"
            else -> content.role ?: "user"
        }
        val toolCalls = content.parts.mapNotNull { it.functionCall }.mapIndexed { index, call ->
            OpenAIToolCall(
                id = call.id ?: "call-$index-${call.name}",
                function = OpenAIToolCallFunction(
                    name = call.name,
                    arguments = call.args?.toString() ?: "{}"
                )
            )
        }.takeIf { it.isNotEmpty() }
        val visibleParts = content.parts.filter { it.thought != true }
        val reasoningContent = content.parts
            .filter { it.thought == true }
            .mapNotNull { it.text }
            .joinToString("\n")
            .ifBlank { null }
        return listOf(
            OpenRouterMultiModalMessage(
                role = role,
                content = convertToMultiModalParts(visibleParts).takeIf { it.isNotEmpty() },
                tool_calls = toolCalls,
                reasoningContent = reasoningContent
            )
        )
    }

    /**
     * GeminiのInlineDataをOpenRouterのImagePartに変換
     */
    private fun convertInlineDataToImagePart(inlineData: InlineData): OpenRouterContentPart.ImagePart {
        // Base64データをdata URLに変換
        val dataUrl = "data:${inlineData.mimeType};base64,${inlineData.data}"
        
        return OpenRouterContentPart.ImagePart(
            imageUrl = OpenRouterImageUrl(url = dataUrl)
        )
    }

    /**
     * OpenRouterのレスポンスをGeminiのレスポンス形式に変換
     */
    fun openRouterToGemini(openRouterResponse: OpenRouterResponse): GenerateContentResponse {
        val candidates = openRouterResponse.choices.map { choice ->
            val parts = mutableListOf<ResponsePart>()
            // Add reasoning as a thought part if present
            val reasoningText = choice.message.reasoningDetails
                ?.joinToString(separator = "") { it.text.orEmpty() }
                ?.trim()
                ?.takeIf { it.isNotBlank() }
                ?: choice.message.reasoning
                    ?.takeIf { it.isNotBlank() }
                ?: choice.message.reasoningContent?.takeIf { it.isNotBlank() }
            reasoningText?.let {
                parts.add(ResponsePart(text = it, thought = true))
            }
            choice.message.content?.takeIf { it.isNotEmpty() }?.let { text ->
                parts.add(ResponsePart(text = text))
            }
            choice.message.tool_calls.orEmpty().forEach { toolCall ->
                val args = runCatching {
                    json.parseToJsonElement(toolCall.function.arguments)
                }.getOrNull()
                parts.add(
                    ResponsePart(
                        functionCall = FunctionCall(
                            name = toolCall.function.name,
                            args = args,
                            id = toolCall.id
                        )
                    )
                )
            }
            if (parts.isEmpty()) {
                parts.add(ResponsePart(text = ""))
            }

            Candidate(
                content = ResponseContent(
                    parts = parts,
                    role = "model"
                ),
                finishReason = choice.finish_reason,
                index = choice.index
            )
        }

        return GenerateContentResponse(
            candidates = candidates,
            text = openRouterResponse.choices.firstOrNull()?.message?.content,
            tokenUsage = openRouterResponse.usage?.toTokenUsageSnapshot()
        )
    }

    /**
     * OpenRouterのストリームレスポンスをGeminiのレスポンス形式に変換
     */
    fun openRouterStreamToGemini(streamChoice: OpenRouterStreamChoice): GenerateContentResponse {
        val candidate = Candidate(
            content = ResponseContent(
                parts = listOf(ResponsePart(text = streamChoice.delta.content ?: "")),
                role = "model"
            ),
            finishReason = streamChoice.finish_reason,
            index = streamChoice.index
        )

        return GenerateContentResponse(
            candidates = listOf(candidate),
            text = streamChoice.delta.content
        )
    }
    
    /**
     * OpenRouterのストリームレスポンス全体をGeminiのレスポンス形式に変換
     */
    fun openRouterStreamResponseToGemini(streamResponse: OpenRouterStreamResponse): GenerateContentResponse {
        val candidates = streamResponse.choices.map { choice ->
            Candidate(
                content = ResponseContent(
                    parts = listOf(ResponsePart(text = choice.delta.content ?: "")),
                    role = "model"
                ),
                finishReason = choice.finish_reason,
                index = choice.index
            )
        }

        return GenerateContentResponse(
            candidates = candidates,
            text = streamResponse.choices.firstOrNull()?.delta?.content
        )
    }

    /**
     * GeminiリクエストをOpenAI Responses APIリクエストに変換
     */
    fun geminiToResponses(
        geminiRequest: GenerateContentRequest,
        model: String,
        stream: Boolean,
        promptCacheKey: String? = null
    ): ResponsesRequest {
        val cleanModel = model.removePrefix("/").removePrefix("openai/").trim()
        val instructions = geminiRequest.system_instruction
            ?.parts
            ?.mapNotNull { it.text }
            ?.joinToString("\n")
            ?.takeIf { it.isNotBlank() }

        val inputItems = geminiRequest.contents.map { content ->
            val role = when (content.role) {
                "model" -> "assistant"
                "user" -> "user"
                else -> content.role ?: "user"
            }
            val isAssistant = role == "assistant"
            val parts = content.parts.mapNotNull { part ->
                when {
                    part.text != null -> {
                        val text = part.text
                        if (isAssistant) ResponseOutputText(text = text ?: "") else ResponseInputText(text = text ?: "")
                    }
                    part.inlineData != null && !isAssistant -> {
                        val dataUrl = "data:${part.inlineData.mimeType};base64,${part.inlineData.data}"
                        ResponseInputImage(imageUrl = dataUrl)
                    }
                    else -> null
                }
            }
            ResponseInputItem(role = role, content = parts)
        }

        val thinkingEffort = geminiRequest.generationConfig?.thinkingConfig
            ?.effort
            ?.takeIf { it.isNotBlank() }

        val codexConfig = geminiRequest.codexConfig
        val promptCacheKeyToSend = if (codexConfig?.promptCacheEnabled == false) {
            null
        } else {
            (geminiRequest.promptCacheKey ?: promptCacheKey)
                ?.trim()
                ?.takeIf { it.isNotBlank() }
        }
        val summary = codexConfig?.reasoningSummary?.takeIf { it.isNotBlank() }
        val reasoning = if (thinkingEffort != null || summary != null) {
            ResponsesReasoning(effort = thinkingEffort, summary = summary)
        } else {
            null
        }
        val include = if (reasoning != null) listOf("reasoning.encrypted_content") else emptyList()
        val textConfig = codexConfig?.verbosity?.takeIf { it.isNotBlank() }?.let {
            ResponsesTextConfig(verbosity = it)
        }
        val tools = buildList {
            if (codexConfig?.webSearchEnabled == true) {
                add(
                    buildJsonObject {
                        put("type", JsonPrimitive("web_search"))
                        codexConfig.webSearchContextSize?.takeIf { it.isNotBlank() }?.let { size ->
                            put("search_context_size", JsonPrimitive(size))
                        }
                    }
                )
            }
        }

        return ResponsesRequest(
            model = cleanModel,
            input = inputItems,
            instructions = instructions.orEmpty(),
            stream = stream,
            store = false,
            include = include,
            tools = tools,
            text = textConfig,
            promptCacheKey = promptCacheKeyToSend,
            reasoning = reasoning
        )
    }
}
