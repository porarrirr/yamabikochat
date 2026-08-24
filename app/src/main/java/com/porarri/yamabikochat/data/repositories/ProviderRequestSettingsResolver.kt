package com.porarri.yamabikochat.data.repositories

import com.porarri.yamabikochat.data.local.Settings
import com.porarri.yamabikochat.data.model.LLMProvider
import com.porarri.yamabikochat.data.model.ProviderClientError
import com.porarri.yamabikochat.data.model.ProviderMaxPriceConfig
import com.porarri.yamabikochat.data.model.ProviderRoutingConfig
import com.porarri.yamabikochat.data.model.ProviderThinkingConfig
import com.porarri.yamabikochat.data.model.ProviderTool
import com.porarri.yamabikochat.data.modelsdev.ProviderReference
import com.porarri.yamabikochat.data.modelsdev.ModelsDevCatalogRepository
import com.porarri.yamabikochat.data.remote.OpenRouterModelEndpointOptions
import com.porarri.yamabikochat.data.remote.OpenRouterModelService
import com.porarri.yamabikochat.data.remote.SuperGrokModelCatalog
import com.porarri.yamabikochat.data.skills.AgentSkillRepository
import com.porarri.yamabikochat.data.skills.AgentSkillTools
import com.porarri.yamabikochat.data.tools.LocalToolRegistry
import com.porarri.yamabikochat.data.tools.search.FetchUrlTool
import com.porarri.yamabikochat.data.tools.search.WebSearchTool
import com.porarri.yamabikochat.data.tools.editor.StrReplaceEditorTool
import com.porarri.yamabikochat.utils.CodexModelPresets
import com.porarri.yamabikochat.utils.DiagnosticsLogger
import com.porarri.yamabikochat.utils.ModelUtils

sealed interface ProviderRequestToolScope {
    object All : ProviderRequestToolScope
    object ProviderOnly : ProviderRequestToolScope
    data class FusionPanel(val allowWebSearch: Boolean) : ProviderRequestToolScope
    object None : ProviderRequestToolScope

    val allowsProviderTools: Boolean
        get() = when (this) {
            is All, is ProviderOnly, is FusionPanel -> true
            is None -> false
        }

    val allowsClientWebSearch: Boolean
        get() = when (this) {
            is All -> true
            is FusionPanel -> allowWebSearch
            is ProviderOnly, is None -> false
        }

    val allowsNativeWebSearch: Boolean
        get() = when (this) {
            is All, is ProviderOnly -> true
            is FusionPanel -> allowWebSearch
            is None -> false
        }

    val allowsAgentSkills: Boolean
        get() = when (this) {
            is All, is FusionPanel -> true
            is ProviderOnly, is None -> false
        }
}

data class ProviderRequestResolvedSettings(
    val tools: List<ProviderTool>,
    val thinking: ProviderThinkingConfig?,
    val routing: ProviderRoutingConfig?,
    val metadata: Map<String, String>
)

