import Foundation

enum ProviderRequestToolScope: Sendable, Equatable {
    case all
    case providerOnly
    case fusionPanel(allowWebSearch: Bool)
    case none

    var allowsProviderTools: Bool {
        switch self {
        case .all, .providerOnly, .fusionPanel:
            return true
        case .none:
            return false
        }
    }

    var allowsClientWebSearch: Bool {
        switch self {
        case .all:
            return true
        case let .fusionPanel(allowWebSearch):
            return allowWebSearch
        case .providerOnly, .none:
            return false
        }
    }

    var allowsNativeWebSearch: Bool {
        switch self {
        case .all, .providerOnly:
            return true
        case let .fusionPanel(allowWebSearch):
            return allowWebSearch
        case .none:
            return false
        }
    }

    var allowsAgentSkills: Bool {
        switch self {
        case .all, .fusionPanel:
            return true
        case .providerOnly, .none:
            return false
        }
    }
}

struct ProviderRequestResolvedSettings: Sendable, Equatable {
    var tools: [ProviderTool]
    var thinking: ProviderThinkingConfig?
    var routing: ProviderRoutingConfig?
    var metadata: [String: String]
}

/// Resolves the provider-global settings used by every chat execution mode.
/// Mode-specific overrides are applied first; unset overrides inherit the provider globals.
final class ProviderRequestSettingsResolver {
    private let modelService: OpenRouterModelService
    private let localToolRegistry: LocalToolRegistry
    private let skillRepository: AgentSkillRepository

    init(
        modelService: OpenRouterModelService,
        skillRepository: AgentSkillRepository = AgentSkillRepository(),
        localToolRegistry: LocalToolRegistry = LocalToolRegistry(
            executors: [WebSearchTool(), FetchUrlTool()]
        )
    ) {
        self.modelService = modelService
        self.skillRepository = skillRepository
        self.localToolRegistry = localToolRegistry
    }

    func resolve(
        settings: AppSettings,
        provider: String,
        model: String,
        context: AppSettings.ReasoningContext = .default,
        toolScope: ProviderRequestToolScope = .all
    ) async throws -> ProviderRequestResolvedSettings {
        var metadata = metadataForProvider(
            settings: settings,
            provider: provider,
            model: model,
            context: context
        )
        if let contextWindow = modelService.resolveContextLength(modelID: model, providerID: provider) {
            metadata["contextWindow"] = String(contextWindow)
        }
        return ProviderRequestResolvedSettings(
            tools: toolsForProvider(
                settings: settings,
                provider: provider,
                context: context,
                toolScope: toolScope
            ),
            thinking: try thinkingConfigForProvider(
                settings: settings,
                provider: provider,
                model: model,
                context: context
            ),
            routing: try await providerPreferencesForProvider(
                settings: settings,
                provider: provider,
                model: model
            ),
            metadata: metadata
        )
    }

    private func toolsForProvider(
        settings: AppSettings,
        provider: String,
        context: AppSettings.ReasoningContext,
        toolScope: ProviderRequestToolScope
    ) -> [ProviderTool] {
        guard toolScope.allowsProviderTools else { return [] }

        let overrides = settings.toolOverride(for: context)
        var tools: [ProviderTool]
        switch provider.uppercased() {
        case "GEMINI":
            tools = []
            if toolScope.allowsNativeWebSearch,
               overrides.googleSearch ?? settings.geminiGoogleSearchEnabled {
                tools.append(ProviderTool(type: "google_search", payload: [:]))
            }
            if overrides.codeExecution ?? settings.geminiCodeExecutionEnabled {
                tools.append(ProviderTool(type: "code_execution", payload: [:]))
            }
            if overrides.urlContext ?? settings.geminiURLContextEnabled {
                tools.append(ProviderTool(type: "url_context", payload: [:]))
            }
            if overrides.googleMaps ?? settings.geminiGoogleMapsEnabled {
                tools.append(ProviderTool(type: "google_maps", payload: [:]))
            }
            if overrides.computerUse ?? settings.geminiComputerUseEnabled {
                tools.append(ProviderTool(type: "computer_use", payload: [:]))
            }
            let declarations = settings.geminiFunctionDeclarations.trimmingCharacters(in: .whitespacesAndNewlines)
            if !declarations.isEmpty {
                tools.append(ProviderTool(type: "function_declarations", payload: ["json": declarations]))
            }
        case "OPENROUTER":
            tools = []
            if toolScope.allowsNativeWebSearch,
               overrides.googleSearch ?? settings.openRouterGoogleSearchEnabled {
                tools.append(ProviderTool(type: "google_search", payload: [:]))
            }
            if overrides.codeExecution ?? settings.openRouterCodeExecutionEnabled {
                tools.append(ProviderTool(type: "code_execution", payload: [:]))
            }
        case "ALIBABA_CODING_PLAN":
            tools = []
            if settings.alibabaMCPEnabled {
                if let serverURL = settings.resolvedAlibabaMCPServerURL() {
                    var payload: [String: String] = [
                        "server_url": serverURL,
                        "server_name": settings.resolvedAlibabaMCPServerName()
                    ]
                    let allowedTools = settings.alibabaMCPAllowedToolsList()
                    if !allowedTools.isEmpty {
                        payload["allowed_tools"] = allowedTools.joined(separator: ",")
                    }
                    tools.append(ProviderTool(type: "mcp_toolset", payload: payload))
                } else {
                    DiagnosticsLogger.log(
                        "Alibaba MCP enabled but server URL is invalid; skipping MCP toolset",
                        level: .warning,
                        category: .settings
                    )
                }
            }
        default:
            tools = []
        }

        let supportsClientWebSearch = ProviderReference(persistedID: provider).isModelsDev
            || LLMProvider(rawOrDefault: provider).supportsClientWebSearchTool
        if toolScope.allowsClientWebSearch,
           settings.clientWebSearchToolEnabled,
           supportsClientWebSearch {
            tools.append(contentsOf: localToolRegistry.definitions.map(\.providerTool))
        }
        if toolScope.allowsAgentSkills, supportsClientWebSearch {
            tools.append(contentsOf: AgentSkillTools.definitions(repository: skillRepository).map(\.providerTool))
        }
        return deduplicatedFunctionTools(from: tools)
    }

