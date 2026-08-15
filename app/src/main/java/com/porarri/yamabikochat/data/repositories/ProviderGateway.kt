package com.porarri.yamabikochat.data.repositories

import com.porarri.yamabikochat.data.auth.CodexAuthRepository
import com.porarri.yamabikochat.data.auth.SuperGrokAuthRepository
import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.data.model.LLMProvider
import com.porarri.yamabikochat.data.model.ProviderClientError
import com.porarri.yamabikochat.data.model.ProviderRequest
import com.porarri.yamabikochat.data.model.ProviderResponse
import com.porarri.yamabikochat.data.model.ProviderStreamEvent
import com.porarri.yamabikochat.data.model.ProviderThinkingConfig
import com.porarri.yamabikochat.data.modelsdev.ModelsDevCatalogRepository
import com.porarri.yamabikochat.data.modelsdev.ModelsDevProviderAdapterRegistry
import com.porarri.yamabikochat.data.modelsdev.ProviderAdapterKind
import com.porarri.yamabikochat.data.modelsdev.ProviderReference
import com.porarri.yamabikochat.data.remote.OpenCodeGoModelCatalog
import com.porarri.yamabikochat.data.remote.ProviderCatalog
import com.porarri.yamabikochat.data.tools.LocalToolRegistry
import com.porarri.yamabikochat.data.tools.search.FetchUrlTool
import com.porarri.yamabikochat.data.tools.search.WebSearchTool
import com.porarri.yamabikochat.pi.PiAgentConfiguration
import com.porarri.yamabikochat.pi.PiAgentRuntime
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import com.porarri.yamabikochat.utils.SecurePreferencesManager
import kotlinx.coroutines.flow.Flow
import java.util.UUID

typealias PiAgentStreamFn = (
    ProviderRequest,
    PiAgentConfiguration,
    LocalToolRegistry
) -> Flow<ProviderStreamEvent>