class ProviderRequestSettingsResolver(
    private val modelService: OpenRouterModelService,
    private val skillRepository: AgentSkillRepository,
    private val modelsDevCatalogRepository: ModelsDevCatalogRepository? = null,
    private val localToolRegistry: LocalToolRegistry = LocalToolRegistry(
        listOf(WebSearchTool(), FetchUrlTool())
    ),
    private val modelsDevReasoningEffort: (String, String) -> String? = { _, _ -> null }
) {
    suspend fun resolve(
        settings: Settings,
        provider: String,
        model: String,
        context: Settings.ReasoningContext = Settings.ReasoningContext.DEFAULT,
        toolScope: ProviderRequestToolScope = ProviderRequestToolScope.All
    ): ProviderRequestResolvedSettings {
        val supportsClientTools = supportsClientTools(provider, model)
        return ProviderRequestResolvedSettings(
            tools = toolsForProvider(
                settings = settings,
                provider = provider,
                model = model,
                context = context,
                toolScope = toolScope
            ),
            thinking = thinkingConfigForProvider(
                settings = settings,
                provider = provider,
                model = model,
                context = context
            ),
            routing = providerPreferencesForProvider(
                settings = settings,
                provider = provider,
                model = model
            ),
            metadata = metadataForProvider(
                settings = settings,
                provider = provider,
                model = model,
                context = context,
                toolScope = toolScope
            ) + ("supportsClientTools" to supportsClientTools.toString())
        )
    }

    private fun toolsForProvider(
        settings: Settings,
        provider: String,
        model: String,
        context: Settings.ReasoningContext,
        toolScope: ProviderRequestToolScope
    ): List<ProviderTool> {
        if (!toolScope.allowsProviderTools) return emptyList()

        val tools = mutableListOf<ProviderTool>()
        when (provider.trim().uppercase()) {
            "GEMINI" -> {
                if (toolScope.allowsNativeWebSearch && settings.isGoogleSearchEnabledFor("GEMINI", context)) {
                    tools.add(ProviderTool(type = "google_search"))
                }
                if (settings.isCodeExecutionEnabledFor("GEMINI", context)) {
                    tools.add(ProviderTool(type = "code_execution"))
                }
                if (settings.isUrlContextEnabledFor("GEMINI", context)) {
                    tools.add(ProviderTool(type = "url_context"))
                }
                if (settings.isGoogleMapsEnabledFor("GEMINI", context)) {
                    tools.add(ProviderTool(type = "google_maps"))
                }
                if (settings.isComputerUseEnabledFor("GEMINI", context)) {
                    tools.add(ProviderTool(type = "computer_use"))
                }
                val declarations = settings.geminiFunctionDeclarations.trim()
                if (declarations.isNotEmpty()) {
                    tools.add(ProviderTool(type = "function_declarations", payload = mapOf("json" to declarations)))
                }
            }
            "OPENROUTER" -> {
                if (toolScope.allowsNativeWebSearch && settings.isGoogleSearchEnabledFor("OPENROUTER", context)) {
                    tools.add(ProviderTool(type = "google_search"))
                }
                if (settings.isCodeExecutionEnabledFor("OPENROUTER", context)) {
                    tools.add(ProviderTool(type = "code_execution"))
                }
            }
            "ALIBABA_CODING_PLAN" -> {
                if (settings.alibabaMcpEnabled) {
                    val serverURL = settings.resolvedAlibabaMcpServerUrl()
                    if (!serverURL.isNullOrBlank()) {
                        val payload = mutableMapOf(
                            "server_url" to serverURL,
                            "server_name" to settings.resolvedAlibabaMcpServerName()
                        )
                        val allowed = settings.alibabaMcpAllowedToolsList()
                        if (allowed.isNotEmpty()) {
                            payload["allowed_tools"] = allowed.joinToString(",")
                        }
                        tools.add(ProviderTool(type = "mcp_toolset", payload = payload))
                    } else {
                        DiagnosticsLogger.log("Alibaba MCP enabled but server URL is invalid; skipping MCP toolset")
                    }
                }
            }
        }

        val supportsClientWebSearch = supportsClientTools(provider, model)
        if (toolScope.allowsClientWebSearch && settings.clientWebSearchToolEnabled && supportsClientWebSearch) {
            tools.addAll(localToolRegistry.definitions
                .filter { it.name == WebSearchTool.NAME || it.name == FetchUrlTool.NAME }
                .map { it.providerTool })
        }
        if (toolScope is ProviderRequestToolScope.All &&
            context in setOf(Settings.ReasoningContext.DEFAULT, Settings.ReasoningContext.DUAL_A, Settings.ReasoningContext.DUAL_B) &&
            supportsClientWebSearch) {
            localToolRegistry.definitions.firstOrNull { it.name == StrReplaceEditorTool.NAME }
                ?.let { tools.add(it.providerTool) }
        }
        if (toolScope.allowsAgentSkills && supportsClientWebSearch) {
            tools.addAll(AgentSkillTools.definitions(skillRepository).map { it.providerTool })
        }

        return tools
    }

    private fun supportsClientTools(provider: String, model: String): Boolean {
        val reference = ProviderReference(provider)
        if (reference.isModelsDev) {
            return modelsDevCatalogRepository?.provider(reference)
                ?.models?.firstOrNull { it.id == model }?.toolCall == true
        }
        return LLMProvider.fromRawOrDefault(provider).supportsClientWebSearchTool
    }

    private fun metadataForProvider(
        settings: Settings,
        provider: String,
        model: String,
        context: Settings.ReasoningContext,
        toolScope: ProviderRequestToolScope
    ): Map<String, String> {
        return when (provider.trim().uppercase()) {
            "CODEX_AUTH" -> {
                val summary = settings.codexReasoningSummary.ifBlank { "auto" }.lowercase()
                val summaryToSend = if (settings.codexReasoningEnabled && summary != "none" &&
                    (settings.codexSupportsReasoningSummaries || CodexModelPresets.supportsReasoningSummary(model))) {
                    summary
                } else null

                val verbosity = settings.codexVerbosity.ifBlank { "medium" }.lowercase()
                val verbosityToSend = if (CodexModelPresets.supportsTextVerbosity(model)) verbosity else null
                val webSearchEnabled = toolScope.allowsNativeWebSearch && settings.codexWebSearchEnabled

                val metadata = mutableMapOf(
                    "codexUserAgentPreset" to settings.codexUserAgentPreset.ifBlank { "android" },
                    "codexWebSearchEnabled" to if (webSearchEnabled) "true" else "false",
                    "codexWebSearchContextSize" to settings.codexWebSearchContextSize.ifBlank { "medium" },
                    "codexPromptCacheEnabled" to if (settings.codexPromptCacheEnabled) "true" else "false",
                    "codexPromptCacheMinLength" to maxOf(0, settings.codexPromptCacheMinLength).toString(),
                    "codexPromptCacheType" to settings.codexPromptCacheType.ifBlank { "ephemeral" }
                )
                if (summaryToSend != null) metadata["codexReasoningSummary"] = summaryToSend
                if (verbosityToSend != null) metadata["codexVerbosity"] = verbosityToSend
                metadata
            }
            "GEMINI" -> {
                val overrides = settings.thinkingOverride(context)
                val level = effectiveGeminiThinkingLevel(
                    settings = settings,
                    model = model,
                    enabledOverride = overrides.enabled,
                    levelOverride = overrides.level
                ).orEmpty()
                mapOf(
                    "geminiResponseMimeType" to settings.geminiResponseMimeType,
                    "geminiResponseJSONSchema" to settings.geminiResponseJsonSchema,
                    "geminiFunctionDeclarations" to settings.geminiFunctionDeclarations,
                    "geminiThinkingLevel" to level
                )
            }
            else -> emptyMap()
        }
    }

    private fun thinkingConfigForProvider(
        settings: Settings,
        provider: String,
        model: String,
        context: Settings.ReasoningContext
    ): ProviderThinkingConfig? {
        val reference = ProviderReference(provider)
        if (reference.isModelsDev) {
            return modelsDevThinkingConfig(reference.modelsDevId.orEmpty(), model)
        }
        val overrides = settings.thinkingOverride(context)
        return when (provider.trim().uppercase()) {
            "OPENROUTER" -> buildOpenRouterThinkingConfig(settings, model, context)
            "CODEX_AUTH" -> {
                val enabled = overrides.enabled ?: settings.codexReasoningEnabled
                val baseEffort = settings.codexReasoningEffort.ifBlank { "medium" }
                val overrideEffort = overrides.codexEffort?.ifBlank { baseEffort }
                ProviderThinkingConfig(
                    enabled = null,
                    budget = null,
                    effort = if (enabled) (overrideEffort ?: baseEffort) else "none",
                    includeThoughts = true,
                    exclude = null
                )
            }
            "SUPERGROK" -> {
                val enabled = overrides.enabled ?: settings.superGrokReasoningEnabled
                val baseEffort = settings.superGrokReasoningEffort.ifBlank { "medium" }
                val overrideEffort = overrides.codexEffort?.ifBlank { baseEffort }
                val rawEffort = if (enabled) (overrideEffort ?: baseEffort) else "none"
                val effort = if (rawEffort == "none") {
                    "none"
                } else {
                    val norm = rawEffort.lowercase()
                    if (norm in listOf("low", "medium", "high")) norm else "medium"
                }
                val catalog = SuperGrokModelCatalog.modelFor(model)
                if (catalog != null && !catalog.supportsReasoning) return null
                ProviderThinkingConfig(
                    enabled = null,
                    budget = null,
                    effort = effort,
                    includeThoughts = true,
                    exclude = null
                )
            }
            "GEMINI" -> {
                val enabled = overrides.enabled ?: settings.geminiThinkingEnabled
                val budget = overrides.budget ?: settings.geminiThinkingBudget
                if (ModelUtils.isThinkingLevelSupported(model)) {
                    return ProviderThinkingConfig(
                        enabled = null,
                        budget = null,
                        effort = null,
                        includeThoughts = true,
                        exclude = null
                    )
                }
                val calculatedBudget = ModelUtils.calculateEffectiveThinkingBudget(
                    model = model,
                    userThinkingEnabled = enabled,
                    userThinkingBudget = budget
                ) ?: return null

                ProviderThinkingConfig(
                    enabled = null,
                    budget = calculatedBudget,
                    effort = null,
                    includeThoughts = true,
                    exclude = null
                )
            }
            else -> null
        }
    }

    private fun modelsDevThinkingConfig(providerId: String, model: String): ProviderThinkingConfig? {
        val catalogModel = modelsDevCatalogRepository
            ?.provider(ProviderReference.modelsDev(providerId))
            ?.models
            ?.firstOrNull { it.id == model }
        val supported = catalogModel?.supportedReasoningEfforts.orEmpty()
        val saved = modelsDevReasoningEffort(providerId, model)
            ?.trim()
            ?.lowercase()
            .orEmpty()
        if (saved.isEmpty() || saved !in supported) return null
        return ProviderThinkingConfig(
            enabled = null,
            budget = null,
            effort = saved,
            includeThoughts = true,
            exclude = null
        )
    }

    private fun buildOpenRouterThinkingConfig(
        settings: Settings,
        model: String,
        context: Settings.ReasoningContext
    ): ProviderThinkingConfig? {
        val overrides = settings.openRouterOverride(context)
        val reasoningExclude = overrides.exclude ?: settings.openRouterReasoningExclude
        val requestedThinkingEnabled = overrides.enabled ?: settings.openRouterThinkingEnabled
        val modelInfo = modelService.getModelById(model) ?: run {
            if (requestedThinkingEnabled) {
                throw ProviderClientError.ParseFailure("OpenRouter reasoning capabilities are unavailable for model: $model")
            }
            return null
        }
        val capabilities = modelInfo.reasoning ?: run {
            if (requestedThinkingEnabled) {
                throw ProviderClientError.ParseFailure("OpenRouter model does not expose reasoning capabilities: $model")
            }
            return null
        }

        val thinkingEnabled = capabilities.mandatory || requestedThinkingEnabled
        val reasoningMode = (overrides.mode ?: settings.openRouterReasoningMode).trim().lowercase()
        val reasoningEffort = (overrides.effort ?: settings.openRouterReasoningEffort).trim().lowercase()
        val thinkingBudget = maxOf(0, overrides.budget ?: settings.openRouterThinkingBudget)
        val includeThoughts = !reasoningExclude

        if (!thinkingEnabled) {
            return ProviderThinkingConfig(
                enabled = false,
                budget = null,
                effort = null,
                includeThoughts = includeThoughts,
                exclude = true
            )
        }

        val supportedModes = listOf("auto") +
                (if (capabilities.selectableEfforts.isNotEmpty()) listOf("effort") else emptyList()) +
                (if (capabilities.supportsMaxTokens) listOf("budget") else emptyList())
        val mode = if (reasoningMode in supportedModes) reasoningMode else "auto"
        val budget = if (mode == "budget" && thinkingBudget > 0) thinkingBudget else null
        val effort: String?
        if (mode == "effort") {
            val supportedEfforts = capabilities.selectableEfforts
            effort = when {
                reasoningEffort in supportedEfforts -> reasoningEffort
                capabilities.defaultEffort?.lowercase() in supportedEfforts -> capabilities.defaultEffort?.lowercase()
                supportedEfforts.isNotEmpty() -> supportedEfforts.first()
                else -> throw ProviderClientError.ParseFailure("OpenRouter reasoning effort is unavailable for model: $model")
            }
        } else {
            effort = null
        }

        val enabled: Boolean? = if (mode == "auto" || (budget == null && effort == null)) true else null
        val exclude: Boolean? = if (reasoningExclude) true else null

        if (budget == null && effort == null && enabled == null && exclude == null) {
            return null
        }

        return ProviderThinkingConfig(
            enabled = enabled,
            budget = budget,
            effort = effort,
            includeThoughts = includeThoughts,
            exclude = exclude
        )
    }

    private suspend fun providerPreferencesForProvider(
        settings: Settings,
        provider: String,
        model: String
    ): ProviderRoutingConfig? {
        if (provider.trim().uppercase() != "OPENROUTER") return null

        val preferredProviders = settings.getPreferredProvidersList()
        val requestedQuantizations = normalizedOpenRouterSlugs(settings.getSelectedQuantizationsList())
        var providers: List<String> = emptyList()
        var quantizations: List<String> = emptyList()

        if (preferredProviders.isNotEmpty() || requestedQuantizations.isNotEmpty()) {
            val endpointOptions: OpenRouterModelEndpointOptions
            try {
                endpointOptions = modelService.getModelEndpointOptions(model)
            } catch (e: Exception) {
                DiagnosticsLogger.log("OpenRouter endpoint restriction validation failed model=$model", e)
                throw ProviderClientError.ParseFailure(
                    "OpenRouter endpoint restrictions could not be validated for $model: ${e.message}"
                )
            }

            val availableProviderSet = endpointOptions.providerEndpoints.map { it.tag }.toSet()
            val invalidProviders = preferredProviders.filter { it !in availableProviderSet }
            if (invalidProviders.isNotEmpty()) {
                throw ProviderClientError.ParseFailure(
                    "Unavailable OpenRouter endpoint tag(s) for $model: ${invalidProviders.joinToString(", ")}"
                )
            }
            providers = preferredProviders

            val availableQuantizationSet = endpointOptions.quantizations.toSet()
            val invalidQuantizations = requestedQuantizations.filter { it !in availableQuantizationSet }
            if (invalidQuantizations.isNotEmpty()) {
                throw ProviderClientError.ParseFailure(
                    "Unavailable OpenRouter quantization(s) for $model: ${invalidQuantizations.joinToString(", ")}"
                )
            }
            quantizations = requestedQuantizations
        }

        val hasRoutingProviders = providers.isNotEmpty()
        if (!hasRoutingProviders && quantizations.isEmpty() && settings.maxPricePerMillionTokens <= 0.0) {
            return null
        }

        val onlyProviders = if (!settings.allowFallbacks && hasRoutingProviders) providers else null
        val orderProviders = if (onlyProviders == null && hasRoutingProviders) providers else null
        val maxPrice = if (settings.maxPricePerMillionTokens > 0.0) {
            ProviderMaxPriceConfig(
                prompt = settings.maxPricePerMillionTokens,
                completion = settings.maxPricePerMillionTokens,
                request = null,
                image = null,
                audio = null
            )
        } else null
        val trimmedSort = settings.providerSort.trim().lowercase()

        DiagnosticsLogger.log("OpenRouter provider routing applied model=$model providers=${providers.joinToString(",")}")

        return ProviderRoutingConfig(
            order = orderProviders,
            allowFallbacks = if (hasRoutingProviders) settings.allowFallbacks else null,
            requireParameters = if (settings.requireParameters) true else null,
            dataCollection = null,
            quantizations = quantizations.ifEmpty { null },
            maxPrice = maxPrice,
            only = onlyProviders,
            ignore = null,
            sort = trimmedSort.ifEmpty { null }
        )
    }

    private fun normalizedOpenRouterSlugs(values: List<String>): List<String> {
        val seen = mutableSetOf<String>()
        return values.map { it.trim().lowercase() }.filter { it.isNotEmpty() && seen.add(it) }
    }

    private fun effectiveGeminiThinkingLevel(
        settings: Settings,
        model: String,
        enabledOverride: Boolean?,
        levelOverride: String?
    ): String? {
        if (!ModelUtils.isThinkingLevelSupported(model)) return null

        val defaultLevel = ModelUtils.getDefaultThinkingLevel(model)
        val levelSource = levelOverride ?: settings.geminiThinkingLevel
        var normalized = ModelUtils.normalizeThinkingLevel(model, levelSource) ?: defaultLevel
        val enabled = enabledOverride ?: settings.geminiThinkingEnabled
        if (!ModelUtils.isThinkingAlwaysOn(model) && !enabled) {
            val minimal = ModelUtils.getMinimalThinkingLevel(model)
            if (minimal != null) normalized = minimal
        }
        return normalized
    }
}
