package com.porarri.yamabikochat.ui.chat.logic

import com.porarri.yamabikochat.BuildConfig
import com.porarri.yamabikochat.data.ChatRepository
import com.porarri.yamabikochat.data.remote.GenerateContentRequest
import com.porarri.yamabikochat.data.remote.extractTokenUsageSnapshot
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.json.Json
import okhttp3.ResponseBody
import retrofit2.Response
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference

/**
 * Handles dual model completion requests so the ChatViewModel can stay lightweight.
 */
class DualChatResponder(
    private val repository: ChatRepository,
    private val json: Json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }
) {
    suspend fun generateResponses(
        conversationId: Long,
        modelA: String,
        modelB: String,
        providerA: String,
        providerB: String,
        requestA: GenerateContentRequest,
        requestB: GenerateContentRequest
    ): DualResponseResult {
        return try {
            val (responseA, responseB) = repository.generateDualContent(
                modelA,
                modelB,
                providerA,
                providerB,
                requestA,
                requestB
            )
            responseA.body()?.extractTokenUsageSnapshot()?.let { usage ->
                runCatching {
                    repository.recordTokenUsage(
                        provider = providerA,
                        model = modelA,
                        usage = usage,
                        conversationId = conversationId,
                        requestType = "dual"
                    )
                }
            }
            responseB.body()?.extractTokenUsageSnapshot()?.let { usage ->
                runCatching {
                    repository.recordTokenUsage(
                        provider = providerB,
                        model = modelB,
                        usage = usage,
                        conversationId = conversationId,
                        requestType = "dual"
                    )
                }
            }

            val errorBodyA = if (!responseA.isSuccessful && (BuildConfig.DEBUG || BuildConfig.DIAGNOSTIC)) {
                responseA.errorBody()?.string()?.take(2048)
            } else {
                responseA.errorBody()?.string()?.take(256)
            }
            val parsedA = parseResponse(
                successful = responseA.isSuccessful,
                provider = providerA,
                model = modelA,
                code = responseA.code(),
                parts = responseA.body()?.candidates?.firstOrNull()?.content?.parts?.mapNotNull { part ->
                    part.text?.let { text -> PartPayload(text, part.thought == true) }
                } ?: emptyList(),
                errorBody = errorBodyA
            )

            val errorBodyB = if (!responseB.isSuccessful && (BuildConfig.DEBUG || BuildConfig.DIAGNOSTIC)) {
                responseB.errorBody()?.string()?.take(2048)
            } else {
                responseB.errorBody()?.string()?.take(256)
            }
            val parsedB = parseResponse(
                successful = responseB.isSuccessful,
                provider = providerB,
                model = modelB,
                code = responseB.code(),
                parts = responseB.body()?.candidates?.firstOrNull()?.content?.parts?.mapNotNull { part ->
                    part.text?.let { text -> PartPayload(text, part.thought == true) }
                } ?: emptyList(),
                errorBody = errorBodyB
            )

            DualResponseResult.Success(
                textA = parsedA.visibleText,
                textB = parsedB.visibleText,
                thinkingA = parsedA.thinkingText.ifBlank { null },
                thinkingB = parsedB.thinkingText.ifBlank { null }
            )
        } catch (e: Exception) {
            DiagnosticsLogger.log("Dual content request failed providerA=${providerA.uppercase()} providerB=${providerB.uppercase()}", e)
            android.util.Log.e("DualChatResponder", "Dual content request failed", e)
            DualResponseResult.Failure(networkFailureMessage(providerA, e))
        }
    }

    suspend fun streamResponses(
        conversationId: Long,
        modelA: String,
        modelB: String,
        providerA: String,
        providerB: String,
        requestA: GenerateContentRequest,
        requestB: GenerateContentRequest,
        onPartial: suspend (textA: String, textB: String, thinkingA: String?, thinkingB: String?) -> Unit
    ): DualResponseResult = coroutineScope {
        try {
            val (responseA, responseB) = repository.streamDualContent(
                modelA,
                modelB,
                providerA,
                providerB,
                requestA,
                requestB
            )

            val textA = AtomicReference("")
            val textB = AtomicReference("")
            val thinkingA = AtomicReference("")
            val thinkingB = AtomicReference("")
            val lastEmitMs = AtomicLong(0L)
            val emitMutex = Mutex()

            suspend fun emitPartial(force: Boolean = false) {
                emitMutex.withLock {
                    val now = System.currentTimeMillis()
                    if (!force && now - lastEmitMs.get() < PARTIAL_EMIT_INTERVAL_MS) {
                        return@withLock
                    }
                    lastEmitMs.set(now)
                    onPartial(
                        textA.get(),
                        textB.get(),
                        thinkingA.get().ifBlank { null },
                        thinkingB.get().ifBlank { null }
                    )
                }
            }

            val jobA = async {
                consumeSide(
                    conversationId = conversationId,
                    side = "A",
                    response = responseA,
                    provider = providerA,
                    model = modelA,
                    textRef = textA,
                    thinkingRef = thinkingA,
                    onProgress = { emitPartial(force = false) }
                )
            }
            val jobB = async {
                consumeSide(
                    conversationId = conversationId,
                    side = "B",
                    response = responseB,
                    provider = providerB,
                    model = modelB,
                    textRef = textB,
                    thinkingRef = thinkingB,
                    onProgress = { emitPartial(force = false) }
                )
            }

            jobA.await()
            jobB.await()
            emitPartial(force = true)

            DualResponseResult.Success(
                textA = textA.get().ifBlank { FALLBACK_MESSAGE },
                textB = textB.get().ifBlank { FALLBACK_MESSAGE },
                thinkingA = thinkingA.get().ifBlank { null },
                thinkingB = thinkingB.get().ifBlank { null }
            )
        } catch (e: Exception) {
            DiagnosticsLogger.log(
                "Dual stream request failed providerA=${providerA.uppercase()} providerB=${providerB.uppercase()}",
                e
            )
            android.util.Log.e("DualChatResponder", "Dual stream request failed", e)
            DualResponseResult.Failure(networkFailureMessage(providerA, e))
        }
    }

    private suspend fun consumeSide(
        conversationId: Long,
        side: String,
        response: Response<ResponseBody>,
        provider: String,
        model: String,
        textRef: AtomicReference<String>,
        thinkingRef: AtomicReference<String>,
        onProgress: suspend () -> Unit
    ) {
        if (!response.isSuccessful) {
            val errorBody = if (BuildConfig.DEBUG || BuildConfig.DIAGNOSTIC) {
                response.errorBody()?.string()?.take(2048)
            } else {
                response.errorBody()?.string()?.take(256)
            }
            DiagnosticsLogger.log(
                "Dual stream call failed side=$side provider=${provider.uppercase()} model=$model code=${response.code()} body=${errorBody.orEmpty()}"
            )
            textRef.set(apiFailureMessage(provider, response.code()))
            onProgress()
            return
        }

        val body = response.body()
        if (body == null) {
            DiagnosticsLogger.log(
                "Dual stream returned empty body side=$side provider=${provider.uppercase()} model=$model"
            )
            textRef.set(FALLBACK_MESSAGE)
            onProgress()
            return
        }

        try {
            val result = StreamChunkConsumer.consumeStreamDetailed(
                body = body,
                provider = provider,
                model = model,
                json = json,
                onDelta = { text, thinking, _ ->
                    textRef.set(text)
                    thinkingRef.set(thinking)
                    onProgress()
                },
                onUsage = { usage ->
                    runCatching {
                        repository.recordTokenUsage(
                            provider = provider,
                            model = model,
                            usage = usage,
                            conversationId = conversationId,
                            requestType = "dual_stream"
                        )
                    }
                }
            )
            textRef.set(result.text)
            thinkingRef.set(result.thinking)
            if (!result.hasData && result.text.isBlank()) {
                textRef.set(FALLBACK_MESSAGE)
            }
        } catch (e: Exception) {
            DiagnosticsLogger.log(
                "Dual stream side failed side=$side provider=${provider.uppercase()} model=$model",
                e
            )
            textRef.set(networkFailureMessage(provider, e))
        }
    }

    private fun parseResponse(
        successful: Boolean,
        provider: String,
        model: String,
        code: Int,
        parts: List<PartPayload>,
        errorBody: String?
    ): ParsedPayload {
        if (!successful) {
            DiagnosticsLogger.log(
                "Dual content call failed provider=${provider.uppercase()} model=$model code=$code body=${errorBody.orEmpty()}"
            )
            android.util.Log.e("DualChatResponder", "Dual content call failed: code=$code")
            return ParsedPayload(apiFailureMessage(provider, code), "")
        }

        if (parts.isEmpty()) {
            DiagnosticsLogger.log("Dual content returned empty parts provider=${provider.uppercase()} model=$model")
            return ParsedPayload(FALLBACK_MESSAGE, "")
        }

        var text = ""
        var thinking = ""
        parts.forEach { payload ->
            if (payload.isThought) {
                thinking += payload.value
            } else {
                text += payload.value
            }
        }
        return ParsedPayload(text.ifBlank { FALLBACK_MESSAGE }, thinking)
    }

    sealed class DualResponseResult {
        data class Success(
            val textA: String,
            val textB: String,
            val thinkingA: String?,
            val thinkingB: String?
        ) : DualResponseResult()

        data class Failure(val message: String) : DualResponseResult()
    }

    private data class PartPayload(val value: String, val isThought: Boolean)

    private data class ParsedPayload(val visibleText: String, val thinkingText: String)

    companion object {
        private const val FALLBACK_MESSAGE = "応答の取得に失敗しました。しばらくしてから再試行してください。"
        private const val PARTIAL_EMIT_INTERVAL_MS = 100L
    }

    private fun apiFailureMessage(provider: String, code: Int): String {
        val p = provider.uppercase()
        return when (code) {
            401 -> "APIキーが未設定または無効です（$p）"
            403 -> "アクセスが拒否されました（$p）"
            404 -> "エンドポイント/モデルが見つかりません（$p）"
            408 -> "タイムアウトしました（$p）"
            429 -> "レート制限です。少し待って再試行してください（$p）"
            in 500..599 -> "サーバーエラーが発生しました（$p, code=$code）"
            else -> "APIエラーが発生しました（$p, code=$code）"
        }
    }

    private fun networkFailureMessage(provider: String, throwable: Throwable): String {
        val p = provider.uppercase()
        val kind = throwable::class.java.simpleName
        return "通信に失敗しました（$p, $kind）"
    }
}
