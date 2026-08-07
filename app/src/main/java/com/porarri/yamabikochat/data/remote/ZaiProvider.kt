package com.porarri.yamabikochat.data.remote

import android.util.Log
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody
import okhttp3.ResponseBody.Companion.toResponseBody
import retrofit2.Response

class ZaiProvider(
    private val zaiApiService: ZaiApiService
) : ApiProvider {

    override val baseUrl: String = "https://api.z.ai/api/coding/paas/v4"
    override val providerType: ProviderType = ProviderType.ZAI

    private fun resolveThinking(request: GenerateContentRequest): ZaiThinking? {
        val config = request.generationConfig?.thinkingConfig ?: return null

        val enabledFlag = config.enabled
        if (enabledFlag != null) {
            return ZaiThinking(type = if (enabledFlag) "enabled" else "disabled")
        }

        val budgetFlag = config.thinkingBudget?.let { it > 0 }
        if (budgetFlag != null) {
            return ZaiThinking(type = if (budgetFlag) "enabled" else "disabled")
        }

        val levelFlag = config.thinkingLevel?.takeIf { it.isNotBlank() }
        if (levelFlag != null) {
            return ZaiThinking(type = "enabled")
        }

        return null
    }

    override suspend fun generateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest
    ): Response<GenerateContentResponse> = withContext(Dispatchers.IO) {
        try {
            val cleanedApiKey = apiKey.trim()
            if (cleanedApiKey.isEmpty()) {
                return@withContext Response.error(401, "API Key is empty".toResponseBody())
            }
            if (!ZaiCodingPlanModelCatalog.isSupported(model)) {
                return@withContext Response.error(
                    400,
                    "Unsupported Z.ai Coding Plan model: $model".toResponseBody()
                )
            }

            // Convert Gemini request into OpenAI-compatible payload
            val converted = RequestConverter.geminiToOpenRouter(request, model, null)
            val thinking = resolveThinking(request)

            val resp = when (converted) {
                is OpenRouterRequest -> zaiApiService.createChatCompletion(
                    authorization = "Bearer $cleanedApiKey",
                    request = converted.copy(provider = null, reasoning = null, thinking = thinking)
                )
                is OpenRouterMultiModalRequest -> zaiApiService.createChatCompletionMultiModal(
                    authorization = "Bearer $cleanedApiKey",
                    request = converted.copy(provider = null, reasoning = null, thinking = thinking)
                )
                else -> throw IllegalArgumentException("Unsupported request type for Z.ai")
            }

            if (resp.isSuccessful && resp.body() != null) {
                val body = resp.body()!!
                val gemini = RequestConverter.openRouterToGemini(body)
                Response.success(gemini)
            } else {
                val errorBodyString = resp.errorBody()?.string() ?: ""
                val recreated = errorBodyString.toResponseBody("application/json".toMediaType())
                Response.error(resp.code(), recreated)
            }
        } catch (e: Exception) {
            DiagnosticsLogger.log("ZaiProvider generateContent failed model=$model", e)
            Log.e("ZaiProvider", "generateContent failed: ${e.message}", e)     
            Response.error(500, (e.message ?: "Unknown error").toResponseBody())
        }
    }

    override suspend fun streamGenerateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest
    ): Response<ResponseBody> = withContext(Dispatchers.IO) {
        try {
            val cleanedApiKey = apiKey.trim()
            if (cleanedApiKey.isEmpty()) {
                return@withContext Response.error(401, "API Key is empty".toResponseBody())
            }
            if (!ZaiCodingPlanModelCatalog.isSupported(model)) {
                return@withContext Response.error(
                    400,
                    "Unsupported Z.ai Coding Plan model: $model".toResponseBody()
                )
            }

            val converted = RequestConverter.geminiToOpenRouter(request, model, null)
            val thinking = resolveThinking(request)
            when (converted) {
                is OpenRouterRequest -> zaiApiService.createChatCompletionStream(
                    authorization = "Bearer $cleanedApiKey",
                    request = converted.copy(stream = true, provider = null, reasoning = null, thinking = thinking)
                )
                is OpenRouterMultiModalRequest -> zaiApiService.createChatCompletionMultiModalStream(
                    authorization = "Bearer $cleanedApiKey",
                    request = converted.copy(stream = true, provider = null, reasoning = null, thinking = thinking)
                )
                else -> throw IllegalArgumentException("Unsupported request type for Z.ai")
            }
        } catch (e: Exception) {
            DiagnosticsLogger.log("ZaiProvider streamGenerateContent failed model=$model", e)
            Response.error(500, (e.message ?: "Unknown error").toResponseBody())
        }
    }
}