    /// Provider APIs reject duplicate function tool names. The resolver composes
    /// tools from several sources, so keep function names unique as a final guard.
    private func deduplicatedFunctionTools(from tools: [ProviderTool]) -> [ProviderTool] {
        var seen = Set<String>()
        var result: [ProviderTool] = []
        result.reserveCapacity(tools.count)
        for tool in tools {
            guard tool.type == "function", let name = tool.payload["name"], !name.isEmpty else {
                result.append(tool)
                continue
            }
            if seen.insert(name).inserted {
                result.append(tool)
            } else {
                DiagnosticsLogger.log(
                    "Duplicate provider function tool omitted",
                    level: .warning,
                    category: .settings,
                    metadata: ["tool": name]
                )
            }
        }
        return result
    }

    private func metadataForProvider(
        settings: AppSettings,
        provider: String,
        model: String,
        context: AppSettings.ReasoningContext
    ) -> [String: String] {
        switch provider.uppercased() {
        case "CODEX_AUTH":
            let summary = settings.codexReasoningSummary.resolvedIfBlank("auto").lowercased()
            let summaryToSend: String?
            if settings.codexReasoningEnabled,
               summary != "none",
               settings.codexSupportsReasoningSummaries || CodexModelCatalog.supportsReasoningSummary(model) {
                summaryToSend = summary
            } else {
                summaryToSend = nil
            }

            let verbosity = settings.codexVerbosity.resolvedIfBlank("medium").lowercased()
            let verbosityToSend = CodexModelCatalog.supportsTextVerbosity(model) ? verbosity : nil
            var metadata: [String: String] = [
                "codexPromptCacheEnabled": settings.codexPromptCacheEnabled ? "true" : "false"
            ]
            if let summaryToSend {
                metadata["codexReasoningSummary"] = summaryToSend
            }
            if let verbosityToSend {
                metadata["codexVerbosity"] = verbosityToSend
            }
            return metadata
        case "GEMINI":
            let overrides = settings.thinkingOverride(for: context)
            let level = effectiveGeminiThinkingLevel(
                settings: settings,
                model: model,
                enabledOverride: overrides.enabled,
                levelOverride: overrides.level
            ) ?? ""
            return [
                "geminiResponseMimeType": settings.geminiResponseMimeType,
                "geminiResponseJSONSchema": settings.geminiResponseJSONSchema,
                "geminiFunctionDeclarations": settings.geminiFunctionDeclarations,
                "geminiThinkingLevel": level
            ]
        default:
            return [:]
        }
    }

