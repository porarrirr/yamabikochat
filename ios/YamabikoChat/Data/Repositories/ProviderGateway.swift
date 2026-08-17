import Foundation

typealias PiAgentStream = @Sendable (
    ProviderRequest,
    PiAgentConfiguration,
    LocalToolRegistry
) async throws -> AsyncThrowingStream<ProviderStreamEvent, Error>

/// The single LLM execution boundary. Every network-backed provider is normalized into a
/// Pi model and executed by the bundled `pi-agent-core` runtime.
final class ProviderGateway {
    private let settingsRepository: SettingsRepository
    private let credentialStore: SecureCredentialStore
    private let piStream: PiAgentStream
    private let localTools: LocalToolRegistry
    private let codexAuthRepository: CodexAuthRepository?
    private let superGrokAuthRepository: SuperGrokAuthRepository?
    private let modelsDevCatalogRepository: ModelsDevCatalogRepository?
    private let appleIntelligence = AppleIntelligenceProviderClient()

    init(
        settingsRepository: SettingsRepository,
        credentialStore: SecureCredentialStore,
        codexAuthRepository: CodexAuthRepository? = nil,
        superGrokAuthRepository: SuperGrokAuthRepository? = nil,
        modelsDevCatalogRepository: ModelsDevCatalogRepository? = nil,
        localTools: LocalToolRegistry = LocalToolRegistry(executors: [WebSearchTool(), FetchUrlTool()]),
        piStream: @escaping PiAgentStream = { request, configuration, tools in
            try await PiAgentRuntime.shared.stream(
                request: request,
                configuration: configuration,
                tools: tools
            )
        }
    ) {
        self.settingsRepository = settingsRepository
        self.credentialStore = credentialStore
        self.codexAuthRepository = codexAuthRepository
        self.superGrokAuthRepository = superGrokAuthRepository
        self.modelsDevCatalogRepository = modelsDevCatalogRepository
        self.localTools = localTools
        self.piStream = piStream
    }

    func generate(request: ProviderRequest, provider: LLMProvider) async throws -> ProviderResponse {
        try await generate(request: request, providerID: provider.rawValue)
    }

    func generate(request: ProviderRequest, providerID: String) async throws -> ProviderResponse {
        let stream = try await stream(request: request, providerID: providerID)
        var completed: ProviderResponse?
        var text = ""
        var reasoning = ""
        for try await event in stream {
            switch event {
            case let .textDelta(delta): text += delta
            case let .reasoningDelta(delta): reasoning += delta
            case let .completed(response): completed = response
            }
        }
        guard var response = completed else {
            throw ProviderClientError.parseFailure("Pi agent stream ended without completion")
        }
        if response.text.isEmpty { response.text = text }
        if response.reasoningSummary == nil { response.reasoningSummary = reasoning.trimmedNonEmpty }
        return response
    }

