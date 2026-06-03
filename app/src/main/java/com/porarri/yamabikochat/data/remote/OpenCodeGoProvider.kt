package com.porarri.yamabikochat.data.remote

import okhttp3.ResponseBody
import retrofit2.Response
import java.security.MessageDigest

class OpenCodeGoProvider(
    private val openAiProvider: OpenAiProvider,
    private val anthropicCompatibleProvider: AnthropicCompatibleProvider
) : ApiProvider {
    override val baseUrl: String = ProviderCatalog.defaultOpenCodeGoBaseUrl
    override val providerType: ProviderType = ProviderType.OPENCODE_GO

    override suspend fun generateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest
    ): Response<GenerateContentResponse> {
        val route = requireSupportedRoute(model)
        return when (route.endpointKind) {
            OpenCodeGoEndpointKind.CHAT_COMPLETIONS -> openAiProvider.generateContent(
                apiKey = apiKey,
                model = route.id,
                request = request,
                baseUrl = baseUrl,
                promptCacheKeyOverride = promptCacheKeyFor(request, route)
            )
            OpenCodeGoEndpointKind.MESSAGES -> anthropicCompatibleProvider.generateContent(
                apiKey = apiKey,
                model = route.id,
                request = request,
                baseUrl = baseUrl,
                providerLabel = "OpenCodeGoProvider"
            )
        }
    }

    override suspend fun streamGenerateContent(
        apiKey: String,
        model: String,
        request: GenerateContentRequest
    ): Response<ResponseBody> {
        val route = requireSupportedRoute(model)
        return when (route.endpointKind) {
            OpenCodeGoEndpointKind.CHAT_COMPLETIONS -> openAiProvider.streamGenerateContent(
                apiKey = apiKey,
                model = route.id,
                request = request,
                baseUrl = baseUrl,
                promptCacheKeyOverride = promptCacheKeyFor(request, route)
            )
            OpenCodeGoEndpointKind.MESSAGES -> anthropicCompatibleProvider.streamGenerateContent(
                apiKey = apiKey,
                model = route.id,
                request = request,
                baseUrl = baseUrl,
                providerLabel = "OpenCodeGoProvider"
            )
        }
    }

    private fun requireSupportedRoute(model: String): OpenCodeGoModel =
        OpenCodeGoModelCatalog.modelFor(model)
            ?: throw IllegalArgumentException("Unsupported OpenCode Go model: $model")

    private fun promptCacheKeyFor(request: GenerateContentRequest, route: OpenCodeGoModel): String {
        request.promptCacheKey?.trim()?.takeIf { it.isNotEmpty() }?.let { return it }
        val firstMessage = request.contents.firstOrNull()
        val firstText = firstMessage?.parts.orEmpty().mapNotNull { it.text }.joinToString("")
        val seed = listOf(
            route.id,
            request.system_instruction?.parts.orEmpty().mapNotNull { it.text }.joinToString("\n").trim(),
            firstMessage?.role.orEmpty(),
            firstText
        ).joinToString("\n")
        val digest = MessageDigest.getInstance("SHA-256")
            .digest(seed.toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(it.toInt() and 0xff) }
        return "opencode-go-${digest.take(48)}"
    }
}