    private func thinkingConfigForProvider(
        settings: AppSettings,
        provider: String,
        model: String,
        context: AppSettings.ReasoningContext
    ) throws -> ProviderThinkingConfig? {
        let overrides = settings.thinkingOverride(for: context)
        switch provider.uppercased() {
        case "OPENROUTER":
            return try buildOpenRouterThinkingConfig(settings: settings, model: model, context: context)
        case "CODEX_AUTH":
            let enabled = overrides.enabled ?? settings.codexReasoningEnabled
            let baseEffort = settings.codexReasoningEffort.resolvedIfBlank("medium")
            let overrideEffort = overrides.codexEffort?.resolvedIfBlank(baseEffort)
            return ProviderThinkingConfig(
                enabled: nil,
                budget: nil,
                effort: enabled ? (overrideEffort ?? baseEffort) : "none",
                includeThoughts: true,
                exclude: nil
            )
        case "SUPERGROK":
            let enabled = overrides.enabled ?? settings.superGrokReasoningEnabled
            let baseEffort = settings.superGrokReasoningEffort.resolvedIfBlank("medium")
            let overrideEffort = overrides.codexEffort?.resolvedIfBlank(baseEffort)
            let rawEffort = enabled ? (overrideEffort ?? baseEffort) : "none"
            let effort: String
            if rawEffort == "none" {
                effort = "none"
            } else {
                let normalized = rawEffort.lowercased()
                effort = ["low", "medium", "high"].contains(normalized) ? normalized : "medium"
            }
            if let catalog = SuperGrokModelCatalog.model(for: model), !catalog.supportsReasoning {
                return nil
            }
            return ProviderThinkingConfig(
                enabled: nil,
                budget: nil,
                effort: effort,
                includeThoughts: true,
                exclude: nil
            )
        case "GEMINI":
            let enabled = overrides.enabled ?? settings.geminiThinkingEnabled
            let budget = overrides.budget ?? settings.geminiThinkingBudget
            if GeminiModelUtils.isThinkingLevelSupported(model: model) {
                return ProviderThinkingConfig(
                    enabled: nil,
                    budget: nil,
                    effort: nil,
                    includeThoughts: true,
                    exclude: nil
                )
            }
            guard let budget = GeminiModelUtils.calculateEffectiveThinkingBudget(
                model: model,
                userThinkingEnabled: enabled,
                userThinkingBudget: budget
            ) else {
                return nil
            }
            return ProviderThinkingConfig(
                enabled: nil,
                budget: budget,
                effort: nil,
                includeThoughts: true,
                exclude: nil
            )
        default:
            return nil
        }
    }

    private func buildOpenRouterThinkingConfig(
        settings: AppSettings,
        model: String,
        context: AppSettings.ReasoningContext
    ) throws -> ProviderThinkingConfig? {
        let overrides = settings.openRouterOverride(for: context)
        let reasoningExclude = overrides.exclude ?? settings.openRouterReasoningExclude
        let requestedThinkingEnabled = overrides.enabled ?? settings.openRouterThinkingEnabled
        guard let modelInfo = modelService.getModelById(model) else {
            if requestedThinkingEnabled {
                throw ProviderClientError.parseFailure(
                    "OpenRouter reasoning capabilities are unavailable for model: \(model)"
                )
            }
            return nil
        }
        guard let capabilities = modelInfo.reasoning else {
            if requestedThinkingEnabled {
                throw ProviderClientError.parseFailure(
                    "OpenRouter model does not expose reasoning capabilities: \(model)"
                )
            }
            return nil
        }

        let thinkingEnabled = capabilities.mandatory || requestedThinkingEnabled
        let reasoningMode = (overrides.mode ?? settings.openRouterReasoningMode)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let reasoningEffort = (overrides.effort ?? settings.openRouterReasoningEffort)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let thinkingBudget = max(0, overrides.budget ?? settings.openRouterThinkingBudget)
        let includeThoughts = !reasoningExclude

        if !thinkingEnabled {
            return ProviderThinkingConfig(
                enabled: false,
                budget: nil,
                effort: nil,
                includeThoughts: includeThoughts,
                exclude: true
            )
        }

        let supportedModes = ["auto"]
            + (capabilities.selectableEfforts.isEmpty ? [] : ["effort"])
            + (capabilities.supportsMaxTokens ? ["budget"] : [])
        let mode = supportedModes.contains(reasoningMode) ? reasoningMode : "auto"
        let budget = mode == "budget" && thinkingBudget > 0 ? thinkingBudget : nil
        let effort: String?
        if mode == "effort" {
            let supportedEfforts = capabilities.selectableEfforts
            if supportedEfforts.contains(reasoningEffort) {
                effort = reasoningEffort
            } else if let defaultEffort = capabilities.defaultEffort?.lowercased(),
                      supportedEfforts.contains(defaultEffort) {
                effort = defaultEffort
            } else if let firstEffort = supportedEfforts.first {
                effort = firstEffort
            } else {
                throw ProviderClientError.parseFailure(
                    "OpenRouter reasoning effort is unavailable for model: \(model)"
                )
            }
        } else {
            effort = nil
        }
        let enabled: Bool? = mode == "auto" || (budget == nil && effort == nil) ? true : nil
        let exclude: Bool? = reasoningExclude ? true : nil

        if budget == nil, effort == nil, enabled == nil, exclude == nil {
            return nil
        }
        return ProviderThinkingConfig(
            enabled: enabled,
            budget: budget,
            effort: effort,
            includeThoughts: includeThoughts,
            exclude: exclude
        )
    }

