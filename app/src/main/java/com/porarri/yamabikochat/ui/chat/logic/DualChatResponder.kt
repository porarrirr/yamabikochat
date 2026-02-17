package com.porarri.yamabikochat.ui.chat.logic

import com.porarri.yamabikochat.data.ChatRepository
import com.porarri.yamabikochat.data.remote.GenerateContentRequest
import com.porarri.yamabikochat.data.remote.extractTokenUsageSnapshot
import com.porarri.yamabikochat.BuildConfig
import com.porarri.yamabikochat.utils.DiagnosticsLogger

/**
 * Handles dual model completion requests so the ChatViewModel can stay lightweight.
 */
class DualChatResponder(
    private val repository: ChatRepository
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
