package com.porarri.yamabikochat.ui.chat.logic

import android.net.Uri
import android.util.Log
import com.porarri.yamabikochat.data.ChatRepository
import com.porarri.yamabikochat.data.local.ChatMessage
import com.porarri.yamabikochat.data.local.ChatMessageSummary
import com.porarri.yamabikochat.data.local.Conversation
import com.porarri.yamabikochat.data.local.DualChatMessage
import com.porarri.yamabikochat.data.local.FullChatMessage
import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.data.remote.GenerateContentRequest
import com.porarri.yamabikochat.data.remote.GenerationConfig
import com.porarri.yamabikochat.data.remote.Part
import com.porarri.yamabikochat.data.remote.SystemInstruction
import com.porarri.yamabikochat.ui.chat.ConversationHistoryBuilder
import com.porarri.yamabikochat.utils.MiniMaxUtils
import com.porarri.yamabikochat.utils.ToolingUtils
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json

class ChatInteractionCoordinator(
    private val repository: ChatRepository,
    private val historyBuilder: ConversationHistoryBuilder,
    private val responseStreamer: ChatResponseStreamer,
    private val dualChatResponder: DualChatResponder
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

        val tools = ToolingUtils.buildTools(settings, activeProvider)
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
            contents = historyPreparation.history,
            tools = tools.takeIf { it.isNotEmpty() },
            generationConfig = generationConfig,
            system_instruction = systemInstruction,
            codexConfig = codexConfig,
            promptCacheKey = "conversation-${conversation.id}"
        )

        if (skipModelResponse) {
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

        val tools = ToolingUtils.buildTools(settings, activeProvider)
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
            contents = historyPreparation.history,
            tools = tools.takeIf { it.isNotEmpty() },
            generationConfig = generationConfig,
            system_instruction = systemInstruction,
            codexConfig = codexConfig,
            promptCacheKey = "conversation-${conversation.id}"
        )

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

        val existingMessage = repository.getFullMessageById(targetMessageId)?.chatMessage
        if (existingMessage == null) {
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
                repository.updateMessage(
                    existingMessage.copy(
                        text = result.text,
                        attachments = result.attachments,
                        thinkingSummary = result.thinking.ifBlank { null }
                    )
                )
                if (result.thinking.isNotBlank()) {
                    repository.insertThinking(targetMessageId, result.thinking)
                } else {
                    repository.updateThinkingStream(targetMessageId, "")
                }
                fetchFullMessage(targetMessageId)
            }
            is ChatResponseStreamer.NonStreamingResult.Failure -> {
                repository.updateMessage(
                    existingMessage.copy(
                        text = result.message,
                        attachments = emptyList(),
                        thinkingSummary = null
                    )
                )
                repository.updateThinkingStream(targetMessageId, "")
                fetchFullMessage(targetMessageId)
            }
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

        val toolsForA = ToolingUtils.buildTools(settings, settings.dualProviderA, Settings.ReasoningContext.DUAL_A)
        val toolsForB = ToolingUtils.buildTools(settings, settings.dualProviderB, Settings.ReasoningContext.DUAL_B)

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
            contents = historyA,
            system_instruction = settings.dualSystemPromptA?.let { SystemInstruction(parts = listOf(Part(it))) },
            generationConfig = buildGenerationConfig(settings, settings.dualProviderA, settings.dualModelA, thinkingConfigA),
            tools = toolsForA.takeIf { it.isNotEmpty() }?.toList(),
            codexConfig = codexConfigA,
            promptCacheKey = "conversation-$conversationId-dual-a"
        )

        val requestB = GenerateContentRequest(
            contents = historyB,
            system_instruction = settings.dualSystemPromptB?.let { SystemInstruction(parts = listOf(Part(it))) },
            generationConfig = buildGenerationConfig(settings, settings.dualProviderB, settings.dualModelB, thinkingConfigB),
            tools = toolsForB.takeIf { it.isNotEmpty() }?.toList(),
            codexConfig = codexConfigB,
            promptCacheKey = "conversation-$conversationId-dual-b"
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