    private func providerPreferencesForProvider(
        settings: AppSettings,
        provider: String,
        model: String
    ) async throws -> ProviderRoutingConfig? {
        guard provider.uppercased() == "OPENROUTER" else { return nil }

        let preferredProviders = settings.preferredProvidersList()
        let requestedQuantizations = normalizedOpenRouterSlugs(settings.selectedQuantizationsList())
        var providers: [String] = []
        var quantizations: [String] = []

        if !preferredProviders.isEmpty || !requestedQuantizations.isEmpty {
            let endpointOptions: OpenRouterModelEndpointOptions
            do {
                endpointOptions = try await modelService.getModelEndpointOptions(modelId: model)
            } catch {
                DiagnosticsLogger.log(
                    "OpenRouter endpoint restriction validation failed",
                    category: .network,
                    metadata: ["model": model],
                    error: error
                )
                throw ProviderClientError.parseFailure(
                    "OpenRouter endpoint restrictions could not be validated for \(model): \(error.localizedDescription)"
                )
            }

            let availableProviderSet = Set(endpointOptions.providerEndpoints.map(\.tag))
            let invalidProviders = preferredProviders.filter { !availableProviderSet.contains($0) }
            guard invalidProviders.isEmpty else {
                throw ProviderClientError.parseFailure(
                    "Unavailable OpenRouter endpoint tag(s) for \(model): \(invalidProviders.joined(separator: ", "))"
                )
            }
            providers = preferredProviders

            let availableQuantizationSet = Set(endpointOptions.quantizations)
            let invalidQuantizations = requestedQuantizations.filter { !availableQuantizationSet.contains($0) }
            guard invalidQuantizations.isEmpty else {
                throw ProviderClientError.parseFailure(
                    "Unavailable OpenRouter quantization(s) for \(model): \(invalidQuantizations.joined(separator: ", "))"
                )
            }
            quantizations = requestedQuantizations
        }

        let hasRoutingProviders = !providers.isEmpty
        if !hasRoutingProviders, quantizations.isEmpty, settings.maxPricePerMillionTokens <= 0 {
            return nil
        }
        let onlyProviders = !settings.allowFallbacks && hasRoutingProviders ? providers : nil
        let orderProviders = onlyProviders == nil && hasRoutingProviders ? providers : nil
        let maxPrice = settings.maxPricePerMillionTokens > 0
            ? ProviderMaxPriceConfig(
                prompt: settings.maxPricePerMillionTokens,
                completion: settings.maxPricePerMillionTokens,
                request: nil,
                image: nil,
                audio: nil
            )
            : nil
        let trimmedSort = settings.providerSort.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        DiagnosticsLogger.log(
            "OpenRouter provider routing applied",
            category: .network,
            metadata: [
                "model": model,
                "providers": providers.joined(separator: ","),
                "only": (onlyProviders ?? []).joined(separator: ","),
                "allow_fallbacks": String(settings.allowFallbacks)
            ]
        )
        return ProviderRoutingConfig(
            order: orderProviders,
            allowFallbacks: hasRoutingProviders ? settings.allowFallbacks : nil,
            requireParameters: settings.requireParameters ? true : nil,
            dataCollection: nil,
            quantizations: quantizations.isEmpty ? nil : quantizations,
            maxPrice: maxPrice,
            only: onlyProviders,
            ignore: nil,
            sort: trimmedSort.isEmpty ? nil : trimmedSort
        )
    }

    private func normalizedOpenRouterSlugs(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func effectiveGeminiThinkingLevel(
        settings: AppSettings,
        model: String,
        enabledOverride: Bool?,
        levelOverride: String?
    ) -> String? {
        guard GeminiModelUtils.isThinkingLevelSupported(model: model) else { return nil }

        let defaultLevel = GeminiModelUtils.getDefaultThinkingLevel(model: model)
        let levelSource = levelOverride ?? settings.geminiThinkingLevel
        var normalized = GeminiModelUtils.normalizeThinkingLevel(model: model, level: levelSource) ?? defaultLevel
        let enabled = enabledOverride ?? settings.geminiThinkingEnabled
        if !GeminiModelUtils.isThinkingAlwaysOn(model: model), !enabled,
           let minimal = GeminiModelUtils.getMinimalThinkingLevel(model: model) {
            normalized = minimal
        }
        return normalized
    }
}

private extension String {
    func resolvedIfBlank(_ fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