    func stream(
        request: ProviderRequest,
        provider: LLMProvider
    ) async throws -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        try await stream(request: request, providerID: provider.rawValue)
    }

    func stream(
        request: ProviderRequest,
        providerID: String
    ) async throws -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        let requestID = UUID().uuidString
        let normalizedProvider = providerID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        DiagnosticsLogger.log(
            "Provider gateway entered",
            category: .network,
            requestID: requestID,
            metadata: [
                "provider": normalizedProvider,
                "model": request.model,
                "messages": String(request.messages.count),
                "tools": request.tools.map(\.type).joined(separator: ","),
                "stream": String(request.stream)
            ]
        )
        let settings: AppSettings
        do {
            settings = try settingsRepository.load()
        } catch {
            DiagnosticsLogger.log(
                "Provider gateway settings load failed",
                category: .network,
                requestID: requestID,
                metadata: ["provider": normalizedProvider, "model": request.model],
                error: error
            )
            throw error
        }
        if knownProvider(providerID) == .appleIntelligence {
            return appleIntelligence.stream(request: request)
        }

        let piConfiguration: PiAgentConfiguration
        do {
            piConfiguration = try await configuration(
                providerID: providerID,
                request: request,
                settings: settings
            )
        } catch {
            DiagnosticsLogger.log(
                "Pi agent configuration failed",
                category: .network,
                requestID: requestID,
                metadata: ["provider": normalizedProvider, "model": request.model],
                error: error
            )
            throw error
        }
        DiagnosticsLogger.log(
            "Pi agent configuration ready",
            category: .network,
            requestID: requestID,
            metadata: [
                "provider": normalizedProvider,
                "piProvider": piConfiguration.provider,
                "model": piConfiguration.model,
                "api": piConfiguration.api,
                "baseURL": piConfiguration.baseURL,
                "credential": piConfiguration.apiKey.isEmpty ? "missing" : "present",
                "thinkingLevel": piConfiguration.thinkingLevel ?? "none"
            ]
        )
        do {
            let stream = try await piStream(request, piConfiguration, localTools)
            DiagnosticsLogger.log(
                "Pi agent stream created",
                category: .network,
                requestID: requestID,
                metadata: ["provider": normalizedProvider, "model": request.model]
            )
            return stream
        } catch {
            DiagnosticsLogger.log(
                "Pi agent stream creation failed",
                category: .network,
                requestID: requestID,
                metadata: ["provider": normalizedProvider, "model": request.model],
                error: error
            )
            throw error
        }
    }

    private func configuration(
        providerID: String,
        request: ProviderRequest,
        settings: AppSettings
    ) async throws -> PiAgentConfiguration {
        if let dynamicID = ProviderReference(persistedID: providerID).modelsDevID {
            return try modelsDevConfiguration(providerID: dynamicID, request: request)
        }
        guard let provider = knownProvider(providerID) else {
            throw ProviderClientError.parseFailure("Unknown provider: \(providerID)")
        }

        var api = "openai-completions"
        var piProvider = provider.rawValue.lowercased()
        var baseURL: String
        var apiKey: String
        var headers: [String: String] = [:]
        var mcpAuthorizationToken: String?

        switch provider {
        case .gemini:
            api = "google-generative-ai"
            piProvider = "google"
            baseURL = "https://generativelanguage.googleapis.com/v1beta"
            apiKey = try credential(.gemini)
        case .openRouter:
            piProvider = "openrouter"
            baseURL = "https://openrouter.ai/api/v1"
            apiKey = try credential(.openRouter)
            headers = ["HTTP-Referer": "https://yamabikochat.app", "X-Title": "YamabikoChat iOS"]
        case .openAI:
            api = "openai-responses"
            piProvider = "openai"
            baseURL = normalizedBaseURL(settings.resolvedOpenAIBaseURL())
            apiKey = try credential(.openAI)
        case .openAICompat:
            let name = settings.selectedOpenAICompatPreset?.trimmedNonEmpty
            guard let name,
                  let value = try credentialStore.openAICompatAPIKey(name: name)?.trimmedNonEmpty else {
                throw ProviderClientError.missingCredential(LLMProvider.openAICompat.rawValue)
            }
            baseURL = normalizedBaseURL(
                settings.selectedCompatBaseURL()?.absoluteString ?? settings.resolvedOpenAIBaseURL()
            )
            apiKey = value
        case .miniMax:
            piProvider = "minimax"
            baseURL = normalizedBaseURL(settings.resolvedMiniMaxBaseURL())
            apiKey = try credential(.miniMax)
        case .zai:
            piProvider = "zai"
            baseURL = normalizedBaseURL(AppConstants.defaultZAICodingPlanBaseURL.absoluteString)
            apiKey = try credential(.zai)
        case .clinePass:
            piProvider = "cline-pass"
            baseURL = normalizedBaseURL(AppConstants.defaultClinePassBaseURL.absoluteString)
            apiKey = try credential(.clinePass)
        case .alibabaCodingPlan:
            api = "anthropic-messages"
            piProvider = "qwen-token-plan"
            baseURL = normalizedAnthropicBaseURL(AppConstants.defaultAlibabaCodingPlanBaseURL.absoluteString)
            apiKey = try credential(.alibabaCodingPlan)
            if request.tools.contains(where: { $0.type == "mcp_toolset" }) {
                headers["anthropic-beta"] = "mcp-client-2025-11-20"
                mcpAuthorizationToken = try credentialStore.readSecret(
                    key: AppConstants.alibabaMCPAuthorizationTokenKey
                )?.trimmedNonEmpty
            }
        case .openCodeGo:
            guard let route = OpenCodeGoModelCatalog.model(for: request.model) else {
                throw ProviderClientError.invalidBaseURL("Unsupported OpenCode Go model: \(request.model)")
            }
            piProvider = "opencode-go"
            api = route.endpointKind == .messages ? "anthropic-messages" : "openai-completions"
            baseURL = normalizedBaseURL(AppConstants.defaultOpenCodeGoBaseURL.absoluteString)
            apiKey = try credential(.openCodeGo)
        case .codexAuth:
            guard let auth = await codexAuthRepository?.getBearerToken() else {
                throw ProviderClientError.missingCredential(LLMProvider.codexAuth.rawValue)
            }
            api = "openai-codex-responses"
            piProvider = "openai-codex"
            baseURL = "https://chatgpt.com/backend-api/codex"
            apiKey = auth.token
            headers["originator"] = "codex_cli_rs"
            if let accountID = auth.accountId?.trimmedNonEmpty {
                headers["ChatGPT-Account-ID"] = accountID
            }
        case .superGrok:
            guard let auth = await superGrokAuthRepository?.getBearerToken() else {
                throw ProviderClientError.missingCredential(LLMProvider.superGrok.rawValue)
            }
            api = "openai-responses"
            piProvider = "xai-oauth"
            baseURL = normalizedBaseURL(AppConstants.defaultSuperGrokBaseURL.absoluteString)
            apiKey = auth.token
        case .appleIntelligence:
            preconditionFailure("Apple Intelligence is handled before Pi configuration")
        }

        return PiAgentConfiguration(
            provider: piProvider,
            model: normalizedModel(request.model, provider: provider),
            api: api,
            baseURL: baseURL,
            apiKey: apiKey,
            headers: headers,
            reasoning: request.thinking?.enabled != false,
            thinkingLevel: thinkingLevel(
                request.thinking,
                geminiLevel: provider == .gemini ? request.metadata["geminiThinkingLevel"] : nil
            ),
            supportsImages: request.metadata["supportsVision"] == "true",
            contextWindow: Int(request.metadata["contextWindow"] ?? ""),
            maxTokens: max(1024, Int(request.metadata["max_output_tokens"] ?? "") ?? 8192),
            mcpAuthorizationToken: mcpAuthorizationToken
        )
    }

    private func modelsDevConfiguration(
        providerID: String,
        request: ProviderRequest
    ) throws -> PiAgentConfiguration {
        guard let catalog = modelsDevCatalogRepository?.provider(for: .modelsDev(providerID)),
              let model = catalog.models.first(where: { $0.id == request.model }) else {
            throw ProviderClientError.parseFailure("models.dev provider or model is unavailable: \(providerID)/\(request.model)")
        }
        let credentialField = catalog.env.first(where: {
            $0.contains("API_KEY") || $0.contains("TOKEN") || $0.contains("SECRET") || $0.contains("BEARER")
        }) ?? catalog.env.first
        guard let credentialField else { throw ProviderClientError.missingCredential(providerID) }
        let credentialKey = modelsDevFieldKey(providerID: providerID, fieldName: credentialField)
        try migrateLegacyCredentialIfNeeded(providerID: providerID, destinationKey: credentialKey)
        guard let apiKey = try credentialStore.readSecret(key: credentialKey)?.trimmedNonEmpty else {
            throw ProviderClientError.missingCredential(providerID)
        }
        let manual = try credentialStore.readSecret(
            key: modelsDevFieldKey(providerID: providerID, fieldName: "YAMABIKO_BASE_URL")
        )?.trimmedNonEmpty
        guard let base = catalog.api?.trimmedNonEmpty.flatMap({ $0.contains("${") ? nil : $0 })
            ?? knownModelsDevBaseURL(providerID)
            ?? manual else {
            throw ProviderClientError.invalidBaseURL("A completed base URL is required for \(catalog.name)")
        }
        let adapter = ModelsDevProviderAdapterRegistry.profile(for: catalog).adapter
        guard adapter == .anthropic || Self.isOpenAICompatible(adapter) else {
            throw ProviderClientError.parseFailure("\(catalog.name) has no Pi-compatible adapter")
        }
        var headers: [String: String] = [:]
        if adapter == .azureOpenAI { headers["api-key"] = apiKey }
        if adapter == .cloudflareAIGateway { headers["cf-aig-authorization"] = "Bearer \(apiKey)" }
        return PiAgentConfiguration(
            provider: providerID,
            model: request.model,
            api: adapter == .anthropic ? "anthropic-messages" : "openai-completions",
            baseURL: adapter == .anthropic ? normalizedAnthropicBaseURL(base) : normalizedBaseURL(base),
            apiKey: apiKey,
            headers: headers,
            reasoning: model.reasoning,
            thinkingLevel: thinkingLevel(request.thinking),
            supportsImages: model.attachment,
            contextWindow: model.limits.context ?? model.limits.input ?? 128_000,
            maxTokens: model.limits.output ?? 8192
        )
    }

    private static func isOpenAICompatible(_ adapter: ProviderAdapterKind) -> Bool {
        switch adapter {
        case .openAICompatible, .openAI, .providerSpecific, .cohere, .vercelAI,
             .cloudflareAIGateway, .azureOpenAI, .unverifiedOpenAICompatible:
            return true
        default:
            return false
        }
    }

    private func credential(_ provider: CredentialProvider) throws -> String {
        guard let value = try credentialStore.credential(for: provider)?.trimmedNonEmpty else {
            throw ProviderClientError.missingCredential(provider.rawValue)
        }
        return value
    }

    private func knownProvider(_ value: String) -> LLMProvider? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "GEMINI_AUTH": return .gemini
        case "QWEN_CODE": return .openRouter
        case let id: return LLMProvider(rawValue: id)
        }
    }

    private func normalizedModel(_ model: String, provider: LLMProvider) -> String {
        guard provider == .codexAuth else { return model }
        return model.replacingOccurrences(of: "/openai/", with: "")
    }

    private func thinkingLevel(
        _ thinking: ProviderThinkingConfig?,
        geminiLevel: String? = nil
    ) -> String? {
        guard thinking?.enabled != false else { return "off" }
        let value = (geminiLevel?.trimmedNonEmpty ?? thinking?.effort)?.lowercased()
        return ["minimal", "low", "medium", "high", "xhigh", "max"].contains(value) ? value : nil
    }

    private func normalizedBaseURL(_ value: String) -> String {
        var result = value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        for suffix in ["/chat/completions", "/responses"] where result.hasSuffix(suffix) {
            result.removeLast(suffix.count)
        }
        return result
    }

    private func normalizedAnthropicBaseURL(_ value: String) -> String {
        var result = normalizedBaseURL(value)
        for suffix in ["/v1/messages", "/messages", "/v1"] where result.hasSuffix(suffix) {
            result.removeLast(suffix.count)
            break
        }
        return result
    }

    private func modelsDevFieldKey(providerID: String, fieldName: String) -> String {
        let provider = providerID.lowercased().replacingOccurrences(
            of: "[^a-z0-9._-]+", with: "_", options: .regularExpression
        )
        let field = fieldName.uppercased().replacingOccurrences(
            of: "[^A-Z0-9_]+", with: "_", options: .regularExpression
        )
        return "models_dev_\(provider)_\(field)"
    }

    private func migrateLegacyCredentialIfNeeded(providerID: String, destinationKey: String) throws {
        guard try credentialStore.readSecret(key: destinationKey)?.trimmedNonEmpty == nil else { return }
        let legacy: CredentialProvider? = switch providerID.lowercased() {
        case "openai": .openAI
        case "opencode-go": .openCodeGo
        case "cline-pass": .clinePass
        case "alibaba-coding-plan": .alibabaCodingPlan
        case "zai-coding-plan": .zai
        case "minimax": .miniMax
        default: nil
        }
        if let legacy, let value = try credentialStore.credential(for: legacy)?.trimmedNonEmpty {
            try credentialStore.saveSecret(value, key: destinationKey)
        }
    }

    private func knownModelsDevBaseURL(_ providerID: String) -> String? {
        [
            "openai": "https://api.openai.com/v1", "anthropic": "https://api.anthropic.com",
            "xai": "https://api.x.ai/v1", "groq": "https://api.groq.com/openai/v1",
            "mistral": "https://api.mistral.ai/v1", "togetherai": "https://api.together.xyz/v1",
            "cerebras": "https://api.cerebras.ai/v1", "deepinfra": "https://api.deepinfra.com/v1/openai",
            "perplexity": "https://api.perplexity.ai", "cohere": "https://api.cohere.ai/compatibility/v1",
            "vercel": "https://ai-gateway.vercel.sh/v1", "v0": "https://api.v0.dev/v1",
            "venice": "https://api.venice.ai/api/v1", "aihubmix": "https://aihubmix.com/v1"
        ][providerID]
    }
}
