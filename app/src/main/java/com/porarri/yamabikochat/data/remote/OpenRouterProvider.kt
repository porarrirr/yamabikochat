package com.porarri.yamabikochat.data.remote

import android.util.Log
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.Json
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody
import okhttp3.ResponseBody.Companion.toResponseBody
import retrofit2.Response

class OpenRouterProvider(
    private val openRouterApiService: OpenRouterApiService
) : ApiProvider {
    
    override val baseUrl: String = "https://openrouter.ai/api"
    override val providerType: ProviderType = ProviderType.OPENROUTER
    
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }
    
    override suspend fun generateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest
    ): Response<GenerateContentResponse> = withContext(Dispatchers.IO) {
        return@withContext generateContent(apiKey, model, request, null)
    }
    
    suspend fun generateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest,
        providerPreferences: ProviderPreferences?
    ): Response<GenerateContentResponse> = withContext(Dispatchers.IO) {
        try {
            // APIキーの検証
            val cleanedApiKey = apiKey.trim()
            if (cleanedApiKey.isEmpty()) {
                Log.e("OpenRouterProvider", "API Key is empty")
                return@withContext Response.error(401, "API Key is empty".toResponseBody())
            }
            
            Log.d("OpenRouterProvider", "Using model: $model")
            
            // GeminiリクエストをOpenRouterリクエストに変換
            val convertedRequest = RequestConverter.geminiToOpenRouter(request, model, providerPreferences)
            Log.d("OpenRouterProvider", "Converted request type: ${convertedRequest::class.simpleName}")
            
            // OpenRouter APIを呼び出し（型によって分岐）
            val openRouterResponse = when (convertedRequest) {
                is OpenRouterRequest -> {
                    Log.d("OpenRouterProvider", "Making simple text request")
                    openRouterApiService.createChatCompletion(
                        authorization = "Bearer $cleanedApiKey",
                        request = convertedRequest
                    )
                }
                is OpenRouterMultiModalRequest -> {
                    Log.d("OpenRouterProvider", "Making multimodal request")
                    openRouterApiService.createChatCompletionMultiModal(
                        authorization = "Bearer $cleanedApiKey",
                        request = convertedRequest
                    )
                }
                else -> throw IllegalArgumentException("Unknown request type: ${convertedRequest::class}")
            }
            
            // レスポンスを変換して返却
            if (openRouterResponse.isSuccessful && openRouterResponse.body() != null) {
                Log.d("OpenRouterProvider", "Request successful")
                val geminiResponse = RequestConverter.openRouterToGemini(openRouterResponse.body()!!)
                Response.success(geminiResponse)
            } else {
                val errorBodyString = openRouterResponse.errorBody()?.string() ?: ""
                Log.e(
                    "OpenRouterProvider",
                    "Request failed with code: ${openRouterResponse.code()} (body length=${errorBodyString.length})"
                )
                val recreatedErrorBody = errorBodyString.toResponseBody("application/json".toMediaType())
                Response.error(openRouterResponse.code(), recreatedErrorBody)
            }
        } catch (e: Exception) {
            DiagnosticsLogger.log("OpenRouterProvider generateContent failed model=$model", e)
            Log.e("OpenRouterProvider", "Exception occurred in generateContent: ${e.message}", e)
            Response.error(500, (e.message ?: "Unknown error").toResponseBody())
        }
    }
    
    override suspend fun streamGenerateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest
    ): Response<ResponseBody> = withContext(Dispatchers.IO) {
        return@withContext streamGenerateContent(apiKey, model, request, null)
    }
    
    suspend fun streamGenerateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest,
        providerPreferences: ProviderPreferences?
    ): Response<ResponseBody> = withContext(Dispatchers.IO) {
        try {
            Log.d("OpenRouterProvider", "Stream - Using model: $model")

            val cleanedApiKey = apiKey.trim()
            if (cleanedApiKey.isEmpty()) {
                Log.e("OpenRouterProvider", "API Key is empty")
                return@withContext Response.error(401, "API Key is empty".toResponseBody())
            }

            // GeminiリクエストをOpenRouterリクエストに変換
            val convertedRequest = RequestConverter.geminiToOpenRouter(request, model, providerPreferences)

            // OpenRouter APIでストリーミング呼び出し（型によって分岐）
            when (convertedRequest) {
                is OpenRouterRequest -> openRouterApiService.createChatCompletionStream(
                    authorization = "Bearer $cleanedApiKey",
                    request = convertedRequest.copy(stream = true)
                )
                is OpenRouterMultiModalRequest -> openRouterApiService.createChatCompletionMultiModalStream(
                    authorization = "Bearer $cleanedApiKey",
                    request = convertedRequest.copy(stream = true)
                )
                else -> throw IllegalArgumentException("Unknown request type")
            }
        } catch (e: Exception) {
            DiagnosticsLogger.log("OpenRouterProvider streamGenerateContent failed model=$model", e)
            Response.error(500, (e.message ?: "Unknown error").toResponseBody())
        }
    }
}
