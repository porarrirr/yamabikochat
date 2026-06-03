package com.porarri.yamabikochat.data.remote

import okhttp3.ResponseBody
import retrofit2.Response

class AlibabaCodingPlanProvider(
    private val anthropicCompatibleProvider: AnthropicCompatibleProvider
) : ApiProvider {
    override val baseUrl: String = ProviderCatalog.defaultAlibabaCodingPlanBaseUrl
    override val providerType: ProviderType = ProviderType.ALIBABA_CODING_PLAN

    override suspend fun generateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest
    ): Response<GenerateContentResponse> =
        generateContent(apiKey, model, request, mcpAuthorizationToken = null)

    suspend fun generateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest,
        mcpAuthorizationToken: String?
    ): Response<GenerateContentResponse> =
        anthropicCompatibleProvider.generateContent(
            apiKey = apiKey,
            model = model.trim().ifBlank { AlibabaCodingPlanModelCatalog.defaultModel },
            request = request,
            baseUrl = baseUrl,
            providerLabel = "AlibabaCodingPlanProvider",
            mcpAuthorizationToken = mcpAuthorizationToken
        )

    override suspend fun streamGenerateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest
    ): Response<ResponseBody> =
        streamGenerateContent(apiKey, model, request, mcpAuthorizationToken = null)

    suspend fun streamGenerateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest,
        mcpAuthorizationToken: String?
    ): Response<ResponseBody> =
        anthropicCompatibleProvider.streamGenerateContent(
            apiKey = apiKey,
            model = model.trim().ifBlank { AlibabaCodingPlanModelCatalog.defaultModel },
            request = request,
            baseUrl = baseUrl,
            providerLabel = "AlibabaCodingPlanProvider",
            mcpAuthorizationToken = mcpAuthorizationToken
        )
}
