package com.porarri.yamabikochat.ui.chat.logic

import com.porarri.yamabikochat.data.ChatRepository
import com.porarri.yamabikochat.data.model.ProviderRequest
import com.porarri.yamabikochat.data.model.ProviderStreamEvent
import com.porarri.yamabikochat.data.local.ToolActivityPayload
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import com.porarri.yamabikochat.utils.UserFacingErrorFormatter
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

class DualChatResponder(
    private val repository: ChatRepository
) {
    suspend fun generateResponses(
        conversationId: Long,
        modelA: String,
        modelB: String,
        providerA: String,
        providerB: String,
        requestA: ProviderRequest,
        requestB: ProviderRequest
    ): DualResponseResult = coroutineScope {
        try {
            val callA = async { repository.generateProviderRequest(requestA, providerA) }
            val callB = async { repository.generateProviderRequest(requestB, providerB) }
            val resA = callA.await()
            val resB = callB.await()

            resA.usage?.let { repository.recordTokenUsage(providerA, modelA, it, conversationId, "dual") }
            resB.usage?.let { repository.recordTokenUsage(providerB, modelB, it, conversationId, "dual") }

            DualResponseResult.Success(
                textA = resA.text.ifBlank { FALLBACK_MESSAGE },
                textB = resB.text.ifBlank { FALLBACK_MESSAGE },
                thinkingA = resA.reasoningSummary?.ifBlank { null },
                thinkingB = resB.reasoningSummary?.ifBlank { null },
                toolActivityA = resA.toolActivity,
                toolActivityB = resB.toolActivity
            )
        } catch (e: Exception) {
            DiagnosticsLogger.log("Dual generate request failed", e)
            DualResponseResult.Failure(UserFacingErrorFormatter.placeholder(e))
        }
    }

    suspend fun streamResponses(
        conversationId: Long,
        modelA: String,
        modelB: String,
        providerA: String,
        providerB: String,
        requestA: ProviderRequest,
        requestB: ProviderRequest,
        onProgress: suspend (DualPartialProgress) -> Unit
    ): DualResponseResult = coroutineScope {
        val textA = AtomicReference("")
        val textB = AtomicReference("")
        val thinkingA = AtomicReference("")
        val thinkingB = AtomicReference("")
        val toolActivityA = AtomicReference(ToolActivityPayload())
        val toolActivityB = AtomicReference(ToolActivityPayload())

        val lastEmitMs = AtomicLong(0L)
        val emitMutex = Mutex()

        suspend fun emitPartial(force: Boolean) {
            val now = System.currentTimeMillis()
            if (!force && now - lastEmitMs.get() < PARTIAL_EMIT_INTERVAL_MS) return
            emitMutex.withLock {
                if (!force && now - lastEmitMs.get() < PARTIAL_EMIT_INTERVAL_MS) return@withLock
                lastEmitMs.set(now)
                onProgress(
                    DualPartialProgress(
                        textA = textA.get(),
                        textB = textB.get(),
                        thinkingA = thinkingA.get().ifBlank { null },
                        thinkingB = thinkingB.get().ifBlank { null },
                        toolActivityA = toolActivityA.get().takeIf { it.steps.isNotEmpty() },
                        toolActivityB = toolActivityB.get().takeIf { it.steps.isNotEmpty() }
                    )
                )
            }
        }

        try {
            val jobA = async {
                try {
                    repository.streamProviderRequest(requestA, providerA).collect { event ->
                        when (event) {
                            ProviderStreamEvent.AnswerStart -> {
                                textA.set("")
                                emitPartial(false)
                            }
                            is ProviderStreamEvent.TextDelta -> {
                                textA.set(textA.get() + event.delta)
                                emitPartial(false)
                            }
                            is ProviderStreamEvent.ReasoningDelta -> {
                                thinkingA.set(thinkingA.get() + event.delta)
                                emitPartial(false)
                            }
                            is ProviderStreamEvent.ToolActivity -> {
                                toolActivityA.set(toolActivityA.get().applying(event.event))
                                emitPartial(true)
                            }
                            is ProviderStreamEvent.Completed -> {
                                if (event.response.text.isNotBlank()) textA.set(event.response.text)
                                event.response.reasoningSummary?.let { thinkingA.set(it) }
                                event.response.providerTranscript?.let { transcript ->
                                    toolActivityA.set(toolActivityA.get().copy(providerTranscript = transcript))
                                }
                                event.response.usage?.let {
                                    repository.recordTokenUsage(providerA, modelA, it, conversationId, "dual_stream")
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    DiagnosticsLogger.log("Dual stream side A failed", e)
                    toolActivityA.set(toolActivityA.get().failRunning("ツールの実行が中断されました"))
                    textA.set(textA.get().ifBlank { UserFacingErrorFormatter.placeholder(e) })
                    emitPartial(true)
                }
            }

            val jobB = async {
                try {
                    repository.streamProviderRequest(requestB, providerB).collect { event ->
                        when (event) {
                            ProviderStreamEvent.AnswerStart -> {
                                textB.set("")
                                emitPartial(false)
                            }
                            is ProviderStreamEvent.TextDelta -> {
                                textB.set(textB.get() + event.delta)
                                emitPartial(false)
                            }
                            is ProviderStreamEvent.ReasoningDelta -> {
                                thinkingB.set(thinkingB.get() + event.delta)
                                emitPartial(false)
                            }
                            is ProviderStreamEvent.ToolActivity -> {
                                toolActivityB.set(toolActivityB.get().applying(event.event))
                                emitPartial(true)
                            }
                            is ProviderStreamEvent.Completed -> {
                                if (event.response.text.isNotBlank()) textB.set(event.response.text)
                                event.response.reasoningSummary?.let { thinkingB.set(it) }
                                event.response.providerTranscript?.let { transcript ->
                                    toolActivityB.set(toolActivityB.get().copy(providerTranscript = transcript))
                                }
                                event.response.usage?.let {
                                    repository.recordTokenUsage(providerB, modelB, it, conversationId, "dual_stream")
                                }
                            }
                        }
                    }
                } catch (e: Exception) {
                    DiagnosticsLogger.log("Dual stream side B failed", e)
                    toolActivityB.set(toolActivityB.get().failRunning("ツールの実行が中断されました"))
                    textB.set(textB.get().ifBlank { UserFacingErrorFormatter.placeholder(e) })
                    emitPartial(true)
                }
            }

            jobA.await()
            jobB.await()
            emitPartial(force = true)

            DualResponseResult.Success(
                textA = textA.get().ifBlank { FALLBACK_MESSAGE },
                textB = textB.get().ifBlank { FALLBACK_MESSAGE },
                thinkingA = thinkingA.get().ifBlank { null },
                thinkingB = thinkingB.get().ifBlank { null },
                toolActivityA = toolActivityA.get().takeIf { it.steps.isNotEmpty() },
                toolActivityB = toolActivityB.get().takeIf { it.steps.isNotEmpty() }
            )
        } catch (e: Exception) {
            DiagnosticsLogger.log("Dual stream request failed", e)
            DualResponseResult.Failure(UserFacingErrorFormatter.placeholder(e))
        }
    }

    sealed class DualResponseResult {
        data class Success(
            val textA: String,
            val textB: String,
            val thinkingA: String?,
            val thinkingB: String?,
            val toolActivityA: ToolActivityPayload? = null,
            val toolActivityB: ToolActivityPayload? = null
        ) : DualResponseResult()

        data class Failure(val message: String) : DualResponseResult()
    }

    companion object {
        private const val FALLBACK_MESSAGE = "応答の取得に失敗しました。しばらくしてから再試行してください。"
        private const val PARTIAL_EMIT_INTERVAL_MS = 60L
    }
}

data class DualPartialProgress(
    val textA: String,
    val textB: String,
    val thinkingA: String?,
    val thinkingB: String?,
    val toolActivityA: ToolActivityPayload? = null,
    val toolActivityB: ToolActivityPayload? = null
)
