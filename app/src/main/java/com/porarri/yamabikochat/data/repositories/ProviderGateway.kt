package com.porarri.yamabikochat.data.repositories

import com.porarri.yamabikochat.data.auth.CodexAuthRepository
import com.porarri.yamabikochat.data.auth.SuperGrokAuthRepository
import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.data.local.ToolActivityPayload
import com.porarri.yamabikochat.data.model.LLMProvider
import com.porarri.yamabikochat.data.model.ProviderClientError
import com.porarri.yamabikochat.data.model.ProviderRequest
import com.porarri.yamabikochat.data.model.ProviderResponse
import com.porarri.yamabikochat.data.model.ProviderStreamEvent
import com.porarri.yamabikochat.data.model.ProviderThinkingConfig
import com.porarri.yamabikochat.data.modelsdev.ModelsDevCatalogRepository
import com.porarri.yamabikochat.data.modelsdev.ModelsDevReasoningPreference
import com.porarri.yamabikochat.data.modelsdev.ProviderReference
import com.porarri.yamabikochat.data.remote.OpenCodeGoModelCatalog
import com.porarri.yamabikochat.data.remote.OpenRouterModelService
import com.porarri.yamabikochat.data.tools.LocalToolRegistry
import com.porarri.yamabikochat.data.tools.search.FetchUrlTool
import com.porarri.yamabikochat.data.tools.search.WebSearchTool
import com.porarri.yamabikochat.pi.PiAgentConfiguration
import com.porarri.yamabikochat.pi.PiAgentRuntime
import com.porarri.yamabikochat.pi.PiCatalogModelContract
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import com.porarri.yamabikochat.utils.SecurePreferencesManager
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.catch
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
    private val openRouterModelService: OpenRouterModelService? = null,
    private val localTools: LocalToolRegistry = LocalToolRegistry(listOf(WebSearchTool(), FetchUrlTool())),
    private val piStream: PiAgentStreamFn? = null,
    private val piRuntime: PiAgentRuntime? = null
) {
    suspend fun generate(request: ProviderRequest, provider: LLMProvider): ProviderResponse {
        return generate(request, provider.rawValue)
    }

    suspend fun generate(
        request: ProviderRequest,
        providerID: String,
        onStreamEvent: ((ProviderStreamEvent) -> Unit)? = null
    ): ProviderResponse {
        val streamFlow = stream(request, providerID)
        var completed: ProviderResponse? = null
        var text = ""
        var reasoning = ""
        var toolActivity = ToolActivityPayload()

        streamFlow.collect { event ->
            onStreamEvent?.invoke(event)
            when (event) {
                ProviderStreamEvent.AnswerStart -> text = ""
                is ProviderStreamEvent.TextDelta -> text += event.delta
                is ProviderStreamEvent.ReasoningDelta -> reasoning += event.delta
                is ProviderStreamEvent.ToolActivity -> toolActivity = toolActivity.applying(event.event)
                is ProviderStreamEvent.Completed -> completed = event.response
            }
        }

        val response = completed ?: throw ProviderClientError.ParseFailure("Pi agent stream ended without completion")
        if (response.text.isEmpty()) response.text = text
        if (response.reasoningSummary == null && reasoning.trim().isNotEmpty()) {
            response.reasoningSummary = reasoning.trim()
        }
        response.providerTranscript?.let {
            toolActivity = toolActivity.copy(providerTranscript = it)
        }
        if (toolActivity.steps.isNotEmpty() || toolActivity.providerTranscript.isNotEmpty()) {
            response.toolActivity = toolActivity
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
            "Pi agent configuration ready provider=${piConfiguration.provider} model=${piConfiguration.model} contractVersion=${piConfiguration.contractVersion}"
        )

        val streamExecutor = piStream ?: { req, cfg, tools ->
            val runtime = piRuntime ?: throw ProviderClientError.ParseFailure("Pi runtime not configured")
            runtime.stream(req, cfg, tools)
        }

        return streamExecutor(request, piConfiguration, localTools).catch { error ->
            DiagnosticsLogger.log(
                "Pi agent stream failed requestId=$requestId provider=$normalizedProvider model=${request.model}",
                error
            )
            throw error
        }
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

        var piProvider = provider.rawValue.lowercase()
        var apiKey: String
        var headers: MutableMap<String, String> = mutableMapOf()
        var mcpAuthorizationToken: String? = null

        when (provider) {
            LLMProvider.GEMINI -> {
                piProvider = "google"
                apiKey = credential(provider)
            }
            LLMProvider.OPENROUTER -> {
                piProvider = "openrouter"
                apiKey = credential(provider)
                headers["HTTP-Referer"] = "https://yamabikochat.app"
                headers["X-Title"] = "YamabikoChat Android"
            }
            LLMProvider.OPENAI -> {
                piProvider = "openai"
                apiKey = credential(provider)
            }
            LLMProvider.OPENAI_COMPAT -> {
                throw ProviderClientError.UnsupportedModel(provider.rawValue, request.model)
            }
            LLMProvider.MINIMAX -> {
                piProvider = "minimax"
                apiKey = credential(provider)
            }
            LLMProvider.ZAI -> {
                piProvider = "zai"
                apiKey = credential(provider)
            }
            LLMProvider.CLINEPASS -> {
                throw ProviderClientError.UnsupportedModel(provider.rawValue, request.model)
            }
            LLMProvider.ALIBABA_CODING_PLAN -> {
                piProvider = "qwen-token-plan"
                apiKey = credential(provider)
                if (request.tools.any { it.type == "mcp_toolset" }) {
                    headers["anthropic-beta"] = "mcp-client-2025-11-20"
                    mcpAuthorizationToken = securePreferences.getAlibabaMcpAuthorizationToken()?.trim()
                }
            }
            LLMProvider.OPENCODE_GO -> {
                piProvider = "opencode-go"
                apiKey = credential(provider)
            }
            LLMProvider.CODEX_AUTH -> {
                val auth = codexAuthRepository?.getBearerToken()
                    ?: throw ProviderClientError.MissingCredential(LLMProvider.CODEX_AUTH.rawValue)
                piProvider = "openai-codex"
                apiKey = auth.token
                headers["originator"] = "codex_cli_rs"
                if (!auth.accountId.isNullOrBlank()) {
                    headers["ChatGPT-Account-ID"] = auth.accountId
                }
            }
            LLMProvider.SUPERGROK -> {
                val auth = superGrokAuthRepository?.getBearerToken()
                    ?: throw ProviderClientError.MissingCredential(LLMProvider.SUPERGROK.rawValue)
                piProvider = "xai-oauth"
                apiKey = auth.token
            }
            LLMProvider.APPLE_INTELLIGENCE -> {
                throw ProviderClientError.UnsupportedModel("APPLE_INTELLIGENCE", request.model)
            }
        }

        val openRouterModel = if (provider == LLMProvider.OPENROUTER) {
            openRouterModelService?.getAvailableModels()?.firstOrNull { it.id == request.model }
        } else null
        val catalogContract = openRouterModel?.let { model ->
            PiCatalogModelContract(
                npm = "@openrouter/ai-sdk-provider",
                api = "https://openrouter.ai/api/v1",
                provenance = "official_provider_catalog",
                toolCall = model.supportsTools,
                name = model.name,
                reasoning = model.supportsReasoning,
                input = model.inputModalities,
                contextWindow = model.contextLength.toLong(),
                maxTokens = model.maxCompletionTokens?.toLong()
            )
        }
        return PiAgentConfiguration(
            provider = piProvider,
            model = normalizedModel(request.model, provider),
            apiKey = apiKey,
            headers = headers,
            catalogContract = catalogContract,
            thinkingLevel = thinkingLevel(
                request.thinking,
                geminiLevel = if (provider == LLMProvider.GEMINI) request.metadata["geminiThinkingLevel"] else null
            ),
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

        val env = catalog.env.mapNotNull { field ->
            val key = modelsDevFieldKey(providerID, field)
            migrateLegacyCredentialIfNeeded(providerID, key)
            securePreferences.readSecret(key)?.trim()?.takeIf { it.isNotEmpty() }?.let { field to it }
        }.toMap()
        if (env.isEmpty()) throw ProviderClientError.MissingCredential(providerID)

        val normalizedModel = if (providerID.equals("opencode-go", ignoreCase = true)) {
            OpenCodeGoModelCatalog.normalizedModelId(request.model)
        } else request.model

        return PiAgentConfiguration(
            provider = providerID,
            model = normalizedModel,
            apiKey = null,
            env = env,
            catalogContract = PiCatalogModelContract(
                npm = model.providerContract?.npm,
                api = model.providerContract?.api,
                shape = model.providerContract?.shape,
                provenance = model.providerContract?.provenance,
                toolCall = model.toolCall,
                name = model.name,
                reasoning = model.reasoning,
                input = model.inputModalities,
                contextWindow = model.limits.context,
                maxTokens = model.limits.output
            ),
            thinkingLevel = thinkingLevel(request.thinking),
        )
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
        return when (provider) {
            LLMProvider.CODEX_AUTH -> model.replace("/openai/", "")
            LLMProvider.OPENCODE_GO -> OpenCodeGoModelCatalog.normalizedModelId(model)
            else -> model
        }
    }

    private fun thinkingLevel(
        thinking: ProviderThinkingConfig?,
        geminiLevel: String? = null
    ): String? {
        if (thinking?.enabled == false) return "off"
        val value = (geminiLevel?.trim()?.takeIf { it.isNotEmpty() } ?: thinking?.effort)?.lowercase()
        return if (value in listOf("minimal", "low", "medium", "high", "xhigh", "max")) value else null
    }


    private fun modelsDevFieldKey(providerID: String, fieldName: String): String =
        ModelsDevReasoningPreference.fieldKey(providerID, fieldName)

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

}
