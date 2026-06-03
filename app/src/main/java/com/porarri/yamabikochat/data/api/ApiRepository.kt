package com.porarri.yamabikochat.data.api

import android.util.Log
import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.data.local.Settings.ReasoningContext
import com.porarri.yamabikochat.data.local.SettingsManager
import com.porarri.yamabikochat.data.auth.CodexAuthRepository
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
import com.porarri.yamabikochat.data.remote.CodexResponsesProvider
import com.porarri.yamabikochat.data.remote.ZaiProvider
import com.porarri.yamabikochat.data.remote.Part
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

class ApiRepository(
    private val geminiProvider: GeminiProvider,
    private val openRouterProvider: OpenRouterProvider,
    private val openAiProvider: OpenAiProvider,
    private val openCodeGoProvider: OpenCodeGoProvider,
    private val alibabaCodingPlanProvider: AlibabaCodingPlanProvider,
    private val codexResponsesProvider: CodexResponsesProvider,
    private val zaiProvider: ZaiProvider,
    private val settingsManager: SettingsManager,
    private val codexAuthRepository: CodexAuthRepository,
    private val modelRepository: ModelRepository,
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
        val accountId: String? = null
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

    private fun missingKeyMessage(providerId: String) =
        "API key for $providerId provider is not configured."

    private fun missingKeyResponse(providerId: String): retrofit2.Response<GenerateContentResponse> =
        retrofit2.Response.error(401, missingKeyMessage(providerId).toResponseBody(missingKeyMediaType))

    private fun missingKeyStreamResponse(providerId: String): retrofit2.Response<ResponseBody> =
        retrofit2.Response.error(401, missingKeyMessage(providerId).toResponseBody(missingKeyMediaType))

    private suspend fun resolveApiContext(providerOverride: String? = null): ApiContextResult {
        val settings = settingsProvider()
        val resolvedProvider = providerOverride?.uppercase()
            ?: settings?.apiProvider
            ?: "GEMINI"

        val apiProvider = when (resolvedProvider) {
            "OPENROUTER" -> openRouterProvider
            "OPENCODE_GO" -> openCodeGoProvider
            "ALIBABA_CODING_PLAN" -> alibabaCodingPlanProvider
            "OPENAI", "OPENAI_COMPAT", "MINIMAX" -> openAiProvider
            "CODEX_AUTH" -> codexResponsesProvider
            "ZAI" -> zaiProvider
            else -> geminiProvider
        }

        val keyResult = when (resolvedProvider) {
            "CODEX_AUTH" -> resolveCodexAuthToken()
            else -> resolveApiKey(
                resolvedProvider,
                when (resolvedProvider) {
                    "OPENROUTER" -> settingsManager.getApiKey("OPENROUTER")
                    "OPENCODE_GO" -> settingsManager.getApiKey("OPENCODE_GO")
                    "ALIBABA_CODING_PLAN" -> settingsManager.getApiKey("ALIBABA_CODING_PLAN")
                    "OPENAI" -> settingsManager.getApiKey("OPENAI")
                    "MINIMAX" -> settingsManager.getApiKey("MINIMAX")
                    "OPENAI_COMPAT" -> settingsManager.getOpenAiCompatApiKey(settings?.selectedOpenAiCompatPreset)
                    "ZAI" -> settingsManager.getApiKey("ZAI")
                    else -> settingsManager.getApiKey("GEMINI")
                }
            )
        }

        return when (keyResult) {
            is ApiKeyResult.Success -> {
                val tokenLabel = if (resolvedProvider == "CODEX_AUTH" && keyResult.tokenKind == TokenKind.AccessToken) {
                    "Access Token"
                } else {
                    "API Key"
                }
                Log.d("ApiRepository", "Using $resolvedProvider $tokenLabel")
                val baseUrlOverride = if (resolvedProvider == "CODEX_AUTH") {
                    codexAuthBaseUrl(keyResult.tokenKind, settings)
                } else {
                    null
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
                        accountId = keyResult.accountId
                    )
                )
            }
            is ApiKeyResult.Missing -> ApiContextResult.MissingApiKey(keyResult.providerId)
        }
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
        val settings = settingsProvider()

        val apiKeyResultA = when (providerA) {
            "CODEX_AUTH" -> resolveCodexAuthToken()
            else -> resolveApiKey(
                providerA,
                when (providerA) {
                    "OPENROUTER" -> settingsManager.getApiKey("OPENROUTER")
                    "OPENCODE_GO" -> settingsManager.getApiKey("OPENCODE_GO")
                    "ALIBABA_CODING_PLAN" -> settingsManager.getApiKey("ALIBABA_CODING_PLAN")
                    "OPENAI" -> settingsManager.getApiKey("OPENAI")
                    "MINIMAX" -> settingsManager.getApiKey("MINIMAX")
                    "OPENAI_COMPAT" -> settingsManager.getOpenAiCompatApiKey(settings?.selectedOpenAiCompatPreset)
                    "ZAI" -> settingsManager.getApiKey("ZAI")
                    else -> settingsManager.getApiKey("GEMINI")
                }
            )
        }

        val apiKeyResultB = when (providerB) {
            "CODEX_AUTH" -> resolveCodexAuthToken()
            else -> resolveApiKey(
                providerB,
                when (providerB) {
                    "OPENROUTER" -> settingsManager.getApiKey("OPENROUTER")
                    "OPENCODE_GO" -> settingsManager.getApiKey("OPENCODE_GO")
                    "ALIBABA_CODING_PLAN" -> settingsManager.getApiKey("ALIBABA_CODING_PLAN")
                    "OPENAI" -> settingsManager.getApiKey("OPENAI")
                    "MINIMAX" -> settingsManager.getApiKey("MINIMAX")
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
        val settings = settingsProvider()

        val apiKeyResultA = when (providerA) {
            "CODEX_AUTH" -> resolveCodexAuthToken()
            else -> resolveApiKey(
                providerA,
                when (providerA) {
                    "OPENROUTER" -> settingsManager.getApiKey("OPENROUTER")
                    "OPENCODE_GO" -> settingsManager.getApiKey("OPENCODE_GO")
                    "ALIBABA_CODING_PLAN" -> settingsManager.getApiKey("ALIBABA_CODING_PLAN")
                    "OPENAI" -> settingsManager.getApiKey("OPENAI")
                    "MINIMAX" -> settingsManager.getApiKey("MINIMAX")
                    "OPENAI_COMPAT" -> settingsManager.getOpenAiCompatApiKey(settings?.selectedOpenAiCompatPreset)
                    "ZAI" -> settingsManager.getApiKey("ZAI")
                    else -> settingsManager.getApiKey("GEMINI")
                }
            )
        }

        val apiKeyResultB = when (providerB) {
            "CODEX_AUTH" -> resolveCodexAuthToken()
            else -> resolveApiKey(
                providerB,
                when (providerB) {
                    "OPENROUTER" -> settingsManager.getApiKey("OPENROUTER")
                    "OPENCODE_GO" -> settingsManager.getApiKey("OPENCODE_GO")
                    "ALIBABA_CODING_PLAN" -> settingsManager.getApiKey("ALIBABA_CODING_PLAN")
                    "OPENAI" -> settingsManager.getApiKey("OPENAI")
                    "MINIMAX" -> settingsManager.getApiKey("MINIMAX")
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
        val apiKeyResult = when (provider) {
            "CODEX_AUTH" -> resolveCodexAuthToken()
            else -> resolveApiKey(
                provider,
                when (provider) {
                    "OPENROUTER" -> settingsManager.getApiKey("OPENROUTER")
                    "OPENCODE_GO" -> settingsManager.getApiKey("OPENCODE_GO")
                    "ALIBABA_CODING_PLAN" -> settingsManager.getApiKey("ALIBABA_CODING_PLAN")
                    "OPENAI" -> settingsManager.getApiKey("OPENAI")
                    "MINIMAX" -> settingsManager.getApiKey("MINIMAX")
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

        return when (provider) {
            "OPENROUTER" -> openRouterProvider.generateContent(apiKey, model, request, normalizedOpenRouterPreferences(settings))
            "OPENAI" -> openAiProvider.generateContent(apiKey, model, request, settings?.openAiBaseUrl ?: "https://api.openai.com/v1/")
            "MINIMAX" -> openAiProvider.generateContent(apiKey, model, request, settings?.miniMaxBaseUrl ?: MiniMaxUtils.INTERNATIONAL_BASE_URL)
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

    fun peekOpenAiCompatApiKey(name: String): String? = settingsManager.getOpenAiCompatApiKey(name)

    fun hasOpenAiCompatApiKey(name: String?): Boolean = settingsManager.hasOpenAiCompatApiKey(name)

    suspend fun clearOpenAiCompatApiKey(name: String) = settingsManager.clearOpenAiCompatApiKey(name)

    suspend fun saveAlibabaMcpAuthorizationToken(token: String?): Boolean =
        settingsManager.saveAlibabaMcpAuthorizationToken(token)

    fun peekAlibabaMcpAuthorizationToken(): String? =
        settingsManager.getAlibabaMcpAuthorizationToken()
}
