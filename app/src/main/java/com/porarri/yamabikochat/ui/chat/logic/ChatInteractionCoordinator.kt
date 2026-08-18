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
import com.porarri.yamabikochat.data.model.ProviderRequest
import com.porarri.yamabikochat.ui.chat.ConversationHistoryBuilder
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.withContext

class ChatInteractionCoordinator(
    private val repository: ChatRepository,
    private val historyBuilder: ConversationHistoryBuilder,
    private val responseStreamer: ChatResponseStreamer,
    private val dualChatResponder: DualChatResponder
) {
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

        val historyPreparation = historyBuilder.buildStandardHistory(
            text = text,
            attachmentsToSend = attachments,
            messageSummaries = messageSummaries,
            existingFullMessages = fullMessagesState.value,
            includeModelThoughts = false
        )

        if (historyPreparation.newlyFetchedMessages.isNotEmpty()) {
            fullMessagesState.update { it + historyPreparation.newlyFetchedMessages }
        }

        if (skipModelResponse) {
            return SingleMessageResult(historyPreparation.newlyFetchedMessages)
        }

        val activeProvider = conversation.apiProvider.ifBlank { settings.apiProvider }
        val activeModel = conversation.model.ifBlank { settings.getCurrentModel() }
        val systemPrompt = conversation.systemPrompt ?: settings.systemPrompt

        val request = repository.buildProviderRequest(
            conversation = conversation,
            settings = settings,
            provider = activeProvider,
            model = activeModel,
            messages = historyPreparation.messages,
            systemPrompt = systemPrompt
        )

        responseStreamer.launchStreamingResponse(
            scope = scope,
            conversationId = conversation.id,
            model = activeModel,
            provider = activeProvider,
            request = request,
            fullMessages = fullMessagesState,
            fetchFullMessage = fetchFullMessage
        )

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

        val historyPreparation = historyBuilder.buildStandardHistory(
            text = userMessage.text,
            attachmentsToSend = userMessage.attachments.map { Uri.parse(it) },
            messageSummaries = messageSummariesBefore,
            existingFullMessages = fullMessagesState.value,
            includeModelThoughts = false
        )

        if (historyPreparation.newlyFetchedMessages.isNotEmpty()) {
            fullMessagesState.update { it + historyPreparation.newlyFetchedMessages }
        }

        val activeProvider = conversation.apiProvider.ifBlank { settings.apiProvider }
        val activeModel = conversation.model.ifBlank { settings.getCurrentModel() }
        val systemPrompt = conversation.systemPrompt ?: settings.systemPrompt

        val request = repository.buildProviderRequest(
            conversation = conversation,
            settings = settings,
            provider = activeProvider,
            model = activeModel,
            messages = historyPreparation.messages,
            systemPrompt = systemPrompt
        )

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

        val (historyA, historyB) = historyBuilder.buildDualHistories(dualMessages, text, attachments)

        val requestA = repository.buildProviderRequest(
            conversation = conversation,
            settings = settings,
            provider = settings.dualProviderA,
            model = settings.dualModelA,
            messages = historyA,
            systemPrompt = settings.dualSystemPromptA ?: conversation.systemPrompt ?: settings.systemPrompt,
            context = Settings.ReasoningContext.DUAL_A,
            promptCacheKey = "conversation-${conversationId}-dual-a"
        )

        val requestB = repository.buildProviderRequest(
            conversation = conversation,
            settings = settings,
            provider = settings.dualProviderB,
            model = settings.dualModelB,
            messages = historyB,
            systemPrompt = settings.dualSystemPromptB ?: conversation.systemPrompt ?: settings.systemPrompt,
            context = Settings.ReasoningContext.DUAL_B,
            promptCacheKey = "conversation-${conversationId}-dual-b"
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

        when (val response = dualChatResponder.streamResponses(
            conversationId = conversationId,
            modelA = settings.dualModelA,
            modelB = settings.dualModelB,
            providerA = settings.dualProviderA,
            providerB = settings.dualProviderB,
            requestA = requestA,
            requestB = requestB,
            onProgress = { partial ->
                val partialMsg = modelDualMessage.copy(
                    id = modelMessageId,
                    modelAText = partial.textA,
                    modelBText = partial.textB,
                    modelAThinking = partial.thinkingA,
                    modelBThinking = partial.thinkingB,
                    modelAToolActivityJSON = DualChatMessage.encodeToolActivity(partial.toolActivityA),
                    modelBToolActivityJSON = DualChatMessage.encodeToolActivity(partial.toolActivityB)
                )
                repository.updateDualMessage(partialMsg)
            }
        )) {
            is DualChatResponder.DualResponseResult.Success -> {
                val updatedMessage = modelDualMessage.copy(
                    id = modelMessageId,
                    modelAText = response.textA,
                    modelBText = response.textB,
                    modelAThinking = response.thinkingA,
                    modelBThinking = response.thinkingB,
                    modelAToolActivityJSON = DualChatMessage.encodeToolActivity(response.toolActivityA),
                    modelBToolActivityJSON = DualChatMessage.encodeToolActivity(response.toolActivityB)
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

    companion object {
        private const val TAG = "ChatInteractionCoordinator"
    }
}
