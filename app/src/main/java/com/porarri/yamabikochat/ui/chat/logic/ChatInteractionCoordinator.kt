package com.porarri.yamabikochat.ui.chat.logic

import android.net.Uri
import android.util.Log
import com.porarri.yamabikochat.data.ChatRepository
import com.porarri.yamabikochat.data.local.ChatMessage
import com.porarri.yamabikochat.data.local.ChatMessageSummary
import com.porarri.yamabikochat.data.local.ChatMessageToolActivity
import com.porarri.yamabikochat.data.local.ChatMessageVariant
import com.porarri.yamabikochat.data.local.Conversation
import com.porarri.yamabikochat.data.local.DualChatMessage
import com.porarri.yamabikochat.data.local.FullChatMessage
import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.data.remote.GenerateContentRequest
import com.porarri.yamabikochat.data.remote.Content
import com.porarri.yamabikochat.data.remote.GenerationConfig
import com.porarri.yamabikochat.data.remote.Part
import com.porarri.yamabikochat.data.remote.SystemInstruction
import com.porarri.yamabikochat.data.tools.ClientToolCallingRunner
import com.porarri.yamabikochat.data.tools.ClientTools
import com.porarri.yamabikochat.data.tools.ToolActivityStep
import com.porarri.yamabikochat.ui.chat.ConversationHistoryBuilder
import com.porarri.yamabikochat.utils.MiniMaxUtils
import com.porarri.yamabikochat.utils.ToolingUtils
import com.porarri.yamabikochat.data.skills.AgentSkillTools
import com.porarri.yamabikochat.data.skills.SkillRequestContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json

