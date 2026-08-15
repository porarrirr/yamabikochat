package com.porarri.yamabikochat.ui.chat

import android.net.Uri
import com.porarri.yamabikochat.data.ChatRepository
import com.porarri.yamabikochat.data.local.ChatMessageSummary
import com.porarri.yamabikochat.data.local.DualChatMessage
import com.porarri.yamabikochat.data.local.FullChatMessage
import com.porarri.yamabikochat.data.model.ProviderRequestMessage
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

data class HistoryPreparation(
    val messages: List<ProviderRequestMessage>,
    val newlyFetchedMessages: Map<Long, FullChatMessage>
)

class ConversationHistoryBuilder(
    private val repository: ChatRepository,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
    private val maxHistoryMessages: Int = DEFAULT_MAX_HISTORY_MESSAGES
) {
    suspend fun buildStandardHistory(
        text: String,
        attachmentsToSend: List<Uri>,
        messageSummaries: List<ChatMessageSummary>,
        existingFullMessages: Map<Long, FullChatMessage>,
        includeModelThoughts: Boolean = false
    ): HistoryPreparation = withContext(ioDispatcher) {
        val limitedSummaries = if (messageSummaries.size > maxHistoryMessages) {
            messageSummaries.takeLast(maxHistoryMessages)
        } else {
            messageSummaries
        }

        val missingIds = limitedSummaries.map { it.id }.filterNot { existingFullMessages.containsKey(it) }
        val fetched = repository.getFullMessagesByIds(missingIds)
        val combinedMessages = existingFullMessages + fetched

        val history = limitedSummaries.mapNotNull { summary ->
            val full = combinedMessages[summary.id] ?: return@mapNotNull null
            val role = if (full.chatMessage.role == "model" || full.chatMessage.role == "assistant") "assistant" else "user"
            val effectiveText = full.displayText
            val effectiveAttachments = full.displayAttachments
            val effectiveThought = if (includeModelThoughts) full.displayThinkingStream ?: full.chatMessage.thinkingSummary else null

            ProviderRequestMessage(
                role = role,
                content = effectiveText,
                attachments = effectiveAttachments,
                reasoningContent = effectiveThought
            )
        }.toMutableList()

        val newAttachmentPaths = attachmentsToSend.mapNotNull { repository.saveAttachment(it) }
        history.add(
            ProviderRequestMessage(
                role = "user",
                content = text,
                attachments = newAttachmentPaths
            )
        )

        HistoryPreparation(history, fetched)
    }

    suspend fun buildDualHistories(
        existingMessages: List<DualChatMessage>,
        currentText: String,
        currentAttachmentUris: List<Uri>
    ): Pair<List<ProviderRequestMessage>, List<ProviderRequestMessage>> = withContext(ioDispatcher) {
        val historyA = mutableListOf<ProviderRequestMessage>()
        val historyB = mutableListOf<ProviderRequestMessage>()

        val newAttachmentPaths = currentAttachmentUris.mapNotNull { repository.saveAttachment(it) }

        for (message in existingMessages) {
            when (message.role) {
                "user" -> {
                    val msg = ProviderRequestMessage(role = "user", content = message.userText, attachments = message.attachments)
                    historyA.add(msg)
                    historyB.add(msg)
                }
                "modelA" -> {
                    historyA.add(ProviderRequestMessage(role = "assistant", content = message.modelAText, reasoningContent = message.modelAThinking))
                    historyB.add(ProviderRequestMessage(role = "user", content = message.modelAText))
                }
                "modelB" -> {
                    historyA.add(ProviderRequestMessage(role = "user", content = message.modelBText))
                    historyB.add(ProviderRequestMessage(role = "assistant", content = message.modelBText, reasoningContent = message.modelBThinking))
                }
            }
        }

        val userMsg = ProviderRequestMessage(role = "user", content = currentText, attachments = newAttachmentPaths)
        historyA.add(userMsg)
        historyB.add(userMsg)

        Pair(historyA, historyB)
    }

    companion object {
        const val DEFAULT_MAX_HISTORY_MESSAGES = 100
    }
}
