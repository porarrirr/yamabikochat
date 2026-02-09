package com.porarri.yamabikochat.data.remote

import okhttp3.ResponseBody
import retrofit2.Response

class GeminiProvider(
    private val geminiApiService: GeminiApiService
) : ApiProvider {
    
    override val baseUrl: String = "https://generativelanguage.googleapis.com"
    override val providerType: ProviderType = ProviderType.GEMINI
    
    override suspend fun generateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest
    ): Response<GenerateContentResponse> {
        return geminiApiService.generateContent(model, apiKey, request)
    }
    
    override suspend fun streamGenerateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest
    ): Response<ResponseBody> {
        return geminiApiService.streamGenerateContent(model, apiKey, request = request)
    }
}