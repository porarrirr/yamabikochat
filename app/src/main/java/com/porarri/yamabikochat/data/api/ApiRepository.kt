package com.porarri.yamabikochat.data.api

import android.util.Log
import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.data.local.Settings.ReasoningContext
import com.porarri.yamabikochat.data.local.SettingsManager
import com.porarri.yamabikochat.data.auth.CodexAuthRepository
import com.porarri.yamabikochat.data.auth.SuperGrokAuthRepository
import com.porarri.yamabikochat.data.model.ModelRepository
import com.porarri.yamabikochat.data.remote.ApiProvider
import com.porarri.yamabikochat.data.remote.Content
import com.porarri.yamabikochat.data.remote.GenerateContentRequest
import com.porarri.yamabikochat.data.remote.GenerateContentResponse
import com.porarri.yamabikochat.data.remote.GenerationConfig
import com.porarri.yamabikochat.data.remote.GeminiProvider
import com.porarri.yamabikochat.data.remote.OpenRouterProvider
import com.porarri.yamabikochat.data.remote.OpenAiProvider
import com.porarri.yamabikochat.data.remote.OpenCodeGoProvider
import com.porarri.yamabikochat.data.remote.AlibabaCodingPlanProvider
import com.porarri.yamabikochat.data.remote.AnthropicCompatibleProvider
import com.porarri.yamabikochat.data.remote.CodexResponsesProvider
import com.porarri.yamabikochat.data.remote.ZaiProvider
import com.porarri.yamabikochat.data.remote.Part
import com.porarri.yamabikochat.data.remote.ProviderCatalog
import com.porarri.yamabikochat.data.remote.ProviderPreferences
import com.porarri.yamabikochat.data.remote.ThinkingConfig
import com.porarri.yamabikochat.utils.MiniMaxUtils
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import com.porarri.yamabikochat.utils.ToolingUtils
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.ResponseBody
import okhttp3.ResponseBody.Companion.toResponseBody
import kotlinx.serialization.json.Json
import com.porarri.yamabikochat.data.modelsdev.CatalogProvider
import com.porarri.yamabikochat.data.modelsdev.ModelsDevCatalogRepository
import com.porarri.yamabikochat.data.modelsdev.ModelsDevProviderAdapterRegistry
import com.porarri.yamabikochat.data.modelsdev.ProviderAdapterKind
import com.porarri.yamabikochat.data.modelsdev.ProviderReference

