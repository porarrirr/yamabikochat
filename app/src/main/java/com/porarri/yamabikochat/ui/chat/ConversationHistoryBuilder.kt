package com.porarri.yamabikochat.ui.chat

import android.net.Uri
import com.porarri.yamabikochat.data.ChatRepository
import com.porarri.yamabikochat.data.local.ChatMessageSummary
import com.porarri.yamabikochat.data.local.DualChatMessage
import com.porarri.yamabikochat.data.remote.Content
import com.porarri.yamabikochat.data.remote.Part
import com.porarri.yamabikochat.data.local.FullChatMessage
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class ConversationHistoryBuilder(
    private val repository: ChatRepository,
    private val ioDispatcher: CoroutineDispatcher = Dispatchers.IO,
    private val maxHistoryMessages: Int = DEFAULT_MAX_HISTORY_MESSAGES,
    private val attachmentCacheSize: Int = DEFAULT_ATTACHMENT_CACHE_SIZE
) {

    private val attachmentCache = object : LinkedHashMap<String, Part?>(attachmentCacheSize, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Part?>?): Boolean {
            return size > attachmentCacheSize
        }
    }

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
        val sessionAttachmentCache = mutableMapOf<String, Part?>()

        val history = limitedSummaries.flatMap { summary ->
            val fullMessage = combinedMessages[summary.id] ?: return@flatMap emptyList()
            val parts = resolveStoredMessageParts(
                message = fullMessage,
                sessionCache = sessionAttachmentCache,
                includeThoughts = includeModelThoughts
            )
            val finalContent = Content(role = fullMessage.chatMessage.role, parts = parts)
            if (fullMessage.chatMessage.role == "model") {
                val activity = fullMessage.displayToolActivity
                val providerTranscript = activity?.providerTranscript
                if (activity != null && activity.steps.isNotEmpty() && providerTranscript == null) {
                    DiagnosticsLogger.log(
                        "Stored tool activity has no replayable provider transcript message=${summary.id}"
                    )
                }
                providerTranscript.orEmpty() + finalContent
            } else {
                listOf(finalContent)
            }
        }.toMutableList()

        val userMessageParts = buildNewMessageParts(text, attachmentsToSend)
        history.add(Content(role = "user", parts = userMessageParts))

        HistoryPreparation(history, fetched)
    }

    suspend fun buildDualHistories(
        existingMessages: List<DualChatMessage>,
        currentUserParts: List<Part>
    ): Pair<List<Content>, List<Content>> = withContext(ioDispatcher) {
        val historyA = mutableListOf<Content>()
        val historyB = mutableListOf<Content>()
        val sessionAttachmentCache = mutableMapOf<String, Part?>()

        for (message in existingMessages) {
            when (message.role) {
                "user" -> {
                    val parts = resolveDualUserMessageParts(message, sessionAttachmentCache)
                    historyA.add(Content(role = "user", parts = parts))
                    historyB.add(Content(role = "user", parts = parts))
                }
                "modelA" -> {
                    val parts = resolveDualModelParts(message.modelAText, message.attachments, sessionAttachmentCache)
                    historyA.add(Content(role = "model", parts = parts))
                    historyB.add(Content(role = "user", parts = parts))
                }
                "modelB" -> {
                    val parts = resolveDualModelParts(message.modelBText, message.attachments, sessionAttachmentCache)
                    historyA.add(Content(role = "user", parts = parts))
                    historyB.add(Content(role = "model", parts = parts))
                }
            }
        }

        historyA.add(Content(role = "user", parts = currentUserParts))
        historyB.add(Content(role = "user", parts = currentUserParts))

        historyA to historyB
    }

    private suspend fun resolveStoredMessageParts(
        message: FullChatMessage,
        sessionCache: MutableMap<String, Part?>,
        includeThoughts: Boolean
    ): List<Part> {
        val chatMessage = message.chatMessage
        val baseText = if (includeThoughts && chatMessage.role == "model") {
            val thought = message.displayThinkingStream?.takeIf { it.isNotBlank() }
            if (thought != null) "<think>$thought</think>\n${message.displayText}" else message.displayText
        } else {
            message.displayText
        }
        val parts = mutableListOf(Part(text = baseText))
        for (path in message.displayAttachments) {
            val key = path
            val cached = sessionCache[key] ?: getCachedPart(key)
            val resolved = cached ?: repository.getPartFromUri(Uri.parse(path)).also { part ->
                sessionCache[key] = part
                putCachedPart(key, part)
            }
            if (resolved != null) {
                parts.add(resolved)
            }
        }
        return parts
    }

    suspend fun buildNewMessageParts(
        text: String,
        attachments: List<Uri>
    ): List<Part> {
        val parts = mutableListOf(Part(text = text))
        for (uri in attachments) {
            val key = uri.toString()
            val cached = getCachedPart(key)
            val resolved = cached ?: repository.getPartFromUri(uri).also { part ->
                putCachedPart(key, part)
            }
            if (resolved != null) {
                parts.add(resolved)
            }
        }
        return parts
    }

    private suspend fun resolveDualUserMessageParts(
        message: DualChatMessage,
        sessionCache: MutableMap<String, Part?>
    ): List<Part> {
        val parts = mutableListOf(Part(text = message.userText))
        for (attachment in message.attachments) {
            val key = attachment
            val cached = sessionCache[key] ?: getCachedPart(key)
            val resolved = cached ?: repository.getPartFromUri(Uri.parse(attachment)).also { part ->
                sessionCache[key] = part
                putCachedPart(key, part)
            }
            if (resolved != null) {
                parts.add(resolved)
            }
        }
        return parts
    }

    private suspend fun resolveDualModelParts(
        text: String,
        attachments: List<String>,
        sessionCache: MutableMap<String, Part?>
    ): List<Part> {
        val parts = mutableListOf(Part(text = text))
        for (attachment in attachments) {
            val key = attachment
            val cached = sessionCache[key] ?: getCachedPart(key)
            val resolved = cached ?: repository.getPartFromUri(Uri.parse(attachment)).also { part ->
                sessionCache[key] = part
                putCachedPart(key, part)
            }
            if (resolved != null) {
                parts.add(resolved)
            }
        }
        return parts
    }

    private fun getCachedPart(key: String): Part? = synchronized(attachmentCache) {
        attachmentCache[key]
    }

    private fun putCachedPart(key: String, part: Part?) {
        synchronized(attachmentCache) {
            attachmentCache[key] = part
        }
    }

    data class HistoryPreparation(
        val history: List<Content>,
        val newlyFetchedMessages: Map<Long, FullChatMessage>
    )

    companion object {
        private const val DEFAULT_MAX_HISTORY_MESSAGES = 20
        private const val DEFAULT_ATTACHMENT_CACHE_SIZE = 32
    }
}
