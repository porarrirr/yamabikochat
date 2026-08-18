package com.porarri.yamabikochat.ui.chat.logic

import android.util.Log
import com.porarri.yamabikochat.data.ChatRepository
import com.porarri.yamabikochat.data.local.ChatMessage
import com.porarri.yamabikochat.data.local.ChatMessageVariant
import com.porarri.yamabikochat.data.local.ChatMessageToolActivity
import com.porarri.yamabikochat.data.local.FullChatMessage
import com.porarri.yamabikochat.data.local.ToolActivityPayload
import com.porarri.yamabikochat.data.local.ToolActivityStep
import com.porarri.yamabikochat.data.model.ProviderRequest
import com.porarri.yamabikochat.data.model.ProviderStreamEvent
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import com.porarri.yamabikochat.utils.UserFacingErrorFormatter
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
                thinkingStream: String,
                toolPayload: ToolActivityPayload
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
                                    .sortedBy { it.variantIndex },
                                variantToolActivities = liveActivity(null, updatedVariant.id, toolPayload)?.let {
                                    existing.variantToolActivities + (updatedVariant.id to it)
                                } ?: existing.variantToolActivities
                            )
                            currentMap + (messageId to updatedFull)
                        } else {
                            val updatedFull = existing.copy(
                                chatMessage = existing.chatMessage.copy(
                                    text = text,
                                    attachments = attachments,
                                    thinkingSummary = thinkingSummary
                                ),
                                thinkingStream = thinkingStream.takeIf { it.isNotBlank() },
                                toolActivity = liveActivity(messageId, null, toolPayload)
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
            var toolPayload = ToolActivityPayload()
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
                        is ProviderStreamEvent.ToolActivity -> {
                            toolPayload = toolPayload.applying(event.event)
                            updateFullMessageState(
                                textAccumulator,
                                emptyList(),
                                null,
                                thinkingAccumulator,
                                toolPayload
                            )
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
                                thinkingStream = thinkingAccumulator,
                                toolPayload = toolPayload
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
                            thinkingStream = thinkingAccumulator,
                            toolPayload = toolPayload
                        )
                    }
                }
            } catch (e: Exception) {
                DiagnosticsLogger.log("Streaming failed messageId=$messageId", e)
                val errText = textAccumulator.ifBlank { UserFacingErrorFormatter.placeholder(e) }
                if (activeVariant != null) {
                    repository.updateMessageVariant(activeVariant!!.copy(text = errText))
                } else {
                    val full = repository.getFullMessageById(messageId)
                    if (full != null) {
                        repository.updateMessage(full.chatMessage.copy(text = errText))
                    }
                }
                toolPayload = toolPayload.failRunning("ツールの実行が中断されました")
                if (toolPayload.steps.isNotEmpty()) {
                    activeVariant?.id?.let { repository.saveToolActivityForVariant(it, toolPayload) }
                        ?: repository.saveToolActivity(messageId, toolPayload)
                }
                updateFullMessageState(errText, emptyList(), null, thinkingAccumulator, toolPayload)
            }
            if (toolPayload.steps.isNotEmpty()) {
                activeVariant?.id?.let { repository.saveToolActivityForVariant(it, toolPayload) }
                    ?: repository.saveToolActivity(messageId, toolPayload)
            }
        }
    }

    private fun liveActivity(
        messageId: Long?,
        variantId: Long?,
        payload: ToolActivityPayload
    ): ChatMessageToolActivity? = payload.steps.takeIf { it.isNotEmpty() }?.let {
        ChatMessageToolActivity(
            messageId = messageId,
            variantId = variantId,
            stepsJSON = ToolActivityStep.encodeSteps(it),
            providerTranscriptJSON = ChatMessageToolActivity.encodeProviderTranscript(payload.providerTranscript)
        )
    }
}
