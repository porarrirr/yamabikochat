package com.porarri.yamabikochat.data.remote

import okhttp3.ResponseBody
import retrofit2.Response

/**
 * 異なるAIプロバイダー（Gemini、OpenRouter）を統一的に扱うためのインターフェース
 */
interface ApiProvider {
    suspend fun generateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest
    ): Response<GenerateContentResponse>

    suspend fun streamGenerateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest
    ): Response<ResponseBody>

    val baseUrl: String
    val providerType: ProviderType
}

enum class ProviderType {
    GEMINI,
    OPENROUTER,
    OPENAI,
    OPENCODE_GO,
    ALIBABA_CODING_PLAN,
    ZAI
}
