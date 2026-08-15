package com.porarri.yamabikochat.ui.chat.logic

import android.util.Log
import com.porarri.yamabikochat.data.ChatRepository
import com.porarri.yamabikochat.data.local.ChatMessage
import com.porarri.yamabikochat.data.local.ChatMessageVariant
import com.porarri.yamabikochat.data.local.FullChatMessage
import com.porarri.yamabikochat.data.model.ProviderRequest
import com.porarri.yamabikochat.data.model.ProviderStreamEvent
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

class ChatResponseStreamer(
    private val repository: ChatRepository
) {
    fun launchStreamingResponse(
        scope: CoroutineScope,
        conversationId: Long,
        model: String,
        provider: String,
        request: ProviderRequest,
        fullMessages: MutableStateFlow<Map<Long, FullChatMessage>>,
        fetchFullMessage: (Long) -> Unit,
        existingMessageId: Long? = null
    ) {
        scope.launch(Dispatchers.IO) {
            val isRegeneration = existingMessageId != null
            var activeVariant: ChatMessageVariant? = null
            val messageId = if (existingMessageId == null) {
                val placeholderMessage =
                    ChatMessage(conversationId = conversationId, role = "model", text = "")
                repository.insertMessage(placeholderMessage)
            } else {
                val existingFull = repository.getFullMessageById(existingMessageId)
                if (existingFull == null) {
                    Log.e("ChatResponseStreamer", "Regeneration failed: message not found id=$existingMessageId")
                    return@launch
                }
                val createdVariant = repository.insertMessageVariant(
                    baseMessageId = existingMessageId,
                    text = "",
                    attachments = emptyList(),
                    thinkingStream = null
                )
                activeVariant = createdVariant
                val selectedBase = existingFull.chatMessage.copy(selectedVariantIndex = createdVariant.variantIndex)
                fullMessages.update { currentMap ->
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

            fun updateFullMessageState(
                text: String,
                attachments: List<String>,
                thinkingSummary: String?,
                thinkingStream: String
            ) {
                fullMessages.update { currentMap ->
                    val existing = currentMap[messageId]
                    if (existing != null) {
                        if (activeVariant != null) {
                            val updatedVariant = activeVariant!!.copy(
                                text = text,
                                attachments = attachments,
                                thinkingStream = thinkingStream.ifBlank { null }
                            )
                            activeVariant = updatedVariant
                            val updatedFull = existing.copy(
                                chatMessage = existing.chatMessage.copy(selectedVariantIndex = updatedVariant.variantIndex),
                                variants = (existing.variants.filterNot { it.variantIndex == updatedVariant.variantIndex } + updatedVariant)
                                    .sortedBy { it.variantIndex }
                            )
                            currentMap + (messageId to updatedFull)
                        } else {
                            val updatedFull = existing.copy(
                                chatMessage = existing.chatMessage.copy(
                                    text = text,
                                    attachments = attachments,
                                    thinkingSummary = thinkingSummary
                                ),
                                thinkingStream = thinkingStream.takeIf { it.isNotBlank() }
                            )
                            currentMap + (messageId to updatedFull)
                        }
                    } else {
                        currentMap
                    }
                }
            }

            var textAccumulator = ""
            var thinkingAccumulator = ""
            var lastUiUpdateMs = 0L

            try {
                repository.streamProviderRequest(request, provider).collect { event ->
                    when (event) {
                        is ProviderStreamEvent.TextDelta -> {
                            textAccumulator += event.delta
                        }
                        is ProviderStreamEvent.ReasoningDelta -> {
                            thinkingAccumulator += event.delta
                        }
                        is ProviderStreamEvent.Completed -> {
                            val response = event.response
                            if (response.text.isNotBlank()) textAccumulator = response.text
                            val thinkingSummary = response.reasoningSummary ?: thinkingAccumulator.takeIf { it.isNotBlank() }

                            if (activeVariant != null) {
                                repository.updateMessageVariant(
                                    activeVariant!!.copy(
                                        text = textAccumulator,
                                        thinkingStream = thinkingAccumulator.ifBlank { null }
                                    )
                                )
                            } else {
                                val full = repository.getFullMessageById(messageId)
                                if (full != null) {
                                    repository.updateMessage(
                                        full.chatMessage.copy(
                                            text = textAccumulator,
                                            thinkingSummary = thinkingSummary
                                        )
                                    )
                                    if (thinkingAccumulator.isNotBlank()) {
                                        repository.insertThinking(messageId, thinkingAccumulator)
                                    }
                                }
                            }

                            response.usage?.let { usage ->
                                repository.recordTokenUsage(
                                    provider = provider,
                                    model = model,
                                    usage = usage,
                                    conversationId = conversationId,
                                    requestType = "chat"
                                )
                            }

                            updateFullMessageState(
                                text = textAccumulator,
                                attachments = emptyList(),
                                thinkingSummary = thinkingSummary,
                                thinkingStream = thinkingAccumulator
                            )
                        }
                    }

                    val now = System.currentTimeMillis()
                    if (now - lastUiUpdateMs >= 60L) {
                        lastUiUpdateMs = now
                        updateFullMessageState(
                            text = textAccumulator,
                            attachments = emptyList(),
                            thinkingSummary = null,
                            thinkingStream = thinkingAccumulator
                        )
                    }
                }
            } catch (e: Exception) {
                DiagnosticsLogger.log("Streaming failed messageId=$messageId", e)
                val errText = textAccumulator.ifBlank { "エラー: ${e.message ?: "通信に失敗しました"}" }
                if (activeVariant != null) {
                    repository.updateMessageVariant(activeVariant!!.copy(text = errText))
                } else {
                    val full = repository.getFullMessageById(messageId)
                    if (full != null) {
                        repository.updateMessage(full.chatMessage.copy(text = errText))
                    }
                }
                updateFullMessageState(errText, emptyList(), null, thinkingAccumulator)
            }
        }
    }
}