class ApiRepository(
    private val geminiProvider: GeminiProvider,
    private val openRouterProvider: OpenRouterProvider,
    private val openAiProvider: OpenAiProvider,
    private val openCodeGoProvider: OpenCodeGoProvider,
    private val alibabaCodingPlanProvider: AlibabaCodingPlanProvider,
    private val anthropicCompatibleProvider: AnthropicCompatibleProvider,
    private val codexResponsesProvider: CodexResponsesProvider,
    private val zaiProvider: ZaiProvider,
    private val settingsManager: SettingsManager,
    private val codexAuthRepository: CodexAuthRepository,
    private val superGrokAuthRepository: SuperGrokAuthRepository,
    private val modelRepository: ModelRepository,
    private val modelsDevCatalogRepository: ModelsDevCatalogRepository,
    private val settingsProvider: suspend () -> Settings?
) {
    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
    }

    private data class ApiContext(
        val providerId: String,
        val apiProvider: ApiProvider,
        val apiKey: String,
        val settings: Settings?,
        val baseUrlOverride: String? = null,
        val accountId: String? = null,
        val modelsDevProvider: CatalogProvider? = null
    )

    private sealed interface ApiContextResult {
        data class Success(val context: ApiContext) : ApiContextResult
        data class MissingApiKey(val providerId: String) : ApiContextResult
    }

    private enum class TokenKind { ApiKey, AccessToken }

    private sealed interface ApiKeyResult {
        data class Success(
            val apiKey: String,
            val tokenKind: TokenKind = TokenKind.ApiKey,
            val accountId: String? = null
        ) : ApiKeyResult
        data class Missing(val providerId: String) : ApiKeyResult
    }

    private val missingKeyMediaType = "text/plain".toMediaType()
    private val codexChatGptBaseUrl = "https://chatgpt.com/backend-api/codex"
    private val superGrokBaseUrl = ProviderCatalog.defaultSuperGrokBaseUrl

    private fun missingKeyMessage(providerId: String) =
        "API key for $providerId provider is not configured."

    private fun missingKeyResponse(providerId: String): retrofit2.Response<GenerateContentResponse> =
        retrofit2.Response.error(401, missingKeyMessage(providerId).toResponseBody(missingKeyMediaType))

    private fun missingKeyStreamResponse(providerId: String): retrofit2.Response<ResponseBody> =
        retrofit2.Response.error(401, missingKeyMessage(providerId).toResponseBody(missingKeyMediaType))

    private suspend fun resolveApiContext(providerOverride: String? = null): ApiContextResult {
        val settings = settingsProvider()
        val rawProvider = providerOverride
            ?: settings?.apiProvider
            ?: "GEMINI"
        val dynamicReference = ProviderReference(rawProvider)
        val dynamicProvider = modelsDevCatalogRepository.providerOrLoad(dynamicReference)
        if (dynamicReference.isModelsDev && dynamicProvider == null) {
            return ApiContextResult.MissingApiKey(dynamicReference.persistedId)
        }
        val knownProviderIds = ProviderCatalog.options.map { it.key }.toSet() + setOf("GEMINI_AUTH", "QWEN_CODE")
        if (!dynamicReference.isModelsDev && rawProvider.uppercase() !in knownProviderIds) {
            return ApiContextResult.MissingApiKey("Unsupported provider: $rawProvider")
        }
        val resolvedProvider = if (dynamicReference.isModelsDev) dynamicReference.persistedId else rawProvider.uppercase()

        val apiProvider = when (resolvedProvider) {
            "OPENROUTER" -> openRouterProvider
            "OPENCODE_GO" -> openCodeGoProvider
            "ALIBABA_CODING_PLAN" -> alibabaCodingPlanProvider
            "OPENAI", "OPENAI_COMPAT", "MINIMAX", "CLINEPASS", "SUPERGROK" -> openAiProvider
            "CODEX_AUTH" -> codexResponsesProvider
            "ZAI" -> zaiProvider
            else -> if (dynamicProvider != null) openAiProvider else geminiProvider
        }

        val keyResult = when (resolvedProvider) {
            "CODEX_AUTH" -> resolveCodexAuthToken()
            "SUPERGROK" -> resolveSuperGrokAuthToken()
            else -> resolveApiKey(
                resolvedProvider,
                when (resolvedProvider) {
                    "OPENROUTER" -> settingsManager.getApiKey("OPENROUTER")
                    "OPENCODE_GO" -> settingsManager.getApiKey("OPENCODE_GO")
                    "ALIBABA_CODING_PLAN" -> settingsManager.getApiKey("ALIBABA_CODING_PLAN")
                    "OPENAI" -> settingsManager.getApiKey("OPENAI")
                    "MINIMAX" -> settingsManager.getApiKey("MINIMAX")
                    "CLINEPASS" -> settingsManager.getApiKey("CLINEPASS")
                    "OPENAI_COMPAT" -> settingsManager.getOpenAiCompatApiKey(settings?.selectedOpenAiCompatPreset)
                    "ZAI" -> settingsManager.getApiKey("ZAI")
                    else -> if (dynamicProvider != null) primaryModelsDevCredential(dynamicProvider) else settingsManager.getApiKey("GEMINI")
                }
            )
        }

        return when (keyResult) {
            is ApiKeyResult.Success -> {
                val tokenLabel = when {
                    resolvedProvider == "CODEX_AUTH" && keyResult.tokenKind == TokenKind.AccessToken -> "Access Token"
                    resolvedProvider == "SUPERGROK" -> "Access Token"
                    else -> "API Key"
                }
                Log.d("ApiRepository", "Using $resolvedProvider $tokenLabel")
                val baseUrlOverride = when (resolvedProvider) {
                    "CODEX_AUTH" -> codexAuthBaseUrl(keyResult.tokenKind, settings)
                    "SUPERGROK" -> superGrokBaseUrl
                    else -> null
                }
                if (resolvedProvider == "CODEX_AUTH") {
                    val rawAccountId = keyResult.accountId?.trim().orEmpty()
                    val redactedAccountId = when {
                        rawAccountId.isBlank() -> "-"
                        rawAccountId.length <= 10 -> rawAccountId
                        else -> rawAccountId.take(6) + "…" + rawAccountId.takeLast(4)
                    }
                    DiagnosticsLogger.log(
                        "CODEX_AUTH using tokenKind=${keyResult.tokenKind} baseUrl=${baseUrlOverride ?: codexResponsesProvider.baseUrl} accountId=$redactedAccountId"
                    )
                }
                ApiContextResult.Success(
                    ApiContext(
                        providerId = resolvedProvider,
                        apiProvider = apiProvider,
                        apiKey = keyResult.apiKey,
                        settings = settings,
                        baseUrlOverride = baseUrlOverride,
                        accountId = keyResult.accountId,
                        modelsDevProvider = dynamicProvider
                    )
                )
            }
            is ApiKeyResult.Missing -> ApiContextResult.MissingApiKey(keyResult.providerId)
        }
    }

    private fun primaryModelsDevCredential(provider: CatalogProvider): String? {
        val preferred = provider.env.firstOrNull { name ->
            listOf("API_KEY", "TOKEN", "SECRET", "BEARER").any { name.contains(it) }
        } ?: provider.env.firstOrNull()
        return preferred?.let { settingsManager.getModelsDevField(provider.id, it) }
    }

    private fun modelsDevBaseUrl(provider: CatalogProvider): String? {
        val catalogUrl = provider.api?.trim()?.takeIf { it.isNotEmpty() && !it.contains("${'$'}{") }
        val azureResource = settingsManager.getModelsDevField(provider.id, provider.env.firstOrNull { it.contains("RESOURCE_NAME") }.orEmpty())
            ?.trim()?.takeIf { it.isNotEmpty() }
        val cloudflareAccount = settingsManager.getModelsDevField(provider.id, "CLOUDFLARE_ACCOUNT_ID")?.trim()?.takeIf { it.isNotEmpty() }
        val cloudflareGateway = settingsManager.getModelsDevField(provider.id, "CLOUDFLARE_GATEWAY_ID")?.trim()?.takeIf { it.isNotEmpty() }
        val knownNativeUrl = when (provider.id) {
            "openai" -> "https://api.openai.com/v1/"
            "anthropic" -> "https://api.anthropic.com/v1/"
            "xai" -> "https://api.x.ai/v1/"
            "groq" -> "https://api.groq.com/openai/v1/"
            "mistral" -> "https://api.mistral.ai/v1/"
            "togetherai" -> "https://api.together.xyz/v1/"
            "cerebras" -> "https://api.cerebras.ai/v1/"
            "deepinfra" -> "https://api.deepinfra.com/v1/openai/"
            "perplexity" -> "https://api.perplexity.ai/"
            "cohere" -> "https://api.cohere.ai/compatibility/v1/"
            "vercel" -> "https://ai-gateway.vercel.sh/v1/"
            "v0" -> "https://api.v0.dev/v1/"
            "venice" -> "https://api.venice.ai/api/v1/"
            "aihubmix" -> "https://aihubmix.com/v1/"
            "merge-gateway" -> "https://api-gateway.merge.dev/v1/ai-sdk/"
            "azure" -> azureResource?.let { "https://$it.openai.azure.com/openai/v1/" }
            "azure-cognitive-services" -> azureResource?.let { "https://$it.services.ai.azure.com/openai/v1/" }
            "cloudflare-ai-gateway" -> if (cloudflareAccount != null && cloudflareGateway != null) {
                "https://gateway.ai.cloudflare.com/v1/$cloudflareAccount/$cloudflareGateway/compat/"
            } else null
            else -> null
        }
        val resolved = catalogUrl ?: knownNativeUrl
            ?: settingsManager.getModelsDevField(provider.id, "YAMABIKO_BASE_URL")?.trim()?.takeIf { it.isNotEmpty() }
        return resolved?.removeSuffix("/chat/completions")
    }

    private fun unsupportedModelsDevResponse(provider: CatalogProvider, detail: String? = null): retrofit2.Response<GenerateContentResponse> =
        retrofit2.Response.error(
            400,
            (detail ?: "${provider.name} requires the ${ModelsDevProviderAdapterRegistry.profile(provider).adapter} native adapter; no compatible request was sent.")
                .toResponseBody(missingKeyMediaType)
        )

    private fun unsupportedModelsDevStreamResponse(provider: CatalogProvider, detail: String? = null): retrofit2.Response<ResponseBody> =
        retrofit2.Response.error(
            400,
            (detail ?: "${provider.name} requires the ${ModelsDevProviderAdapterRegistry.profile(provider).adapter} native adapter; no compatible request was sent.")
                .toResponseBody(missingKeyMediaType)
        )

    private suspend fun generateModelsDev(
        provider: CatalogProvider,
        apiKey: String,
        model: String,
        request: GenerateContentRequest
    ): retrofit2.Response<GenerateContentResponse> {
        validateModelsDevRequest(provider, model, request)?.let { return unsupportedModelsDevResponse(provider, it) }
        val profile = ModelsDevProviderAdapterRegistry.profile(provider)
        val baseUrl = modelsDevBaseUrl(provider) ?: return retrofit2.Response.error(
            400, "A completed base URL is required for ${provider.name}.".toResponseBody(missingKeyMediaType)
        )
        return when (profile.adapter) {
            ProviderAdapterKind.OPEN_AI_COMPATIBLE,
            ProviderAdapterKind.OPEN_AI,
            ProviderAdapterKind.PROVIDER_SPECIFIC,
            ProviderAdapterKind.COHERE,
            ProviderAdapterKind.VERCEL_AI,
            ProviderAdapterKind.CLOUDFLARE_AI_GATEWAY,
            ProviderAdapterKind.AZURE_OPEN_AI,
            ProviderAdapterKind.UNVERIFIED_OPEN_AI_COMPATIBLE -> {
                if (!profile.isVerifiedMapping) DiagnosticsLogger.log("models.dev unverified OpenAI-compatible mode provider=${provider.id}")
                openAiProvider.generateContent(
                    apiKey, model, request, baseUrl,
                    useApiKeyHeader = profile.adapter == ProviderAdapterKind.AZURE_OPEN_AI,
                    useCloudflareGatewayHeader = profile.adapter == ProviderAdapterKind.CLOUDFLARE_AI_GATEWAY,
                    stripOpenAiProviderPrefix = false
                )
            }
            ProviderAdapterKind.ANTHROPIC -> anthropicCompatibleProvider.generateContent(
                apiKey, model, request, baseUrl, provider.name
            )
            else -> unsupportedModelsDevResponse(provider)
        }
    }

    private suspend fun streamModelsDev(
        provider: CatalogProvider,
        apiKey: String,
        model: String,
        request: GenerateContentRequest
    ): retrofit2.Response<ResponseBody> {
        validateModelsDevRequest(provider, model, request)?.let { return unsupportedModelsDevStreamResponse(provider, it) }
        val profile = ModelsDevProviderAdapterRegistry.profile(provider)
        val baseUrl = modelsDevBaseUrl(provider) ?: return retrofit2.Response.error(
            400, "A completed base URL is required for ${provider.name}.".toResponseBody(missingKeyMediaType)
        )
        return when (profile.adapter) {
            ProviderAdapterKind.OPEN_AI_COMPATIBLE,
            ProviderAdapterKind.OPEN_AI,
            ProviderAdapterKind.PROVIDER_SPECIFIC,
            ProviderAdapterKind.COHERE,
            ProviderAdapterKind.VERCEL_AI,
            ProviderAdapterKind.CLOUDFLARE_AI_GATEWAY,
            ProviderAdapterKind.AZURE_OPEN_AI,
            ProviderAdapterKind.UNVERIFIED_OPEN_AI_COMPATIBLE -> {
                if (!profile.isVerifiedMapping) DiagnosticsLogger.log("models.dev unverified OpenAI-compatible mode provider=${provider.id}")
                openAiProvider.streamGenerateContent(
                    apiKey, model, request, baseUrl,
                    useApiKeyHeader = profile.adapter == ProviderAdapterKind.AZURE_OPEN_AI,
                    useCloudflareGatewayHeader = profile.adapter == ProviderAdapterKind.CLOUDFLARE_AI_GATEWAY,
                    stripOpenAiProviderPrefix = false
                )
            }
            ProviderAdapterKind.ANTHROPIC -> anthropicCompatibleProvider.streamGenerateContent(
                apiKey, model, request, baseUrl, provider.name
            )
            else -> unsupportedModelsDevStreamResponse(provider)
        }
    }

    private fun validateModelsDevRequest(provider: CatalogProvider, modelId: String, request: GenerateContentRequest): String? {
        val model = provider.models.firstOrNull { it.id == modelId }
            ?: return "Model is unavailable in the current models.dev catalog: $modelId"
        if (!request.tools.isNullOrEmpty() && !model.toolCall) return "${model.name} does not support tool calls"
        if (request.contents.any { content -> content.parts.any { it.inlineData != null || it.fileData != null } } && !model.attachment) {
            return "${model.name} does not support attachments"
        }
        if (request.generationConfig?.thinkingConfig?.enabled == true && !model.reasoning) {
            return "${model.name} does not support reasoning"
        }
        return null
    }

    private suspend fun normalizedOpenRouterPreferences(settings: Settings?): ProviderPreferences? {
        val raw = settings?.createProviderPreferences() ?: return null
        val directory = modelRepository.getProvidersDirectory()
        return raw.copy(
            order = raw.order?.map { directory.slugForName(it) ?: it.lowercase() },
            only = raw.only?.map { directory.slugForName(it) ?: it.lowercase() },
            ignore = raw.ignore?.map { directory.slugForName(it) ?: it.lowercase() }
        )
    }

    private fun resolveApiKey(providerId: String, apiKey: String?): ApiKeyResult {
        val cleanedKey = apiKey?.trim()
        return if (cleanedKey.isNullOrEmpty()) {
            ApiKeyResult.Missing(providerId)
        } else {
            ApiKeyResult.Success(cleanedKey)
        }
    }

    private suspend fun resolveCodexAuthToken(): ApiKeyResult {
        val bearer = codexAuthRepository.getBearerToken()
        return if (bearer == null || bearer.token.isBlank()) {
            ApiKeyResult.Missing("CODEX_AUTH")
        } else {
            val kind = if (bearer.isApiKey) TokenKind.ApiKey else TokenKind.AccessToken
            ApiKeyResult.Success(bearer.token, kind, bearer.accountId)
        }
    }

    private suspend fun refreshCodexAuthToken(settings: Settings?): ApiKeyResult.Success? {
        codexAuthRepository.refreshIfNeeded(force = true)
        val bearer = codexAuthRepository.getBearerToken() ?: return null
        if (bearer.token.isBlank()) return null
        val kind = if (bearer.isApiKey) TokenKind.ApiKey else TokenKind.AccessToken
        return ApiKeyResult.Success(bearer.token, kind, bearer.accountId)
    }

    private suspend fun resolveSuperGrokAuthToken(): ApiKeyResult {
        val bearer = superGrokAuthRepository.getBearerToken()
        return if (bearer == null || bearer.token.isBlank()) {
            ApiKeyResult.Missing("SUPERGROK")
        } else {
            ApiKeyResult.Success(bearer.token, TokenKind.AccessToken)
        }
    }

    private suspend fun refreshSuperGrokAuthToken(): ApiKeyResult.Success? {
        superGrokAuthRepository.refreshIfNeeded(force = true)
        val bearer = superGrokAuthRepository.getBearerToken() ?: return null
        if (bearer.token.isBlank()) return null
        return ApiKeyResult.Success(bearer.token, TokenKind.AccessToken)
    }

    private fun codexAuthBaseUrl(tokenKind: TokenKind, settings: Settings?): String {
        return if (tokenKind == TokenKind.AccessToken) {
            codexChatGptBaseUrl
        } else {
            settings?.openAiBaseUrl?.takeIf { it.isNotBlank() } ?: "https://api.openai.com/v1/"
        }
    }

    private suspend fun <T> callCodexAuthWithRetry(
        initialToken: String,
        initialBaseUrl: String,
        initialAccountId: String?,
        settings: Settings?,
        call: suspend (String, String, String?) -> retrofit2.Response<T>
    ): retrofit2.Response<T> {
        val first = call(initialToken, initialBaseUrl, initialAccountId)
        if (first.code() != 401) return first

        val refreshed = refreshCodexAuthToken(settings) ?: return first
        val refreshedBaseUrl = codexAuthBaseUrl(refreshed.tokenKind, settings)
        return call(refreshed.apiKey, refreshedBaseUrl, refreshed.accountId)
    }

    private suspend fun <T> callSuperGrokAuthWithRetry(
        initialToken: String,
        initialBaseUrl: String,
        call: suspend (String, String) -> retrofit2.Response<T>
    ): retrofit2.Response<T> {
        val first = call(initialToken, initialBaseUrl)
        if (first.code() != 401) return first

        val refreshed = refreshSuperGrokAuthToken() ?: return first
        return call(refreshed.apiKey, superGrokBaseUrl)
    }

    suspend fun generateContent(
        model: String,
        request: GenerateContentRequest,
        providerOverride: String? = null,
        sessionId: String? = null
    ): retrofit2.Response<GenerateContentResponse> {
        Log.d("ApiRepository", "generateContent called with model: '$model'")
        return when (val contextResult = resolveApiContext(providerOverride)) {
            is ApiContextResult.Success -> {
                val context = contextResult.context
                val settings = context.settings
                val provider = context.apiProvider
                val actualApiKey = context.apiKey
                Log.d("ApiRepository", "About to call provider (${context.providerId}) with model: '$model'")

                context.modelsDevProvider?.let { dynamicProvider ->
                    return generateModelsDev(dynamicProvider, actualApiKey, model, request)
                }

                when (context.providerId) {
                    "OPENROUTER" -> {
                        val prefs = normalizedOpenRouterPreferences(settings)
                        openRouterProvider.generateContent(actualApiKey, model, request, prefs)
                    }
                    "OPENAI" -> {
                        val baseUrl = settings?.openAiBaseUrl?.takeIf { it.isNotBlank() } ?: "https://api.openai.com/v1/"
                        openAiProvider.generateContent(actualApiKey, model, request, baseUrl)
                    }
                    "MINIMAX" -> {
                        val baseUrl = settings?.miniMaxBaseUrl?.takeIf { it.isNotBlank() }
                            ?: MiniMaxUtils.INTERNATIONAL_BASE_URL
                        openAiProvider.generateContent(actualApiKey, model, request, baseUrl)
                    }
                    "CLINEPASS" -> openAiProvider.generateContent(
                        actualApiKey,
                        model,
                        request,
                        ProviderCatalog.defaultClinePassBaseUrl
                    )
                    "OPENAI_COMPAT" -> {
                        val baseUrl = settings?.resolveSelectedCompatBaseUrl() ?: "https://api.openai.com/v1/"
                        openAiProvider.generateContent(actualApiKey, model, request, baseUrl)
                    }
                    "ALIBABA_CODING_PLAN" -> alibabaCodingPlanProvider.generateContent(
                        actualApiKey,
                        model,
                        request,
                        settingsManager.getAlibabaMcpAuthorizationToken()
                    )
                    "CODEX_AUTH" -> {
                        val baseUrl = context.baseUrlOverride ?: codexResponsesProvider.baseUrl
                        callCodexAuthWithRetry(
                            initialToken = actualApiKey,
                            initialBaseUrl = baseUrl,
                            initialAccountId = context.accountId,
                            settings = settings
                        ) { token, resolvedBaseUrl, accountId ->
                            codexResponsesProvider.generateContent(
                                apiKey = token,
                                model = model,
                                request = request,
                                baseUrl = resolvedBaseUrl,
                                accountId = accountId,
                                sessionId = sessionId
                            )
                        }
                    }
                    "SUPERGROK" -> {
                        val baseUrl = context.baseUrlOverride ?: superGrokBaseUrl
                        callSuperGrokAuthWithRetry(
                            initialToken = actualApiKey,
                            initialBaseUrl = baseUrl
                        ) { token, resolvedBaseUrl ->
                            openAiProvider.generateContent(token, model, request, resolvedBaseUrl)
                        }
                    }
                    else -> provider.generateContent(actualApiKey, model, request)
                }
            }
            is ApiContextResult.MissingApiKey -> missingKeyResponse(contextResult.providerId)
        }
    }

    suspend fun streamGenerateContent(
        model: String,
        request: GenerateContentRequest,
        providerOverride: String? = null,
        sessionId: String? = null
    ): retrofit2.Response<ResponseBody> {
        return when (val contextResult = resolveApiContext(providerOverride)) {
            is ApiContextResult.Success -> {
                val context = contextResult.context
                val settings = context.settings
                val provider = context.apiProvider
                val actualApiKey = context.apiKey

                context.modelsDevProvider?.let { dynamicProvider ->
                    return streamModelsDev(dynamicProvider, actualApiKey, model, request)
                }

                when (context.providerId) {
                    "OPENROUTER" -> {
                        val prefs = normalizedOpenRouterPreferences(settings)
                        openRouterProvider.streamGenerateContent(actualApiKey, model, request, prefs)
                    }
                    "OPENAI" -> {
                        val baseUrl = settings?.openAiBaseUrl?.takeIf { it.isNotBlank() } ?: "https://api.openai.com/v1/"
                        openAiProvider.streamGenerateContent(actualApiKey, model, request, baseUrl)
                    }
                    "MINIMAX" -> {
                        val baseUrl = settings?.miniMaxBaseUrl?.takeIf { it.isNotBlank() }
                            ?: MiniMaxUtils.INTERNATIONAL_BASE_URL
                        openAiProvider.streamGenerateContent(actualApiKey, model, request, baseUrl)
                    }
                    "CLINEPASS" -> openAiProvider.streamGenerateContent(
                        actualApiKey,
                        model,
                        request,
                        ProviderCatalog.defaultClinePassBaseUrl
                    )
                    "OPENAI_COMPAT" -> {
                        val baseUrl = settings?.resolveSelectedCompatBaseUrl() ?: "https://api.openai.com/v1/"
                        openAiProvider.streamGenerateContent(actualApiKey, model, request, baseUrl)
                    }
                    "ALIBABA_CODING_PLAN" -> alibabaCodingPlanProvider.streamGenerateContent(
                        actualApiKey,
                        model,
                        request,
                        settingsManager.getAlibabaMcpAuthorizationToken()
                    )
                    "CODEX_AUTH" -> {
                        val baseUrl = context.baseUrlOverride ?: codexResponsesProvider.baseUrl
                        callCodexAuthWithRetry(
                            initialToken = actualApiKey,
                            initialBaseUrl = baseUrl,
                            initialAccountId = context.accountId,
                            settings = settings
                        ) { token, resolvedBaseUrl, accountId ->
                            codexResponsesProvider.streamGenerateContent(
                                apiKey = token,
                                model = model,
                                request = request,
                                baseUrl = resolvedBaseUrl,
                                accountId = accountId,
                                sessionId = sessionId
                            )
                        }
                    }
                    "SUPERGROK" -> {
                        val baseUrl = context.baseUrlOverride ?: superGrokBaseUrl
                        callSuperGrokAuthWithRetry(
                            initialToken = actualApiKey,
                            initialBaseUrl = baseUrl
                        ) { token, resolvedBaseUrl ->
                            openAiProvider.streamGenerateContent(token, model, request, resolvedBaseUrl)
                        }
                    }
                    else -> provider.streamGenerateContent(actualApiKey, model, request)
                }
            }
            is ApiContextResult.MissingApiKey -> missingKeyStreamResponse(contextResult.providerId)
        }
    }

    suspend fun generateDualContent(
        modelA: String,
        modelB: String,
        providerA: String,
        providerB: String,
        requestA: GenerateContentRequest,
        requestB: GenerateContentRequest
    ): Pair<retrofit2.Response<GenerateContentResponse>, retrofit2.Response<GenerateContentResponse>> = coroutineScope {
        if (ProviderReference(providerA).isModelsDev || ProviderReference(providerB).isModelsDev) {
            val responseA = async { generateContent(modelA, requestA, providerA) }
            val responseB = async { generateContent(modelB, requestB, providerB) }
            return@coroutineScope responseA.await() to responseB.await()
        }
        val settings = settingsProvider()

        val apiKeyResultA = when (providerA) {
            "CODEX_AUTH" -> resolveCodexAuthToken()
            "SUPERGROK" -> resolveSuperGrokAuthToken()
            else -> resolveApiKey(
                providerA,
                when (providerA) {
                    "OPENROUTER" -> settingsManager.getApiKey("OPENROUTER")
                    "OPENCODE_GO" -> settingsManager.getApiKey("OPENCODE_GO")
                    "ALIBABA_CODING_PLAN" -> settingsManager.getApiKey("ALIBABA_CODING_PLAN")
                    "OPENAI" -> settingsManager.getApiKey("OPENAI")
                    "MINIMAX" -> settingsManager.getApiKey("MINIMAX")
                    "CLINEPASS" -> settingsManager.getApiKey("CLINEPASS")
                    "OPENAI_COMPAT" -> settingsManager.getOpenAiCompatApiKey(settings?.selectedOpenAiCompatPreset)
                    "ZAI" -> settingsManager.getApiKey("ZAI")
                    else -> settingsManager.getApiKey("GEMINI")
                }
            )
        }

        val apiKeyResultB = when (providerB) {
            "CODEX_AUTH" -> resolveCodexAuthToken()
            "SUPERGROK" -> resolveSuperGrokAuthToken()
            else -> resolveApiKey(
                providerB,
                when (providerB) {
                    "OPENROUTER" -> settingsManager.getApiKey("OPENROUTER")
                    "OPENCODE_GO" -> settingsManager.getApiKey("OPENCODE_GO")
                    "ALIBABA_CODING_PLAN" -> settingsManager.getApiKey("ALIBABA_CODING_PLAN")
                    "OPENAI" -> settingsManager.getApiKey("OPENAI")
                    "MINIMAX" -> settingsManager.getApiKey("MINIMAX")
                    "CLINEPASS" -> settingsManager.getApiKey("CLINEPASS")
                    "OPENAI_COMPAT" -> settingsManager.getOpenAiCompatApiKey(settings?.selectedOpenAiCompatPreset)
                    "ZAI" -> settingsManager.getApiKey("ZAI")
                    else -> settingsManager.getApiKey("GEMINI")
                }
            )
        }

        val normalizedPrefs = if (providerA == "OPENROUTER" || providerB == "OPENROUTER") {
            normalizedOpenRouterPreferences(settings)
        } else {
            null
        }

        val deferredA = async {
            when (apiKeyResultA) {
                is ApiKeyResult.Success -> when (providerA) {
                    "OPENROUTER" -> openRouterProvider.generateContent(apiKeyResultA.apiKey, modelA, requestA, normalizedPrefs)
                    "OPENAI" -> openAiProvider.generateContent(apiKeyResultA.apiKey, modelA, requestA, settings?.openAiBaseUrl ?: "https://api.openai.com/v1/")
                    "MINIMAX" -> openAiProvider.generateContent(apiKeyResultA.apiKey, modelA, requestA, settings?.miniMaxBaseUrl ?: MiniMaxUtils.INTERNATIONAL_BASE_URL)
                    "CLINEPASS" -> openAiProvider.generateContent(apiKeyResultA.apiKey, modelA, requestA, ProviderCatalog.defaultClinePassBaseUrl)
                    "OPENAI_COMPAT" -> openAiProvider.generateContent(apiKeyResultA.apiKey, modelA, requestA, settings?.resolveSelectedCompatBaseUrl() ?: "https://api.openai.com/v1/")
                    "CODEX_AUTH" -> {
                        val baseUrl = codexAuthBaseUrl(apiKeyResultA.tokenKind, settings)
                        callCodexAuthWithRetry(
                            initialToken = apiKeyResultA.apiKey,
                            initialBaseUrl = baseUrl,
                            initialAccountId = apiKeyResultA.accountId,
                            settings = settings
                        ) { token, resolvedBaseUrl, accountId ->
                            codexResponsesProvider.generateContent(
                                token,
                                modelA,
                                requestA,
                                resolvedBaseUrl,
                                accountId
                            )
                        }
                    }
                    "SUPERGROK" -> callSuperGrokAuthWithRetry(
                        initialToken = apiKeyResultA.apiKey,
                        initialBaseUrl = superGrokBaseUrl
                    ) { token, resolvedBaseUrl ->
                        openAiProvider.generateContent(token, modelA, requestA, resolvedBaseUrl)
                    }
                    "ZAI" -> zaiProvider.generateContent(apiKeyResultA.apiKey, modelA, requestA)
                    "OPENCODE_GO" -> openCodeGoProvider.generateContent(apiKeyResultA.apiKey, modelA, requestA)
                    "ALIBABA_CODING_PLAN" -> alibabaCodingPlanProvider.generateContent(
                        apiKeyResultA.apiKey,
                        modelA,
                        requestA,
                        settingsManager.getAlibabaMcpAuthorizationToken()
                    )
                    else -> geminiProvider.generateContent(apiKeyResultA.apiKey, modelA, requestA)
                }
                is ApiKeyResult.Missing -> missingKeyResponse(apiKeyResultA.providerId)
            }
        }

        val deferredB = async {
            when (apiKeyResultB) {
                is ApiKeyResult.Success -> when (providerB) {
                    "OPENROUTER" -> openRouterProvider.generateContent(apiKeyResultB.apiKey, modelB, requestB, normalizedPrefs)
                    "OPENAI" -> openAiProvider.generateContent(apiKeyResultB.apiKey, modelB, requestB, settings?.openAiBaseUrl ?: "https://api.openai.com/v1/")
                    "MINIMAX" -> openAiProvider.generateContent(apiKeyResultB.apiKey, modelB, requestB, settings?.miniMaxBaseUrl ?: MiniMaxUtils.INTERNATIONAL_BASE_URL)
                    "CLINEPASS" -> openAiProvider.generateContent(apiKeyResultB.apiKey, modelB, requestB, ProviderCatalog.defaultClinePassBaseUrl)
                    "OPENAI_COMPAT" -> openAiProvider.generateContent(apiKeyResultB.apiKey, modelB, requestB, settings?.resolveSelectedCompatBaseUrl() ?: "https://api.openai.com/v1/")
                    "CODEX_AUTH" -> {
                        val baseUrl = codexAuthBaseUrl(apiKeyResultB.tokenKind, settings)
                        callCodexAuthWithRetry(
                            initialToken = apiKeyResultB.apiKey,
                            initialBaseUrl = baseUrl,
                            initialAccountId = apiKeyResultB.accountId,
                            settings = settings
                        ) { token, resolvedBaseUrl, accountId ->
                            codexResponsesProvider.generateContent(
                                token,
                                modelB,
                                requestB,
                                resolvedBaseUrl,
                                accountId
                            )
                        }
                    }
                    "SUPERGROK" -> callSuperGrokAuthWithRetry(
                        initialToken = apiKeyResultB.apiKey,
                        initialBaseUrl = superGrokBaseUrl
                    ) { token, resolvedBaseUrl ->
                        openAiProvider.generateContent(token, modelB, requestB, resolvedBaseUrl)
                    }
                    "ZAI" -> zaiProvider.generateContent(apiKeyResultB.apiKey, modelB, requestB)
                    "OPENCODE_GO" -> openCodeGoProvider.generateContent(apiKeyResultB.apiKey, modelB, requestB)
                    "ALIBABA_CODING_PLAN" -> alibabaCodingPlanProvider.generateContent(
                        apiKeyResultB.apiKey,
                        modelB,
                        requestB,
                        settingsManager.getAlibabaMcpAuthorizationToken()
                    )
                    else -> geminiProvider.generateContent(apiKeyResultB.apiKey, modelB, requestB)
                }
                is ApiKeyResult.Missing -> missingKeyResponse(apiKeyResultB.providerId)
            }
        }

        deferredA.await() to deferredB.await()
    }

    suspend fun streamDualContent(
        modelA: String,
        modelB: String,
        providerA: String,
        providerB: String,
        requestA: GenerateContentRequest,
        requestB: GenerateContentRequest
    ): Pair<retrofit2.Response<ResponseBody>, retrofit2.Response<ResponseBody>> = coroutineScope {
        if (ProviderReference(providerA).isModelsDev || ProviderReference(providerB).isModelsDev) {
            val responseA = async { streamGenerateContent(modelA, requestA, providerA) }
            val responseB = async { streamGenerateContent(modelB, requestB, providerB) }
            return@coroutineScope responseA.await() to responseB.await()
        }
        val settings = settingsProvider()

        val apiKeyResultA = when (providerA) {
            "CODEX_AUTH" -> resolveCodexAuthToken()
            "SUPERGROK" -> resolveSuperGrokAuthToken()
            else -> resolveApiKey(
                providerA,
                when (providerA) {
                    "OPENROUTER" -> settingsManager.getApiKey("OPENROUTER")
                    "OPENCODE_GO" -> settingsManager.getApiKey("OPENCODE_GO")
                    "ALIBABA_CODING_PLAN" -> settingsManager.getApiKey("ALIBABA_CODING_PLAN")
                    "OPENAI" -> settingsManager.getApiKey("OPENAI")
                    "MINIMAX" -> settingsManager.getApiKey("MINIMAX")
                    "CLINEPASS" -> settingsManager.getApiKey("CLINEPASS")
                    "OPENAI_COMPAT" -> settingsManager.getOpenAiCompatApiKey(settings?.selectedOpenAiCompatPreset)
                    "ZAI" -> settingsManager.getApiKey("ZAI")
                    else -> settingsManager.getApiKey("GEMINI")
                }
            )
        }

        val apiKeyResultB = when (providerB) {
            "CODEX_AUTH" -> resolveCodexAuthToken()
            "SUPERGROK" -> resolveSuperGrokAuthToken()
            else -> resolveApiKey(
                providerB,
                when (providerB) {
                    "OPENROUTER" -> settingsManager.getApiKey("OPENROUTER")
                    "OPENCODE_GO" -> settingsManager.getApiKey("OPENCODE_GO")
                    "ALIBABA_CODING_PLAN" -> settingsManager.getApiKey("ALIBABA_CODING_PLAN")
                    "OPENAI" -> settingsManager.getApiKey("OPENAI")
                    "MINIMAX" -> settingsManager.getApiKey("MINIMAX")
                    "CLINEPASS" -> settingsManager.getApiKey("CLINEPASS")
                    "OPENAI_COMPAT" -> settingsManager.getOpenAiCompatApiKey(settings?.selectedOpenAiCompatPreset)
                    "ZAI" -> settingsManager.getApiKey("ZAI")
                    else -> settingsManager.getApiKey("GEMINI")
                }
            )
        }

        val normalizedPrefs = if (providerA == "OPENROUTER" || providerB == "OPENROUTER") {
            normalizedOpenRouterPreferences(settings)
        } else {
            null
        }

        val deferredA = async {
            when (apiKeyResultA) {
                is ApiKeyResult.Success -> when (providerA) {
                    "OPENROUTER" -> openRouterProvider.streamGenerateContent(apiKeyResultA.apiKey, modelA, requestA, normalizedPrefs)
                    "OPENAI" -> openAiProvider.streamGenerateContent(apiKeyResultA.apiKey, modelA, requestA, settings?.openAiBaseUrl ?: "https://api.openai.com/v1/")
                    "MINIMAX" -> openAiProvider.streamGenerateContent(apiKeyResultA.apiKey, modelA, requestA, settings?.miniMaxBaseUrl ?: MiniMaxUtils.INTERNATIONAL_BASE_URL)
                    "CLINEPASS" -> openAiProvider.streamGenerateContent(apiKeyResultA.apiKey, modelA, requestA, ProviderCatalog.defaultClinePassBaseUrl)
                    "OPENAI_COMPAT" -> openAiProvider.streamGenerateContent(apiKeyResultA.apiKey, modelA, requestA, settings?.resolveSelectedCompatBaseUrl() ?: "https://api.openai.com/v1/")
                    "CODEX_AUTH" -> {
                        val baseUrl = codexAuthBaseUrl(apiKeyResultA.tokenKind, settings)
                        callCodexAuthWithRetry(
                            initialToken = apiKeyResultA.apiKey,
                            initialBaseUrl = baseUrl,
                            initialAccountId = apiKeyResultA.accountId,
                            settings = settings
                        ) { token, resolvedBaseUrl, accountId ->
                            codexResponsesProvider.streamGenerateContent(
                                token,
                                modelA,
                                requestA,
                                resolvedBaseUrl,
                                accountId
                            )
                        }
                    }
                    "SUPERGROK" -> callSuperGrokAuthWithRetry(
                        initialToken = apiKeyResultA.apiKey,
                        initialBaseUrl = superGrokBaseUrl
                    ) { token, resolvedBaseUrl ->
                        openAiProvider.streamGenerateContent(token, modelA, requestA, resolvedBaseUrl)
                    }
                    "ZAI" -> zaiProvider.streamGenerateContent(apiKeyResultA.apiKey, modelA, requestA)
                    "OPENCODE_GO" -> openCodeGoProvider.streamGenerateContent(apiKeyResultA.apiKey, modelA, requestA)
                    "ALIBABA_CODING_PLAN" -> alibabaCodingPlanProvider.streamGenerateContent(
                        apiKeyResultA.apiKey,
                        modelA,
                        requestA,
                        settingsManager.getAlibabaMcpAuthorizationToken()
                    )
                    else -> geminiProvider.streamGenerateContent(apiKeyResultA.apiKey, modelA, requestA)
                }
                is ApiKeyResult.Missing -> missingKeyStreamResponse(apiKeyResultA.providerId)
            }
        }

        val deferredB = async {
            when (apiKeyResultB) {
                is ApiKeyResult.Success -> when (providerB) {
                    "OPENROUTER" -> openRouterProvider.streamGenerateContent(apiKeyResultB.apiKey, modelB, requestB, normalizedPrefs)
                    "OPENAI" -> openAiProvider.streamGenerateContent(apiKeyResultB.apiKey, modelB, requestB, settings?.openAiBaseUrl ?: "https://api.openai.com/v1/")
                    "MINIMAX" -> openAiProvider.streamGenerateContent(apiKeyResultB.apiKey, modelB, requestB, settings?.miniMaxBaseUrl ?: MiniMaxUtils.INTERNATIONAL_BASE_URL)
                    "CLINEPASS" -> openAiProvider.streamGenerateContent(apiKeyResultB.apiKey, modelB, requestB, ProviderCatalog.defaultClinePassBaseUrl)
                    "OPENAI_COMPAT" -> openAiProvider.streamGenerateContent(apiKeyResultB.apiKey, modelB, requestB, settings?.resolveSelectedCompatBaseUrl() ?: "https://api.openai.com/v1/")
                    "CODEX_AUTH" -> {
                        val baseUrl = codexAuthBaseUrl(apiKeyResultB.tokenKind, settings)
                        callCodexAuthWithRetry(
                            initialToken = apiKeyResultB.apiKey,
                            initialBaseUrl = baseUrl,
                            initialAccountId = apiKeyResultB.accountId,
                            settings = settings
                        ) { token, resolvedBaseUrl, accountId ->
                            codexResponsesProvider.streamGenerateContent(
                                token,
                                modelB,
                                requestB,
                                resolvedBaseUrl,
                                accountId
                            )
                        }
                    }
                    "SUPERGROK" -> callSuperGrokAuthWithRetry(
                        initialToken = apiKeyResultB.apiKey,
                        initialBaseUrl = superGrokBaseUrl
                    ) { token, resolvedBaseUrl ->
                        openAiProvider.streamGenerateContent(token, modelB, requestB, resolvedBaseUrl)
                    }
                    "ZAI" -> zaiProvider.streamGenerateContent(apiKeyResultB.apiKey, modelB, requestB)
                    "OPENCODE_GO" -> openCodeGoProvider.streamGenerateContent(apiKeyResultB.apiKey, modelB, requestB)
                    "ALIBABA_CODING_PLAN" -> alibabaCodingPlanProvider.streamGenerateContent(
                        apiKeyResultB.apiKey,
                        modelB,
                        requestB,
                        settingsManager.getAlibabaMcpAuthorizationToken()
                    )
                    else -> geminiProvider.streamGenerateContent(apiKeyResultB.apiKey, modelB, requestB)
                }
                is ApiKeyResult.Missing -> missingKeyStreamResponse(apiKeyResultB.providerId)
            }
        }

        deferredA.await() to deferredB.await()
    }

    suspend fun generateAutoConversationResponse(
        model: String,
        provider: String,
        systemPrompt: String,
        conversationHistory: List<com.porarri.yamabikochat.data.remote.Content>,
        reasoningContext: ReasoningContext
    ): retrofit2.Response<GenerateContentResponse> {
        val settings = settingsProvider()

        val thinkingConfig = settings?.buildThinkingConfigFor(provider, model, reasoningContext)
        val generationConfig = buildGenerationConfig(settings, provider, model, thinkingConfig)
        val codexConfig = if (provider.uppercase() == "CODEX_AUTH") {
            settings?.buildCodexRequestConfig(model)
        } else {
            null
        }
        val tools = settings?.let { ToolingUtils.buildTools(it, provider, reasoningContext) }.orEmpty()

        val request = GenerateContentRequest(
            contents = conversationHistory,
            generationConfig = generationConfig,
            system_instruction = com.porarri.yamabikochat.data.remote.SystemInstruction(
                parts = listOf(Part(systemPrompt))
            ),
            tools = tools.takeIf { it.isNotEmpty() },
            codexConfig = codexConfig
        )

        if (ProviderReference(provider).isModelsDev) {
            return generateContent(model, request, provider)
        }

        val apiKeyResult = when (provider) {
            "CODEX_AUTH" -> resolveCodexAuthToken()
            "SUPERGROK" -> resolveSuperGrokAuthToken()
            else -> resolveApiKey(
                provider,
                when (provider) {
                    "OPENROUTER" -> settingsManager.getApiKey("OPENROUTER")
                    "OPENCODE_GO" -> settingsManager.getApiKey("OPENCODE_GO")
                    "ALIBABA_CODING_PLAN" -> settingsManager.getApiKey("ALIBABA_CODING_PLAN")
                    "OPENAI" -> settingsManager.getApiKey("OPENAI")
                    "MINIMAX" -> settingsManager.getApiKey("MINIMAX")
                    "CLINEPASS" -> settingsManager.getApiKey("CLINEPASS")
                    "OPENAI_COMPAT" -> settingsManager.getOpenAiCompatApiKey(settings?.selectedOpenAiCompatPreset)
                    "ZAI" -> settingsManager.getApiKey("ZAI")
                    else -> settingsManager.getApiKey("GEMINI")
                }
            )
        }

        if (apiKeyResult is ApiKeyResult.Missing) {
            return missingKeyResponse(apiKeyResult.providerId)
        }

        val apiKeySuccess = apiKeyResult as ApiKeyResult.Success
        val apiKey = apiKeySuccess.apiKey

        return when (provider) {
            "OPENROUTER" -> openRouterProvider.generateContent(apiKey, model, request, normalizedOpenRouterPreferences(settings))
            "OPENAI" -> openAiProvider.generateContent(apiKey, model, request, settings?.openAiBaseUrl ?: "https://api.openai.com/v1/")
            "MINIMAX" -> openAiProvider.generateContent(apiKey, model, request, settings?.miniMaxBaseUrl ?: MiniMaxUtils.INTERNATIONAL_BASE_URL)
            "CLINEPASS" -> openAiProvider.generateContent(apiKey, model, request, ProviderCatalog.defaultClinePassBaseUrl)
            "OPENAI_COMPAT" -> openAiProvider.generateContent(apiKey, model, request, settings?.resolveSelectedCompatBaseUrl() ?: "https://api.openai.com/v1/")
            "CODEX_AUTH" -> {
                val baseUrl = codexAuthBaseUrl(apiKeySuccess.tokenKind, settings)
                callCodexAuthWithRetry(
                    initialToken = apiKey,
                    initialBaseUrl = baseUrl,
                    initialAccountId = apiKeySuccess.accountId,
                    settings = settings
                ) { token, resolvedBaseUrl, accountId ->
                    codexResponsesProvider.generateContent(token, model, request, resolvedBaseUrl, accountId)
                }
            }
            "SUPERGROK" -> callSuperGrokAuthWithRetry(
                initialToken = apiKey,
                initialBaseUrl = superGrokBaseUrl
            ) { token, resolvedBaseUrl ->
                openAiProvider.generateContent(token, model, request, resolvedBaseUrl)
            }
            "ZAI" -> zaiProvider.generateContent(apiKey, model, request)
            "OPENCODE_GO" -> openCodeGoProvider.generateContent(apiKey, model, request)
            "ALIBABA_CODING_PLAN" -> alibabaCodingPlanProvider.generateContent(
                apiKey,
                model,
                request,
                settingsManager.getAlibabaMcpAuthorizationToken()
            )
            else -> geminiProvider.generateContent(apiKey, model, request)
        }
    }

    private fun buildGenerationConfig(
        settings: Settings?,
        provider: String,
        model: String,
        thinkingConfig: ThinkingConfig?
    ): GenerationConfig {
        val base = GenerationConfig(thinkingConfig = thinkingConfig)
        if (provider.uppercase() != "GEMINI") return base

        val responseMimeType = settings?.geminiResponseMimeType?.trim()?.takeIf { it.isNotEmpty() }
        val responseJsonSchema = settings?.geminiResponseJsonSchema?.trim()?.takeIf { it.isNotEmpty() }?.let { raw ->
            runCatching { json.parseToJsonElement(raw) }.getOrElse { err ->
                Log.w("ApiRepository", "Invalid response JSON schema for model=$model: ${err.message}")
                null
            }
        }

        return base.copy(
            responseMimeType = responseMimeType,
            responseJsonSchema = responseJsonSchema
        )
    }

    suspend fun saveApiKey(provider: String, apiKey: String?): Boolean =
        settingsManager.saveApiKey(provider, apiKey)

    fun hasApiKey(provider: String): Boolean = settingsManager.hasApiKey(provider)

    fun peekApiKey(provider: String): String? = settingsManager.getApiKey(provider)

    // OpenAI-compatible preset API key helpers
    suspend fun saveOpenAiCompatApiKey(name: String, apiKey: String?): Boolean =
        settingsManager.saveOpenAiCompatApiKey(name, apiKey)

    suspend fun saveModelsDevField(providerId: String, fieldName: String, value: String?): Boolean =
        settingsManager.saveModelsDevField(providerId, fieldName, value)

    fun peekModelsDevField(providerId: String, fieldName: String): String? =
        settingsManager.getModelsDevField(providerId, fieldName)

    fun peekOpenAiCompatApiKey(name: String): String? = settingsManager.getOpenAiCompatApiKey(name)

    fun hasOpenAiCompatApiKey(name: String?): Boolean = settingsManager.hasOpenAiCompatApiKey(name)

    suspend fun clearOpenAiCompatApiKey(name: String) = settingsManager.clearOpenAiCompatApiKey(name)

    suspend fun saveAlibabaMcpAuthorizationToken(token: String?): Boolean =
        settingsManager.saveAlibabaMcpAuthorizationToken(token)

    fun peekAlibabaMcpAuthorizationToken(): String? =
        settingsManager.getAlibabaMcpAuthorizationToken()
}