class ProviderGateway(
    private val settingsProvider: suspend () -> Settings?,
    private val securePreferences: SecurePreferencesManager,
    private val codexAuthRepository: CodexAuthRepository? = null,
    private val superGrokAuthRepository: SuperGrokAuthRepository? = null,
    private val modelsDevCatalogRepository: ModelsDevCatalogRepository? = null,
    private val localTools: LocalToolRegistry = LocalToolRegistry(listOf(WebSearchTool(), FetchUrlTool())),
    private val piStream: PiAgentStreamFn? = null,
    private val piRuntime: PiAgentRuntime? = null
) {
    suspend fun generate(request: ProviderRequest, provider: LLMProvider): ProviderResponse {
        return generate(request, provider.rawValue)
    }

    suspend fun generate(request: ProviderRequest, providerID: String): ProviderResponse {
        val streamFlow = stream(request, providerID)
        var completed: ProviderResponse? = null
        var text = ""
        var reasoning = ""

        streamFlow.collect { event ->
            when (event) {
                is ProviderStreamEvent.TextDelta -> text += event.delta
                is ProviderStreamEvent.ReasoningDelta -> reasoning += event.delta
                is ProviderStreamEvent.Completed -> completed = event.response
            }
        }

        val response = completed ?: throw ProviderClientError.ParseFailure("Pi agent stream ended without completion")
        if (response.text.isEmpty()) response.text = text
        if (response.reasoningSummary == null && reasoning.trim().isNotEmpty()) {
            response.reasoningSummary = reasoning.trim()
        }
        return response
    }

    suspend fun stream(request: ProviderRequest, provider: LLMProvider): Flow<ProviderStreamEvent> {
        return stream(request, provider.rawValue)
    }

    suspend fun stream(request: ProviderRequest, providerID: String): Flow<ProviderStreamEvent> {
        val requestId = UUID.randomUUID().toString()
        val normalizedProvider = providerID.trim().uppercase()

        DiagnosticsLogger.log(
            "Provider gateway entered requestId=$requestId provider=$normalizedProvider model=${request.model} messages=${request.messages.size}"
        )

        val settings = settingsProvider() ?: Settings()
        val piConfiguration = configuration(providerID, request, settings)

        DiagnosticsLogger.log(
            "Pi agent configuration ready provider=${piConfiguration.provider} model=${piConfiguration.model} api=${piConfiguration.api}"
        )

        val streamExecutor = piStream ?: { req, cfg, tools ->
            val runtime = piRuntime ?: throw ProviderClientError.ParseFailure("Pi runtime not configured")
            runtime.stream(req, cfg, tools)
        }

        return streamExecutor(request, piConfiguration, localTools)
    }

    private suspend fun configuration(
        providerID: String,
        request: ProviderRequest,
        settings: Settings
    ): PiAgentConfiguration {
        val dynamicID = ProviderReference(providerID).modelsDevId
        if (dynamicID != null) {
            return modelsDevConfiguration(dynamicID, request)
        }

        val provider = knownProvider(providerID)
            ?: throw ProviderClientError.ParseFailure("Unknown provider: $providerID")

        var api = "openai-completions"
        var piProvider = provider.rawValue.lowercase()
        var baseURL: String
        var apiKey: String
        var headers: MutableMap<String, String> = mutableMapOf()
        var mcpAuthorizationToken: String? = null

        when (provider) {
            LLMProvider.GEMINI -> {
                api = "google-generative-ai"
                piProvider = "google"
                baseURL = "https://generativelanguage.googleapis.com/v1beta"
                apiKey = credential(provider)
            }
            LLMProvider.OPENROUTER -> {
                piProvider = "openrouter"
                baseURL = "https://openrouter.ai/api/v1"
                apiKey = credential(provider)
                headers["HTTP-Referer"] = "https://yamabikochat.app"
                headers["X-Title"] = "YamabikoChat Android"
            }
            LLMProvider.OPENAI -> {
                api = "openai-responses"
                piProvider = "openai"
                baseURL = normalizedBaseURL(settings.openAiBaseUrl)
                apiKey = credential(provider)
            }
            LLMProvider.OPENAI_COMPAT -> {
                val name = settings.selectedOpenAiCompatPreset?.trim()?.takeIf { it.isNotEmpty() }
                    ?: throw ProviderClientError.MissingCredential(LLMProvider.OPENAI_COMPAT.rawValue)
                val value = securePreferences.getCustomApiKey(name)?.trim()?.takeIf { it.isNotEmpty() }
                    ?: throw ProviderClientError.MissingCredential(LLMProvider.OPENAI_COMPAT.rawValue)
                baseURL = normalizedBaseURL(
                    settings.resolveSelectedCompatBaseUrl() ?: settings.openAiBaseUrl
                )
                apiKey = value
            }
            LLMProvider.MINIMAX -> {
                piProvider = "minimax"
                baseURL = normalizedBaseURL(settings.miniMaxBaseUrl)
                apiKey = credential(provider)
            }
            LLMProvider.ZAI -> {
                piProvider = "zai"
                baseURL = normalizedBaseURL(ProviderCatalog.defaultZaiCodingPlanBaseUrl)
                apiKey = credential(provider)
            }
            LLMProvider.CLINEPASS -> {
                piProvider = "cline-pass"
                baseURL = normalizedBaseURL(ProviderCatalog.defaultClinePassBaseUrl)
                apiKey = credential(provider)
            }
            LLMProvider.ALIBABA_CODING_PLAN -> {
                api = "anthropic-messages"
                piProvider = "qwen-token-plan"
                baseURL = normalizedAnthropicBaseURL(ProviderCatalog.defaultAlibabaCodingPlanBaseUrl)
                apiKey = credential(provider)
                if (request.tools.any { it.type == "mcp_toolset" }) {
                    headers["anthropic-beta"] = "mcp-client-2025-11-20"
                    mcpAuthorizationToken = securePreferences.getAlibabaMcpAuthorizationToken()?.trim()
                }
            }
            LLMProvider.OPENCODE_GO -> {
                val route = OpenCodeGoModelCatalog.modelFor(request.model)
                    ?: throw ProviderClientError.InvalidBaseURL("Unsupported OpenCode Go model: ${request.model}")
                piProvider = "opencode-go"
                api = if (route.endpointKind == com.porarri.yamabikochat.data.remote.OpenCodeGoEndpointKind.MESSAGES) {
                    "anthropic-messages"
                } else "openai-completions"
                baseURL = normalizedBaseURL(ProviderCatalog.defaultOpenCodeGoBaseUrl)
                apiKey = credential(provider)
            }
            LLMProvider.CODEX_AUTH -> {
                val auth = codexAuthRepository?.getBearerToken()
                    ?: throw ProviderClientError.MissingCredential(LLMProvider.CODEX_AUTH.rawValue)
                api = "openai-codex-responses"
                piProvider = "openai-codex"
                baseURL = "https://chatgpt.com/backend-api/codex"
                apiKey = auth.token
                headers["originator"] = "codex_cli_rs"
                if (!auth.accountId.isNullOrBlank()) {
                    headers["ChatGPT-Account-ID"] = auth.accountId
                }
            }
            LLMProvider.SUPERGROK -> {
                val auth = superGrokAuthRepository?.getBearerToken()
                    ?: throw ProviderClientError.MissingCredential(LLMProvider.SUPERGROK.rawValue)
                api = "openai-responses"
                piProvider = "xai-oauth"
                baseURL = normalizedBaseURL(ProviderCatalog.defaultSuperGrokBaseUrl)
                apiKey = auth.token
            }
            LLMProvider.APPLE_INTELLIGENCE -> {
                throw ProviderClientError.UnsupportedModel("APPLE_INTELLIGENCE", request.model)
            }
        }

        return PiAgentConfiguration(
            provider = piProvider,
            model = normalizedModel(request.model, provider),
            api = api,
            baseURL = baseURL,
            apiKey = apiKey,
            headers = headers,
            reasoning = request.thinking?.enabled != false,
            thinkingLevel = thinkingLevel(
                request.thinking,
                geminiLevel = if (provider == LLMProvider.GEMINI) request.metadata["geminiThinkingLevel"] else null
            ),
            supportsImages = request.metadata["supportsVision"] == "true",
            contextWindow = 128000,
            maxTokens = maxOf(1024, request.metadata["max_output_tokens"]?.toIntOrNull() ?: 8192),
            mcpAuthorizationToken = mcpAuthorizationToken
        )
    }

    private fun modelsDevConfiguration(
        providerID: String,
        request: ProviderRequest
    ): PiAgentConfiguration {
        val catalog = modelsDevCatalogRepository?.provider(ProviderReference.modelsDev(providerID))
            ?: throw ProviderClientError.ParseFailure("models.dev provider is unavailable: $providerID")
        val model = catalog.models.firstOrNull { it.id == request.model }
            ?: throw ProviderClientError.ParseFailure("models.dev model is unavailable: $providerID/${request.model}")

        val credentialField = catalog.env.firstOrNull { field ->
            field.contains("API_KEY") || field.contains("TOKEN") || field.contains("SECRET") || field.contains("BEARER")
        } ?: catalog.env.firstOrNull() ?: throw ProviderClientError.MissingCredential(providerID)

        val credentialKey = modelsDevFieldKey(providerID, credentialField)
        migrateLegacyCredentialIfNeeded(providerID, credentialKey)

        val apiKey = securePreferences.readSecret(credentialKey)?.trim()?.takeIf { it.isNotEmpty() }
            ?: throw ProviderClientError.MissingCredential(providerID)

        val manual = securePreferences.readSecret(modelsDevFieldKey(providerID, "YAMABIKO_BASE_URL"))?.trim()
        val base = catalog.api?.trim()?.takeIf { !it.contains("\${") }
            ?: knownModelsDevBaseURL(providerID)
            ?: manual
            ?: throw ProviderClientError.InvalidBaseURL("A completed base URL is required for ${catalog.name}")

        val adapter = ModelsDevProviderAdapterRegistry.profile(catalog).adapter
        if (adapter != ProviderAdapterKind.ANTHROPIC && !isOpenAICompatible(adapter)) {
            throw ProviderClientError.ParseFailure("${catalog.name} has no Pi-compatible adapter")
        }

        val headers = mutableMapOf<String, String>()
        if (adapter == ProviderAdapterKind.AZURE_OPEN_AI) headers["api-key"] = apiKey
        if (adapter == ProviderAdapterKind.CLOUDFLARE_AI_GATEWAY) headers["cf-aig-authorization"] = "Bearer $apiKey"

        return PiAgentConfiguration(
            provider = providerID,
            model = request.model,
            api = if (adapter == ProviderAdapterKind.ANTHROPIC) "anthropic-messages" else "openai-completions",
            baseURL = if (adapter == ProviderAdapterKind.ANTHROPIC) normalizedAnthropicBaseURL(base) else normalizedBaseURL(base),
            apiKey = apiKey,
            headers = headers,
            reasoning = model.reasoning,
            thinkingLevel = thinkingLevel(request.thinking),
            supportsImages = model.attachment,
            contextWindow = (model.limits.context ?: model.limits.input ?: 128000L).toInt(),
            maxTokens = (model.limits.output ?: 8192L).toInt()
        )
    }

    private fun isOpenAICompatible(adapter: ProviderAdapterKind): Boolean {
        return when (adapter) {
            ProviderAdapterKind.OPEN_AI_COMPATIBLE,
            ProviderAdapterKind.OPEN_AI,
            ProviderAdapterKind.PROVIDER_SPECIFIC,
            ProviderAdapterKind.COHERE,
            ProviderAdapterKind.VERCEL_AI,
            ProviderAdapterKind.CLOUDFLARE_AI_GATEWAY,
            ProviderAdapterKind.AZURE_OPEN_AI,
            ProviderAdapterKind.UNVERIFIED_OPEN_AI_COMPATIBLE -> true
            else -> false
        }
    }

    private fun credential(provider: LLMProvider): String {
        val value = when (provider) {
            LLMProvider.GEMINI -> securePreferences.getGeminiApiKey()
            LLMProvider.OPENROUTER -> securePreferences.getOpenRouterApiKey()
            LLMProvider.OPENAI -> securePreferences.getOpenAiApiKey()
            LLMProvider.MINIMAX -> securePreferences.getMiniMaxApiKey()
            LLMProvider.ZAI -> securePreferences.getZaiApiKey()
            LLMProvider.CLINEPASS -> securePreferences.getClinePassApiKey()
            LLMProvider.ALIBABA_CODING_PLAN -> securePreferences.getAlibabaCodingPlanApiKey()
            LLMProvider.OPENCODE_GO -> securePreferences.getOpenCodeGoApiKey()
            else -> null
        }?.trim()?.takeIf { it.isNotEmpty() }

        return value ?: throw ProviderClientError.MissingCredential(provider.rawValue)
    }

    private fun knownProvider(value: String): LLMProvider? {
        return LLMProvider.fromRawOrNull(value)
    }

    private fun normalizedModel(model: String, provider: LLMProvider): String {
        return if (provider == LLMProvider.CODEX_AUTH) {
            model.replace("/openai/", "")
        } else model
    }

    private fun thinkingLevel(
        thinking: ProviderThinkingConfig?,
        geminiLevel: String? = null
    ): String? {
        if (thinking?.enabled == false) return "off"
        val value = (geminiLevel?.trim()?.takeIf { it.isNotEmpty() } ?: thinking?.effort)?.lowercase()
        return if (value in listOf("minimal", "low", "medium", "high", "xhigh", "max")) value else null
    }

    private fun normalizedBaseURL(value: String): String {
        var result = value.trim().trimEnd('/')
        for (suffix in listOf("/chat/completions", "/responses")) {
            if (result.endsWith(suffix)) {
                result = result.substring(0, result.length - suffix.length)
            }
        }
        return result
    }

    private fun normalizedAnthropicBaseURL(value: String): String {
        var result = normalizedBaseURL(value)
        for (suffix in listOf("/v1/messages", "/messages", "/v1")) {
            if (result.endsWith(suffix)) {
                result = result.substring(0, result.length - suffix.length)
                break
            }
        }
        return result
    }

    private fun modelsDevFieldKey(providerID: String, fieldName: String): String {
        val provider = providerID.lowercase().replace(Regex("[^a-z0-9._-]+"), "_")
        val field = fieldName.uppercase().replace(Regex("[^A-Z0-9_]+"), "_")
        return "models_dev_${provider}_$field"
    }

    private fun migrateLegacyCredentialIfNeeded(providerID: String, destinationKey: String) {
        if (!securePreferences.readSecret(destinationKey).isNullOrBlank()) return
        val legacyVal = when (providerID.lowercase()) {
            "openai" -> securePreferences.getOpenAiApiKey()
            "opencode-go" -> securePreferences.getOpenCodeGoApiKey()
            "cline-pass" -> securePreferences.getClinePassApiKey()
            "alibaba-coding-plan" -> securePreferences.getAlibabaCodingPlanApiKey()
            "zai-coding-plan" -> securePreferences.getZaiApiKey()
            "minimax" -> securePreferences.getMiniMaxApiKey()
            else -> null
        }?.trim()?.takeIf { it.isNotEmpty() }

        if (legacyVal != null) {
            securePreferences.saveSecret(destinationKey, legacyVal)
        }
    }

    private fun knownModelsDevBaseURL(providerID: String): String? {
        return mapOf(
            "openai" to "https://api.openai.com/v1",
            "anthropic" to "https://api.anthropic.com",
            "xai" to "https://api.x.ai/v1",
            "groq" to "https://api.groq.com/openai/v1",
            "mistral" to "https://api.mistral.ai/v1",
            "togetherai" to "https://api.together.xyz/v1",
            "cerebras" to "https://api.cerebras.ai/v1",
            "deepinfra" to "https://api.deepinfra.com/v1/openai",
            "perplexity" to "https://api.perplexity.ai",
            "cohere" to "https://api.cohere.ai/compatibility/v1",
            "vercel" to "https://ai-gateway.vercel.sh/v1",
            "v0" to "https://api.v0.dev/v1",
            "venice" to "https://api.venice.ai/api/v1",
            "aihubmix" to "https://aihubmix.com/v1"
        )[providerID.lowercase()]
    }
}
