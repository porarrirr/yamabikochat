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

    func generate(
        request: ProviderRequest,
        providerID: String,
        onStreamEvent: (@Sendable (ProviderStreamEvent) -> Void)? = nil
    ) async throws -> ProviderResponse {
        let stream = try await stream(request: request, providerID: providerID)
        var completed: ProviderResponse?
        var text = ""
        var reasoning = ""
        var toolActivity = ToolActivityPayload()
        for try await event in stream {
            onStreamEvent?(event)
            switch event {
            case let .textDelta(delta): text += delta
            case let .reasoningDelta(delta): reasoning += delta
            case let .toolActivity(activity): toolActivity.apply(activity)
            case let .completed(response): completed = response
            }
        }
        guard var response = completed else {
            throw ProviderClientError.parseFailure("Pi agent stream ended without completion")
        }
        if response.text.isEmpty { response.text = text }
        if response.reasoningSummary == nil { response.reasoningSummary = reasoning.trimmedNonEmpty }
        if !toolActivity.steps.isEmpty { response.toolActivity = toolActivity }
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
                "contractVersion": String(piConfiguration.contractVersion),
                "credential": piConfiguration.apiKey?.isEmpty == false || !piConfiguration.env.isEmpty ? "present" : "missing",
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

        var piProvider = provider.rawValue.lowercased()
        var apiKey: String
        var headers: [String: String] = [:]
        var mcpAuthorizationToken: String?

        switch provider {
        case .gemini:
            piProvider = "google"
            apiKey = try credential(.gemini)
        case .openRouter:
            piProvider = "openrouter"
            apiKey = try credential(.openRouter)
            headers = [
                "HTTP-Referer": "https://apps.apple.com/jp/app/yamabikochat-ai%E3%83%81%E3%83%A3%E3%83%83%E3%83%88/id6771687018",
                "X-Title": "YamabikoChat iOS"
            ]
        case .openAI:
            piProvider = "openai"
            apiKey = try credential(.openAI)
        case .openAICompat:
            throw ProviderClientError.unsupportedModel(provider: provider.rawValue, model: request.model)
        case .miniMax:
            piProvider = "minimax"
            apiKey = try credential(.miniMax)
        case .zai:
            piProvider = "zai"
            apiKey = try credential(.zai)
        case .clinePass:
            throw ProviderClientError.unsupportedModel(provider: provider.rawValue, model: request.model)
        case .alibabaCodingPlan:
            piProvider = "qwen-token-plan"
            apiKey = try credential(.alibabaCodingPlan)
            if request.tools.contains(where: { $0.type == "mcp_toolset" }) {
                headers["anthropic-beta"] = "mcp-client-2025-11-20"
                mcpAuthorizationToken = try credentialStore.readSecret(
                    key: AppConstants.alibabaMCPAuthorizationTokenKey
                )?.trimmedNonEmpty
            }
        case .openCodeGo:
            piProvider = "opencode-go"
            apiKey = try credential(.openCodeGo)
        case .codexAuth:
            guard let auth = await codexAuthRepository?.getBearerToken() else {
                throw ProviderClientError.missingCredential(LLMProvider.codexAuth.rawValue)
            }
            piProvider = "openai-codex"
            apiKey = auth.token
            headers["originator"] = "codex_cli_rs"
            if let accountID = auth.accountId?.trimmedNonEmpty {
                headers["ChatGPT-Account-ID"] = accountID
            }
        case .superGrok:
            guard let auth = await superGrokAuthRepository?.getBearerToken() else {
                throw ProviderClientError.missingCredential(LLMProvider.superGrok.rawValue)
            }
            piProvider = "xai-oauth"
            apiKey = auth.token
        case .appleIntelligence:
            preconditionFailure("Apple Intelligence is handled before Pi configuration")
        }

        return PiAgentConfiguration(
            provider: piProvider,
            model: normalizedModel(request.model, provider: provider),
            apiKey: apiKey,
            headers: headers,
            thinkingLevel: thinkingLevel(
                request.thinking,
                geminiLevel: provider == .gemini ? request.metadata["geminiThinkingLevel"] : nil
            ),
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
        var env: [String: String] = [:]
        for field in catalog.env {
            let key = modelsDevFieldKey(providerID: providerID, fieldName: field)
            try migrateLegacyCredentialIfNeeded(providerID: providerID, destinationKey: key)
            if let value = try credentialStore.readSecret(key: key)?.trimmedNonEmpty { env[field] = value }
        }
        guard !env.isEmpty else {
            throw ProviderClientError.missingCredential(providerID)
        }
        let normalizedModel = providerID.caseInsensitiveCompare("opencode-go") == .orderedSame
            ? OpenCodeGoModelCatalog.normalizedModelID(request.model)
            : request.model
        return PiAgentConfiguration(
            provider: providerID,
            model: normalizedModel,
            apiKey: nil,
            headers: [:],
            env: env,
            catalogContract: PiCatalogModelContract(
                npm: model.providerContract?.npm,
                api: model.providerContract?.api,
                shape: model.providerContract?.shape,
                toolCall: model.toolCall,
                provenance: model.providerContract?.provenance
            ),
            thinkingLevel: thinkingLevel(request.thinking),
        )
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
        switch provider {
        case .codexAuth:
            return model.replacingOccurrences(of: "/openai/", with: "")
        case .openCodeGo:
            return OpenCodeGoModelCatalog.normalizedModelID(model)
        default:
            return model
        }
    }

    private func thinkingLevel(
        _ thinking: ProviderThinkingConfig?,
        geminiLevel: String? = nil
    ) -> String? {
        guard thinking?.enabled != false else { return "off" }
        let value = (geminiLevel?.trimmedNonEmpty ?? thinking?.effort)?.lowercased()
        return ["minimal", "low", "medium", "high", "xhigh", "max"].contains(value) ? value : nil
    }


    private func modelsDevFieldKey(providerID: String, fieldName: String) -> String {
        ModelsDevReasoningPreference.fieldKey(providerID: providerID, fieldName: fieldName)
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

}
