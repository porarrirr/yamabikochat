package com.porarri.yamabikochat.data.remote

import android.util.Log
import com.porarri.yamabikochat.utils.MiniMaxUtils
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody
import okhttp3.ResponseBody.Companion.toResponseBody
import retrofit2.Response

/**
 * OpenAI provider (and OpenAI-compatible) that uses dynamic base URLs.
 * It converts the app's unified request to the OpenAI Chat Completions format.
 */
class OpenAiProvider(
    private val makeService: (baseUrl: String) -> OpenAiApiService
) : ApiProvider {

    override val baseUrl: String = "https://api.openai.com/v1"
    override val providerType: ProviderType = ProviderType.OPENAI

    // Not used directly; OpenAI requires a dynamically selected base URL.
    override suspend fun generateContent(apiKey: String, model: String, request: GenerateContentRequest): Response<GenerateContentResponse> =
        Response.error(500, "Use generateContent(apiKey, model, request, baseUrl)".toResponseBody())

    // Not used directly; OpenAI requires a dynamically selected base URL.
    override suspend fun streamGenerateContent(apiKey: String, model: String, request: GenerateContentRequest): Response<ResponseBody> =
        Response.error(500, "Use streamGenerateContent(apiKey, model, request, baseUrl)".toResponseBody())

    suspend fun generateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest,
        baseUrl: String,
        promptCacheKeyOverride: String? = null,
        useApiKeyHeader: Boolean = false,
        useCloudflareGatewayHeader: Boolean = false,
        stripOpenAiProviderPrefix: Boolean = true,
        reasoningEffortOverride: String? = null
    ): Response<GenerateContentResponse> = withContext(Dispatchers.IO) {
        try {
            val cleanedKey = apiKey.trim()
            if (cleanedKey.isEmpty()) {
                return@withContext Response.error(401, "API Key is empty".toResponseBody())
            }

            val payload = RequestConverter.geminiToOpenRouter(request, model, null)
            val budget = request.generationConfig?.thinkingConfig?.thinkingBudget?.takeIf { it > 0 }
            val service = makeService(baseUrl)
            val reasoningSplit = MiniMaxUtils.isMiniMaxBaseUrl(baseUrl)
            val reasoning = if (preserveReasoning(baseUrl)) {
                when (payload) {
                    is OpenRouterRequest -> payload.reasoning
                    is OpenRouterMultiModalRequest -> payload.reasoning
                    else -> null
                }
            } else {
                null
            }

            val resp = when (payload) {
                is OpenRouterRequest -> service.createChatCompletion(
                    authorization = if (useApiKeyHeader || useCloudflareGatewayHeader) null else "Bearer $cleanedKey",
                    apiKey = cleanedKey.takeIf { useApiKeyHeader },
                    cloudflareAuthorization = "Bearer $cleanedKey".takeIf { useCloudflareGatewayHeader },
                    request = payload.copy(
                        model = normalizeOpenAiModel(payload.model, stripOpenAiProviderPrefix),
                        provider = null,
                        reasoning = reasoning,
                        reasoningEffort = reasoningEffortOverride,
                        cacheControl = null,
                        reasoningSplit = reasoningSplit.takeIf { it },
                        max_tokens = budget ?: payload.max_tokens,
                        promptCacheKey = promptCacheKeyOverride ?: promptCacheKeyForOfficialOpenAi(request, baseUrl)
                    )
                )
                is OpenRouterMultiModalRequest -> service.createChatCompletionMultiModal(
                    authorization = if (useApiKeyHeader || useCloudflareGatewayHeader) null else "Bearer $cleanedKey",
                    apiKey = cleanedKey.takeIf { useApiKeyHeader },
                    cloudflareAuthorization = "Bearer $cleanedKey".takeIf { useCloudflareGatewayHeader },
                    request = payload.copy(
                        model = normalizeOpenAiModel(payload.model, stripOpenAiProviderPrefix),
                        provider = null,
                        reasoning = reasoning,
                        reasoningEffort = reasoningEffortOverride,
                        cacheControl = null,
                        reasoningSplit = reasoningSplit.takeIf { it },
                        max_tokens = budget ?: payload.max_tokens,
                        promptCacheKey = promptCacheKeyOverride ?: promptCacheKeyForOfficialOpenAi(request, baseUrl)
                    )
                )
                else -> throw IllegalArgumentException("Unsupported request type")
            }

            if (resp.isSuccessful && resp.body() != null) {
                Response.success(RequestConverter.openRouterToGemini(resp.body()!!))
            } else {
                val body = resp.errorBody()?.string().orEmpty()
                Response.error(resp.code(), body.toResponseBody("application/json".toMediaType()))
            }
        } catch (e: Exception) {
            DiagnosticsLogger.log("OpenAiProvider generateContent failed model=$model baseUrl=$baseUrl", e)
            Log.e("OpenAiProvider", "generateContent failed: ${e.message}", e)  
            Response.error(500, (e.message ?: "Unknown error").toResponseBody())
        }
    }

    suspend fun streamGenerateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest,
        baseUrl: String,
        promptCacheKeyOverride: String? = null,
        useApiKeyHeader: Boolean = false,
        useCloudflareGatewayHeader: Boolean = false,
        stripOpenAiProviderPrefix: Boolean = true,
        reasoningEffortOverride: String? = null
    ): Response<ResponseBody> = withContext(Dispatchers.IO) {
        try {
            val cleanedKey = apiKey.trim()
            if (cleanedKey.isEmpty()) {
                return@withContext Response.error(401, "API Key is empty".toResponseBody())
            }
            val payload = RequestConverter.geminiToOpenRouter(request, model, null)
            val budget = request.generationConfig?.thinkingConfig?.thinkingBudget?.takeIf { it > 0 }
            val service = makeService(baseUrl)
            val reasoningSplit = MiniMaxUtils.isMiniMaxBaseUrl(baseUrl)
            val reasoning = if (preserveReasoning(baseUrl)) {
                when (payload) {
                    is OpenRouterRequest -> payload.reasoning
                    is OpenRouterMultiModalRequest -> payload.reasoning
                    else -> null
                }
            } else {
                null
            }

            when (payload) {
                is OpenRouterRequest -> service.createChatCompletionStream(
                    authorization = if (useApiKeyHeader || useCloudflareGatewayHeader) null else "Bearer $cleanedKey",
                    apiKey = cleanedKey.takeIf { useApiKeyHeader },
                    cloudflareAuthorization = "Bearer $cleanedKey".takeIf { useCloudflareGatewayHeader },
                    request = payload.copy(
                        model = normalizeOpenAiModel(payload.model, stripOpenAiProviderPrefix),
                        stream = true,
                        provider = null,
                        reasoning = reasoning,
                        reasoningEffort = reasoningEffortOverride,
                        cacheControl = null,
                        reasoningSplit = reasoningSplit.takeIf { it },
                        max_tokens = budget ?: payload.max_tokens,
                        promptCacheKey = promptCacheKeyOverride ?: promptCacheKeyForOfficialOpenAi(request, baseUrl)
                    )
                )
                is OpenRouterMultiModalRequest -> service.createChatCompletionMultiModalStream(
                    authorization = if (useApiKeyHeader || useCloudflareGatewayHeader) null else "Bearer $cleanedKey",
                    apiKey = cleanedKey.takeIf { useApiKeyHeader },
                    cloudflareAuthorization = "Bearer $cleanedKey".takeIf { useCloudflareGatewayHeader },
                    request = payload.copy(
                        model = normalizeOpenAiModel(payload.model, stripOpenAiProviderPrefix),
                        stream = true,
                        provider = null,
                        reasoning = reasoning,
                        reasoningEffort = reasoningEffortOverride,
                        cacheControl = null,
                        reasoningSplit = reasoningSplit.takeIf { it },
                        max_tokens = budget ?: payload.max_tokens,
                        promptCacheKey = promptCacheKeyOverride ?: promptCacheKeyForOfficialOpenAi(request, baseUrl)
                    )
                )
                else -> throw IllegalArgumentException("Unsupported request type")
            }
        } catch (e: Exception) {
            DiagnosticsLogger.log("OpenAiProvider streamGenerateContent failed model=$model baseUrl=$baseUrl", e)
            Response.error(500, (e.message ?: "Unknown error").toResponseBody())
        }
    }

    internal fun normalizeOpenAiModel(model: String, stripProviderPrefix: Boolean): String {
        val trimmed = model.trim()
        return if (stripProviderPrefix) trimmed.removePrefix("openai/") else trimmed
    }

    /**
     * SuperGrok (xAI) accepts OpenRouter-style `reasoning` (effort). Official OpenAI and most
     * OpenAI-compatible endpoints do not — keep stripping there.
     */
    private fun preserveReasoning(baseUrl: String): Boolean {
        val host = baseUrl.lowercase()
        return host.contains("api.x.ai") || host.contains("x.ai/")
    }

    private fun promptCacheKeyForOfficialOpenAi(
        request: GenerateContentRequest,
        baseUrl: String
    ): String? {
        if (!isOfficialOpenAiBaseUrl(baseUrl)) return null
        return request.promptCacheKey?.trim()?.takeIf { it.isNotBlank() }
    }

    private fun isOfficialOpenAiBaseUrl(baseUrl: String): Boolean {
        val normalized = baseUrl.trim().lowercase().trimEnd('/')
        return normalized == "https://api.openai.com/v1"
    }
}