class ChatInteractionCoordinator(
    private val repository: ChatRepository,
    private val historyBuilder: ConversationHistoryBuilder,
    private val responseStreamer: ChatResponseStreamer,
    private val dualChatResponder: DualChatResponder,
    private val toolCallingRunner: ClientToolCallingRunner = ClientToolCallingRunner(
        generate = { request, model, provider ->
            repository.generateContent(
                model = model,
                request = request,
                providerOverride = provider
            )
        },
        registry = ClientTools.defaultRegistry(repository.agentSkillRepository)
    )
) {
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    data class SingleMessageContext(
        val conversation: Conversation,
        val settings: Settings,
        val text: String,
        val attachments: List<Uri>,
        val messageSummaries: List<ChatMessageSummary>,
        val fullMessagesState: MutableStateFlow<Map<Long, FullChatMessage>>,
        val fetchFullMessage: (Long) -> Unit,
        val scope: CoroutineScope,
        val skipModelResponse: Boolean = false
    )

    data class RegenerateMessageContext(
        val conversation: Conversation,
        val settings: Settings,
        val userMessage: ChatMessage,
        val messageSummariesBefore: List<ChatMessageSummary>,
        val fullMessagesState: MutableStateFlow<Map<Long, FullChatMessage>>,
        val fetchFullMessage: (Long) -> Unit,
        val scope: CoroutineScope,
        val targetMessageId: Long
    )

    data class SingleMessageResult(
        val newlyFetchedMessages: Map<Long, FullChatMessage>
    )

    suspend fun sendSingleMessage(context: SingleMessageContext): SingleMessageResult {
        val (conversation, settings, text, attachments, messageSummaries, fullMessagesState, fetchFullMessage, scope, skipModelResponse) = context

        val attachmentPaths = withContext(Dispatchers.IO) {
            attachments.mapNotNull { repository.saveAttachment(it) }
        }

        val userMessage = ChatMessage(
            conversationId = conversation.id,
            role = "user",
            text = text,
            attachments = attachmentPaths
        )
        withContext(Dispatchers.IO) { repository.insertMessage(userMessage) }

        if (messageSummaries.isEmpty() && conversation.title == "New Chat") {
            withContext(Dispatchers.IO) {
                val newTitle = text.take(50)
                repository.upsertConversation(conversation.copy(title = newTitle))
            }
        }

        val activeProvider = (conversation.apiProvider.ifBlank { settings.apiProvider }).uppercase()
        val activeModel = conversation.model.ifBlank { settings.getCurrentModel() }
        val baseUrlForHistory = when (activeProvider) {
            "OPENAI" -> settings.openAiBaseUrl.ifBlank { "https://api.openai.com/v1/" }
            "MINIMAX" -> settings.miniMaxBaseUrl.ifBlank { MiniMaxUtils.INTERNATIONAL_BASE_URL }
            "OPENAI_COMPAT" -> settings.resolveSelectedCompatBaseUrl() ?: "https://api.openai.com/v1/"
            "CODEX_AUTH" -> settings.openAiBaseUrl.ifBlank { "https://api.openai.com/v1/" }
            else -> null
        }
        val includeModelThoughts = baseUrlForHistory?.let(MiniMaxUtils::isMiniMaxBaseUrl) == true

        val historyPreparation = historyBuilder.buildStandardHistory(
            text = text,
            attachmentsToSend = attachments,
            messageSummaries = messageSummaries,
            existingFullMessages = fullMessagesState.value,
            includeModelThoughts = includeModelThoughts
        )

        if (historyPreparation.newlyFetchedMessages.isNotEmpty()) {
            fullMessagesState.update { it + historyPreparation.newlyFetchedMessages }
        }

        val skillContext = repository.agentSkillRepository.requestContext(text, "conversation-${conversation.id}")
        val skillDeclarations = if (ClientTools.supportsClientWebSearchTool(activeProvider)) {
            AgentSkillTools.declarations(repository.agentSkillRepository)
        } else {
            emptyList()
        }
        val tools = appendSkillDeclarations(ToolingUtils.buildTools(settings, activeProvider), skillDeclarations)
        val thinkingConfig = settings.buildThinkingConfigFor(activeProvider, activeModel)
        val generationConfig = buildGenerationConfig(settings, activeProvider, activeModel, thinkingConfig)
        val systemInstructionSource = conversation.systemPrompt ?: settings.systemPrompt
        val systemInstruction = systemInstructionSource?.let { SystemInstruction(parts = listOf(Part(it))) }
        val codexConfig = if (activeProvider == "CODEX_AUTH") {
            settings.buildCodexRequestConfig(activeModel)
        } else {
            null
        }

        val request = GenerateContentRequest(
            contents = applySkillContext(historyPreparation.history, skillContext),
            tools = tools.takeIf { it.isNotEmpty() },
            generationConfig = generationConfig,
            system_instruction = systemInstruction,
            codexConfig = codexConfig,
            promptCacheKey = "conversation-${conversation.id}",
            skillContext = skillContext
        )

        if (skipModelResponse) {
            return SingleMessageResult(historyPreparation.newlyFetchedMessages)
        }

        val useClientTools = ClientTools.supportsClientWebSearchTool(activeProvider) &&
            (settings.clientWebSearchToolEnabled || skillDeclarations.isNotEmpty())

        if (useClientTools) {
            scope.launch(Dispatchers.IO) {
                runClientToolCallingTurn(
                    conversationId = conversation.id,
                    model = activeModel,
                    provider = activeProvider,
                    request = request,
                    fullMessagesState = fullMessagesState,
                    fetchFullMessage = fetchFullMessage,
                    existingMessageId = null
                )
            }
            return SingleMessageResult(historyPreparation.newlyFetchedMessages)
        }

        if (settings.isStreamingEnabledFor(activeProvider)) {
            responseStreamer.launchStreamingResponse(
                scope = scope,
                conversationId = conversation.id,
                model = activeModel,
                provider = activeProvider,
                request = request,
                fullMessages = fullMessagesState,
                fetchFullMessage = fetchFullMessage
            )
        } else {
            when (val result = responseStreamer.requestSingleResponse(conversation.id, activeModel, activeProvider, request)) {
                is ChatResponseStreamer.NonStreamingResult.Success -> {
                    val modelMessage = ChatMessage(
                        conversationId = conversation.id,
                        role = "model",
                        text = result.text,
                        attachments = result.attachments,
                        thinkingSummary = result.thinking.ifBlank { null }
                    )
                    val modelMessageId = repository.insertMessage(modelMessage)
                    if (result.thinking.isNotBlank()) {
                        repository.insertThinking(modelMessageId, result.thinking)
                    }
                    fetchFullMessage(modelMessageId)
                }
                is ChatResponseStreamer.NonStreamingResult.Failure -> {
                    val modelMessage = ChatMessage(
                        conversationId = conversation.id,
                        role = "model",
                        text = result.message
                    )
                    repository.insertMessage(modelMessage)
                }
            }
        }

        return SingleMessageResult(historyPreparation.newlyFetchedMessages)
    }

    suspend fun regenerateMessage(context: RegenerateMessageContext) {
        val (
            conversation,
            settings,
            userMessage,
            messageSummariesBefore,
            fullMessagesState,
            fetchFullMessage,
            scope,
            targetMessageId
        ) = context

        val activeProvider = (conversation.apiProvider.ifBlank { settings.apiProvider }).uppercase()
        val activeModel = conversation.model.ifBlank { settings.getCurrentModel() }
        val baseUrlForHistory = when (activeProvider) {
            "OPENAI" -> settings.openAiBaseUrl.ifBlank { "https://api.openai.com/v1/" }
            "MINIMAX" -> settings.miniMaxBaseUrl.ifBlank { MiniMaxUtils.INTERNATIONAL_BASE_URL }
            "OPENAI_COMPAT" -> settings.resolveSelectedCompatBaseUrl() ?: "https://api.openai.com/v1/"
            "CODEX_AUTH" -> settings.openAiBaseUrl.ifBlank { "https://api.openai.com/v1/" }
            else -> null
        }
        val includeModelThoughts = baseUrlForHistory?.let(MiniMaxUtils::isMiniMaxBaseUrl) == true

        val historyPreparation = historyBuilder.buildStandardHistory(
            text = userMessage.text,
            attachmentsToSend = userMessage.attachments.map { Uri.parse(it) },
            messageSummaries = messageSummariesBefore,
            existingFullMessages = fullMessagesState.value,
            includeModelThoughts = includeModelThoughts
        )

        if (historyPreparation.newlyFetchedMessages.isNotEmpty()) {
            fullMessagesState.update { it + historyPreparation.newlyFetchedMessages }
        }

        val skillContext = repository.agentSkillRepository.requestContext(userMessage.text, "conversation-${conversation.id}")
        val skillDeclarations = if (ClientTools.supportsClientWebSearchTool(activeProvider)) AgentSkillTools.declarations(repository.agentSkillRepository) else emptyList()
        val tools = appendSkillDeclarations(ToolingUtils.buildTools(settings, activeProvider), skillDeclarations)
        val thinkingConfig = settings.buildThinkingConfigFor(activeProvider, activeModel)
        val generationConfig = buildGenerationConfig(settings, activeProvider, activeModel, thinkingConfig)
        val systemInstructionSource = conversation.systemPrompt ?: settings.systemPrompt
        val systemInstruction = systemInstructionSource?.let { SystemInstruction(parts = listOf(Part(it))) }
        val codexConfig = if (activeProvider == "CODEX_AUTH") {
            settings.buildCodexRequestConfig(activeModel)
        } else {
            null
        }

        val request = GenerateContentRequest(
            contents = applySkillContext(historyPreparation.history, skillContext),
            tools = tools.takeIf { it.isNotEmpty() },
            generationConfig = generationConfig,
            system_instruction = systemInstruction,
            codexConfig = codexConfig,
            promptCacheKey = "conversation-${conversation.id}",
            skillContext = skillContext
        )

        val useClientTools = ClientTools.supportsClientWebSearchTool(activeProvider) &&
            (settings.clientWebSearchToolEnabled || skillDeclarations.isNotEmpty())

        if (useClientTools) {
            scope.launch(Dispatchers.IO) {
                runClientToolCallingTurn(
                    conversationId = conversation.id,
                    model = activeModel,
                    provider = activeProvider,
                    request = request,
                    fullMessagesState = fullMessagesState,
                    fetchFullMessage = fetchFullMessage,
                    existingMessageId = targetMessageId
                )
            }
            return
        }

        if (settings.isStreamingEnabledFor(activeProvider)) {
            responseStreamer.launchStreamingResponse(
                scope = scope,
                conversationId = conversation.id,
                model = activeModel,
                provider = activeProvider,
                request = request,
                fullMessages = fullMessagesState,
                fetchFullMessage = fetchFullMessage,
                existingMessageId = targetMessageId
            )
            return
        }

        if (repository.getFullMessageById(targetMessageId) == null) {
            Log.e(TAG, "Regeneration failed: message not found id=$targetMessageId")
            return
        }

        when (val result = responseStreamer.requestSingleResponse(
            conversationId = conversation.id,
            model = activeModel,
            provider = activeProvider,
            request = request
        )) {
            is ChatResponseStreamer.NonStreamingResult.Success -> {
                repository.insertMessageVariant(
                    baseMessageId = targetMessageId,
                    text = result.text,
                    attachments = result.attachments,
                    thinkingStream = result.thinking.ifBlank { null }
                )
                fetchFullMessage(targetMessageId)
            }
            is ChatResponseStreamer.NonStreamingResult.Failure -> {
                repository.insertMessageVariant(
                    baseMessageId = targetMessageId,
                    text = result.message,
                    attachments = emptyList(),
                    thinkingStream = null
                )
                fetchFullMessage(targetMessageId)
            }
        }
    }

    private suspend fun runClientToolCallingTurn(
        conversationId: Long,
        model: String,
        provider: String,
        request: GenerateContentRequest,
        fullMessagesState: MutableStateFlow<Map<Long, FullChatMessage>>,
        fetchFullMessage: (Long) -> Unit,
        existingMessageId: Long?
    ) {
        var activeVariant: ChatMessageVariant? = null
        val messageId = if (existingMessageId == null) {
            val id = repository.insertMessage(
                ChatMessage(conversationId = conversationId, role = "model", text = "")
            )
            fullMessagesState.update { currentMap ->
                currentMap + (
                    id to FullChatMessage(
                        chatMessage = ChatMessage(
                            id = id,
                            conversationId = conversationId,
                            role = "model",
                            text = ""
                        )
                    )
                )
            }
            id
        } else {
            val existingFull = repository.getFullMessageById(existingMessageId)
            if (existingFull == null) {
                Log.e(TAG, "Tool calling regeneration failed: message not found id=$existingMessageId")
                return
            }
            val createdVariant = repository.insertMessageVariant(
                baseMessageId = existingMessageId,
                text = "",
                attachments = emptyList(),
                thinkingStream = null
            )
            activeVariant = createdVariant
            val selectedBase = existingFull.chatMessage.copy(selectedVariantIndex = createdVariant.variantIndex)
            fullMessagesState.update { currentMap ->
                currentMap + (
                    existingMessageId to existingFull.copy(
                        chatMessage = selectedBase,
                        variants = (existingFull.variants.filterNot { it.variantIndex == createdVariant.variantIndex } + createdVariant)
                            .sortedBy { it.variantIndex }
                    )
                )
            }
            existingMessageId
        }

        fun publishActivities(steps: List<ToolActivityStep>, providerTranscriptJSON: String?) {
            val activity = ChatMessageToolActivity(
                messageId = if (activeVariant == null) messageId else null,
                variantId = activeVariant?.id,
                stepsJSON = ToolActivityStep.encodeSteps(steps),
                providerTranscriptJSON = providerTranscriptJSON
            )
            fullMessagesState.update { currentMap ->
                val existing = currentMap[messageId] ?: return@update currentMap
                if (activeVariant != null) {
                    val variantId = activeVariant!!.id
                    existing.copy(
                        variantToolActivities = existing.variantToolActivities + (variantId to activity)
                    ).let { currentMap + (messageId to it) }
                } else {
                    existing.copy(toolActivity = activity).let { currentMap + (messageId to it) }
                }
            }
        }

        try {
            val result = toolCallingRunner.run(
                baseRequest = request,
                model = model,
                provider = provider,
                onProgressChanged = { progress ->
                    val transcriptJSON = ChatMessageToolActivity.encodeProviderTranscript(
                        progress.replayContents
                    )
                    if (activeVariant != null) {
                        repository.saveToolActivitiesForVariant(
                            variantId = activeVariant!!.id,
                            stepsJSON = ToolActivityStep.encodeSteps(progress.activities),
                            providerTranscriptJSON = transcriptJSON
                        )
                    } else {
                        repository.saveToolActivities(
                            messageId = messageId,
                            stepsJSON = ToolActivityStep.encodeSteps(progress.activities),
                            providerTranscriptJSON = transcriptJSON
                        )
                    }
                    publishActivities(progress.activities, transcriptJSON)
                }
            )

            result.usage?.let { usage ->
                runCatching {
                    repository.recordTokenUsage(
                        provider = provider,
                        model = model,
                        usage = usage,
                        conversationId = conversationId,
                        requestType = "chat_client_tools"
                    )
                }
            }

            val thinking = result.thinking.trim()
            val text = result.text
            val variant = activeVariant
            if (variant != null) {
                val updated = variant.copy(
                    text = text,
                    thinkingStream = thinking.takeIf { it.isNotBlank() }
                )
                repository.updateMessageVariant(updated)
                if (result.activities.isNotEmpty()) {
                    repository.saveToolActivitiesForVariant(
                        variantId = updated.id,
                        stepsJSON = ToolActivityStep.encodeSteps(result.activities),
                        providerTranscriptJSON = ChatMessageToolActivity.encodeProviderTranscript(
                            result.replayContents
                        )
                    )
                }
            } else {
                repository.updateMessage(
                    ChatMessage(
                        id = messageId,
                        conversationId = conversationId,
                        role = "model",
                        text = text,
                        thinkingSummary = thinking.takeIf { it.isNotBlank() }
                    )
                )
                if (thinking.isNotBlank()) {
                    repository.insertThinking(messageId, thinking)
                }
                if (result.activities.isNotEmpty()) {
                    repository.saveToolActivities(
                        messageId = messageId,
                        stepsJSON = ToolActivityStep.encodeSteps(result.activities),
                        providerTranscriptJSON = ChatMessageToolActivity.encodeProviderTranscript(
                            result.replayContents
                        )
                    )
                }
            }
            fetchFullMessage(messageId)
        } catch (e: Exception) {
            Log.e(TAG, "Client tool calling failed", e)
            val errorText = e.message?.takeIf { it.isNotBlank() } ?: "ツール呼び出しに失敗しました"
            val variant = activeVariant
            if (variant != null) {
                repository.updateMessageVariant(variant.copy(text = errorText))
            } else {
                repository.updateMessage(
                    ChatMessage(
                        id = messageId,
                        conversationId = conversationId,
                        role = "model",
                        text = errorText
                    )
                )
            }
            fetchFullMessage(messageId)
        }
    }

    suspend fun sendDualMessage(
        conversationId: Long,
        text: String,
        attachments: List<Uri>,
        dualMessages: List<DualChatMessage>,
        settings: Settings
    ) {
        val conversation = withContext(Dispatchers.IO) { repository.getConversationById(conversationId) }
            ?: run {
                Log.e(TAG, "No conversation found for id: $conversationId")
                return
            }

        val isFirstMessage = dualMessages.isEmpty()
        if (isFirstMessage && conversation.title == "New Chat") {
            withContext(Dispatchers.IO) {
                val newTitle = text.take(50)
                repository.upsertConversation(conversation.copy(title = newTitle))
            }
        }

        val attachmentPaths = withContext(Dispatchers.IO) {
            attachments.mapNotNull { repository.saveAttachment(it) }
        }

        val userDualMessage = DualChatMessage(
            conversationId = conversationId,
            role = "user",
            userText = text,
            attachments = attachmentPaths
        )
        withContext(Dispatchers.IO) { repository.insertDualMessage(userDualMessage) }

        val userMessageParts = historyBuilder.buildNewMessageParts(text, attachments)
        val (historyA, historyB) = historyBuilder.buildDualHistories(dualMessages, userMessageParts)

        val skillContext = repository.agentSkillRepository.requestContext(text, "conversation-$conversationId")
        val declarationsA = if (ClientTools.supportsClientWebSearchTool(settings.dualProviderA)) AgentSkillTools.declarations(repository.agentSkillRepository) else emptyList()
        val declarationsB = if (ClientTools.supportsClientWebSearchTool(settings.dualProviderB)) AgentSkillTools.declarations(repository.agentSkillRepository) else emptyList()
        val toolsForA = appendSkillDeclarations(ToolingUtils.buildTools(settings, settings.dualProviderA, Settings.ReasoningContext.DUAL_A), declarationsA)
        val toolsForB = appendSkillDeclarations(ToolingUtils.buildTools(settings, settings.dualProviderB, Settings.ReasoningContext.DUAL_B), declarationsB)

        val thinkingConfigA = settings.buildThinkingConfigFor(
            provider = settings.dualProviderA,
            model = settings.dualModelA,
            context = Settings.ReasoningContext.DUAL_A
        )

        val thinkingConfigB = settings.buildThinkingConfigFor(
            provider = settings.dualProviderB,
            model = settings.dualModelB,
            context = Settings.ReasoningContext.DUAL_B
        )
        val codexConfigA = if (settings.dualProviderA.uppercase() == "CODEX_AUTH") {
            settings.buildCodexRequestConfig(settings.dualModelA)
        } else {
            null
        }
        val codexConfigB = if (settings.dualProviderB.uppercase() == "CODEX_AUTH") {
            settings.buildCodexRequestConfig(settings.dualModelB)
        } else {
            null
        }

        val requestA = GenerateContentRequest(
            contents = applySkillContext(historyA, skillContext),
            system_instruction = settings.dualSystemPromptA?.let { SystemInstruction(parts = listOf(Part(it))) },
            generationConfig = buildGenerationConfig(settings, settings.dualProviderA, settings.dualModelA, thinkingConfigA),
            tools = toolsForA.takeIf { it.isNotEmpty() }?.toList(),
            codexConfig = codexConfigA,
            promptCacheKey = "conversation-$conversationId-dual-a",
            skillContext = skillContext
        )

        val requestB = GenerateContentRequest(
            contents = applySkillContext(historyB, skillContext),
            system_instruction = settings.dualSystemPromptB?.let { SystemInstruction(parts = listOf(Part(it))) },
            generationConfig = buildGenerationConfig(settings, settings.dualProviderB, settings.dualModelB, thinkingConfigB),
            tools = toolsForB.takeIf { it.isNotEmpty() }?.toList(),
            codexConfig = codexConfigB,
            promptCacheKey = "conversation-$conversationId-dual-b",
            skillContext = skillContext
        )

        val modelDualMessage = DualChatMessage(
            conversationId = conversationId,
            role = "dual_model",
            modelAName = settings.dualModelA,
            modelBName = settings.dualModelB,
            modelAProvider = settings.dualProviderA,
            modelBProvider = settings.dualProviderB
        )
        val modelMessageId = withContext(Dispatchers.IO) { repository.insertDualMessage(modelDualMessage) }

        when (val response = dualChatResponder.generateResponses(
            conversationId = conversationId,
            modelA = settings.dualModelA,
            modelB = settings.dualModelB,
            providerA = settings.dualProviderA,
            providerB = settings.dualProviderB,
            requestA = requestA,
            requestB = requestB
        )) {
            is DualChatResponder.DualResponseResult.Success -> {
                val updatedMessage = modelDualMessage.copy(
                    id = modelMessageId,
                    modelAText = response.textA,
                    modelBText = response.textB,
                    modelAThinking = response.thinkingA,
                    modelBThinking = response.thinkingB
                )
                repository.updateDualMessage(updatedMessage)
            }
            is DualChatResponder.DualResponseResult.Failure -> {
                val updatedMessage = modelDualMessage.copy(
                    id = modelMessageId,
                    modelAText = response.message,
                    modelBText = response.message
                )
                repository.updateDualMessage(updatedMessage)
            }
        }
    }

    private fun appendSkillDeclarations(
        tools: List<com.porarri.yamabikochat.data.remote.Tool>,
        declarations: List<com.porarri.yamabikochat.data.remote.FunctionDeclaration>
    ): List<com.porarri.yamabikochat.data.remote.Tool> {
        if (declarations.isEmpty()) return tools
        val result = tools.toMutableList()
        val index = result.indexOfFirst { it.function_declarations != null }
        if (index >= 0) result[index] = result[index].copy(function_declarations = result[index].function_declarations.orEmpty() + declarations)
        else result += com.porarri.yamabikochat.data.remote.Tool(function_declarations = declarations)
        return result
    }

    private fun applySkillContext(contents: List<Content>, context: SkillRequestContext?): List<Content> {
        if (context == null) return contents
        val injection = listOfNotNull(context.syntheticUserContext, context.explicitUserContext).joinToString("\n\n")
        if (injection.isBlank()) return contents
        val index = contents.indexOfLast { it.role == "user" }
        if (index < 0) return contents
        return contents.toMutableList().also { result ->
            val content = result[index]
            val parts = content.parts.toMutableList()
            val textIndex = parts.indexOfLast { it.text != null }
            if (textIndex >= 0) parts[textIndex] = parts[textIndex].copy(text = parts[textIndex].text.orEmpty() + "\n\n" + injection)
            else parts += Part(text = injection)
            result[index] = content.copy(parts = parts)
        }
    }

    private fun buildGenerationConfig(
        settings: Settings,
        provider: String,
        model: String,
        thinkingConfig: com.porarri.yamabikochat.data.remote.ThinkingConfig?
    ): GenerationConfig {
        val base = GenerationConfig(thinkingConfig = thinkingConfig)
        if (provider.uppercase() != "GEMINI") return base

        val responseMimeType = settings.geminiResponseMimeType.trim().takeIf { it.isNotEmpty() }
        val responseJsonSchema = settings.geminiResponseJsonSchema.trim().takeIf { it.isNotEmpty() }?.let { raw ->
            runCatching { json.parseToJsonElement(raw) }.getOrElse { err ->
                Log.w(TAG, "Invalid response JSON schema for model=$model: ${err.message}")
                null
            }
        }

        return base.copy(
            responseMimeType = responseMimeType,
            responseJsonSchema = responseJsonSchema
        )
    }

    companion object {
        private const val TAG = "ChatInteractionCoordinator"
    }
}
