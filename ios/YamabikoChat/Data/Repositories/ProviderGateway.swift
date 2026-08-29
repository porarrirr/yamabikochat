import Foundation

typealias PiAgentStream = @Sendable (
    ProviderRequest,
    PiAgentConfiguration,
    LocalToolRegistry
) async throws -> AsyncThrowingStream<ProviderStreamEvent, Error>

/// The single LLM execution boundary. Every network-backed provider is normalized into a
/// Pi model and executed by the bundled `pi-agent-core` runtime.
final class ProviderGateway {
    static let openRouterAttributionHeaders = [
        "HTTP-Referer": "https://apps.apple.com/jp/app/yamabikochat-ai%E3%83%81%E3%83%A3%E3%83%83%E3%83%88/id6771687018",
        "X-OpenRouter-Title": "YamabikoChat iOS",
        "X-Title": "YamabikoChat iOS"
    ]

    private let settingsRepository: SettingsRepository
    private let credentialStore: SecureCredentialStore
    private let piStream: PiAgentStream
    /// Snapshot fallback for tests / legacy callers.
    private let localTools: LocalToolRegistry
    /// Factory evaluated per request so Skill states are reflected without recreating the gateway.
    private let localToolFactory: (@Sendable () -> LocalToolRegistry)?
    private let codexAuthRepository: CodexAuthRepository?
    private let superGrokAuthRepository: SuperGrokAuthRepository?
    private let modelsDevCatalogRepository: ModelsDevCatalogRepository?
    private let openRouterModelService: OpenRouterModelService?
    private let appleIntelligence = AppleIntelligenceProviderClient()
    private let geminiRotationStateLock = NSLock()
    private var lastGoodGeminiRotationCandidate: GeminiRotationCandidate?

    private struct GeminiRotationCandidate: Sendable {
        let keyID: String
        let apiKey: String
        let model: String
        let keyIndex: Int
    }

    private enum GeminiRotationEligibility {
        case rateLimited
        case authFailure
        case other
    }

    init(
        settingsRepository: SettingsRepository,
        credentialStore: SecureCredentialStore,
        codexAuthRepository: CodexAuthRepository? = nil,
        superGrokAuthRepository: SuperGrokAuthRepository? = nil,
        modelsDevCatalogRepository: ModelsDevCatalogRepository? = nil,
        openRouterModelService: OpenRouterModelService? = nil,
        localTools: LocalToolRegistry = LocalToolRegistry(executors: [WebSearchTool(), FetchUrlTool(), PythonExecuteTool()]),
        localToolFactory: (@Sendable () -> LocalToolRegistry)? = nil,
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
        self.openRouterModelService = openRouterModelService
        self.localTools = localTools
        self.localToolFactory = localToolFactory
        self.piStream = piStream
    }

    // Factory has priority; fallback to snapshot for backwards compatibility / tests.
    private func resolveLocalTools() -> LocalToolRegistry {
        localToolFactory?() ?? localTools
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
        var reasoning = ""
        var toolActivity = ToolActivityPayload()
        for try await event in stream {
            onStreamEvent?(event)
            switch event {
            case .answerStart, .textDelta: break
            case let .reasoningDelta(delta): reasoning += delta
            case let .toolActivity(activity): toolActivity.apply(activity)
            case let .executionSnapshot(execution): toolActivity.piExecution = execution
            case let .completed(response): completed = response
            }
        }
        guard var response = completed else {
            throw ProviderClientError.parseFailure("Pi agent stream ended without completion")
        }
        if response.reasoningSummary == nil { response.reasoningSummary = reasoning.trimmedNonEmpty }
        if let providerTranscript = response.providerTranscript {
            toolActivity.providerTranscript = providerTranscript
        }
        if toolActivity.hasPersistableContent {
            var merged = response.toolActivity ?? ToolActivityPayload()
            if !toolActivity.steps.isEmpty { merged.steps = toolActivity.steps }
            if !toolActivity.providerTranscript.isEmpty { merged.providerTranscript = toolActivity.providerTranscript }
            if !toolActivity.attachmentPaths.isEmpty { merged.attachmentPaths = toolActivity.attachmentPaths }
            merged.piExecution = response.piExecution ?? toolActivity.piExecution
            response.toolActivity = merged
        }
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
        if knownProvider(providerID) == .gemini {
            let candidates = try reorderedForLastGoodGeminiCandidate(
                geminiRotationCandidates(for: request, settings: settings)
            )
            return try await geminiRotationStream(
                request: request,
                providerID: providerID,
                settings: settings,
                candidates: candidates,
                requestID: requestID,
                normalizedProvider: normalizedProvider
            )
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
            let stream = try await piStream(request, piConfiguration, resolveLocalTools())
            DiagnosticsLogger.log(
                "Pi agent stream created",
                category: .network,
                requestID: requestID,
                metadata: ["provider": normalizedProvider, "model": request.model]
            )
            return monitoredStream(
                stream,
                requestID: requestID,
                provider: normalizedProvider,
                model: request.model
            )
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

    private func monitoredStream(
        _ stream: AsyncThrowingStream<ProviderStreamEvent, Error>,
        requestID: String,
        provider: String,
        model: String
    ) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await event in stream {
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: CancellationError())
                } catch {
                    DiagnosticsLogger.log(
                        "Pi agent stream failed",
                        category: .network,
                        requestID: requestID,
                        metadata: ["provider": provider, "model": model],
                        error: error
                    )
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func geminiRotationCandidates(
        for request: ProviderRequest,
        settings: AppSettings
    ) throws -> [GeminiRotationCandidate] {
        var keys: [(id: String, value: String)] = []
        if let defaultKey = try credentialStore.credential(for: .gemini)?.trimmedNonEmpty {
            keys.append((id: "default", value: defaultKey))
        }
        for name in settings.geminiKeyNames() {
            guard let value = try credentialStore.geminiAPIKey(name: name)?.trimmedNonEmpty else {
                DiagnosticsLogger.log(
                    "Gemini rotation key slot has no credential",
                    level: .warning,
                    category: .network,
                    metadata: ["keySlot": name]
                )
                continue
            }
            guard !keys.contains(where: { $0.value == value }) else { continue }
            keys.append((id: "slot:\(name)", value: value))
        }
        guard !keys.isEmpty else {
            throw ProviderClientError.missingCredential(CredentialProvider.gemini.rawValue)
        }

        var models = [request.model]
        for model in settings.geminiRotationModelsList() where !models.contains(model) {
            models.append(model)
        }

        return keys.enumerated().flatMap { keyIndex, key in
            models.map { model in
                GeminiRotationCandidate(
                    keyID: key.id,
                    apiKey: key.value,
                    model: model,
                    keyIndex: keyIndex
                )
            }
        }
    }

    private func reorderedForLastGoodGeminiCandidate(
        _ candidates: [GeminiRotationCandidate]
    ) -> [GeminiRotationCandidate] {
        let last = geminiRotationStateLock.withLock { lastGoodGeminiRotationCandidate }
        guard let last,
              let matchIndex = candidates.firstIndex(where: {
                  $0.keyID == last.keyID &&
                      $0.apiKey == last.apiKey &&
                      $0.model == last.model
              }) else {
            return candidates
        }
        let keyIndex = candidates[matchIndex].keyIndex
        let sameKey = candidates.filter { $0.keyIndex == keyIndex }
        let otherKeys = candidates.filter { $0.keyIndex != keyIndex }
        guard let modelIndex = sameKey.firstIndex(where: { $0.model == last.model }) else {
            return candidates
        }
        return Array(sameKey[modelIndex...]) + Array(sameKey[..<modelIndex]) + otherKeys
    }

    private func rememberGoodGeminiRotationCandidate(_ candidate: GeminiRotationCandidate) {
        geminiRotationStateLock.withLock {
            lastGoodGeminiRotationCandidate = candidate
        }
    }

    private func geminiRotationStream(
        request: ProviderRequest,
        providerID: String,
        settings: AppSettings,
        candidates: [GeminiRotationCandidate],
        requestID: String,
        normalizedProvider: String
    ) async throws -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        var initialCandidateIndex = 0
        var initialStream: AsyncThrowingStream<ProviderStreamEvent, Error>
        while true {
            let candidate = candidates[initialCandidateIndex]
            var candidateRequest = request
            candidateRequest.model = candidate.model
            do {
                initialStream = try await startGeminiCandidate(
                    request: candidateRequest,
                    providerID: providerID,
                    settings: settings,
                    candidate: candidate,
                    candidateIndex: initialCandidateIndex,
                    requestID: requestID,
                    normalizedProvider: normalizedProvider
                )
                break
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                let eligibility = Self.geminiRotationEligibility(error)
                guard let nextIndex = Self.nextGeminiCandidateIndex(
                    after: initialCandidateIndex,
                    failedKeyIndex: candidate.keyIndex,
                    candidates: candidates,
                    eligibility: eligibility
                ) else {
                    throw error
                }
                logGeminiRotation(
                    candidate: candidate,
                    candidateIndex: initialCandidateIndex,
                    nextCandidateIndex: nextIndex,
                    eligibility: eligibility,
                    requestID: requestID,
                    error: error
                )
                initialCandidateIndex = nextIndex
            }
        }

        let preparedCandidateIndex = initialCandidateIndex
        let preparedInitialStream = initialStream
        return AsyncThrowingStream { continuation in
            let task = Task {
                var candidateIndex = preparedCandidateIndex
                var preparedStream: AsyncThrowingStream<ProviderStreamEvent, Error>? = preparedInitialStream

                while candidateIndex < candidates.count {
                    let candidate = candidates[candidateIndex]
                    var candidateRequest = request
                    candidateRequest.model = candidate.model
                    var pendingEvents: [ProviderStreamEvent] = []
                    var committedToCandidate = false

                    do {
                        let stream: AsyncThrowingStream<ProviderStreamEvent, Error>
                        if let existingStream = preparedStream {
                            stream = existingStream
                        } else {
                            stream = try await startGeminiCandidate(
                                request: candidateRequest,
                                providerID: providerID,
                                settings: settings,
                                candidate: candidate,
                                candidateIndex: candidateIndex,
                                requestID: requestID,
                                normalizedProvider: normalizedProvider
                            )
                        }
                        preparedStream = nil

                        for try await event in stream {
                            if !committedToCandidate && Self.commitsGeminiCandidate(event) {
                                pendingEvents.forEach { continuation.yield($0) }
                                pendingEvents.removeAll(keepingCapacity: false)
                                committedToCandidate = true
                            }
                            if committedToCandidate {
                                continuation.yield(event)
                            } else {
                                pendingEvents.append(event)
                            }
                        }

                        if !committedToCandidate {
                            pendingEvents.forEach { continuation.yield($0) }
                        }
                        rememberGoodGeminiRotationCandidate(candidate)
                        continuation.finish()
                        return
                    } catch is CancellationError {
                        continuation.finish(throwing: CancellationError())
                        return
                    } catch {
                        let eligibility = Self.geminiRotationEligibility(error)
                        let nextIndex = Self.nextGeminiCandidateIndex(
                            after: candidateIndex,
                            failedKeyIndex: candidate.keyIndex,
                            candidates: candidates,
                            eligibility: eligibility
                        )
                        if !committedToCandidate, let nextIndex {
                            logGeminiRotation(
                                candidate: candidate,
                                candidateIndex: candidateIndex,
                                nextCandidateIndex: nextIndex,
                                eligibility: eligibility,
                                requestID: requestID,
                                error: error
                            )
                            candidateIndex = nextIndex
                            continue
                        }

                        pendingEvents.forEach { continuation.yield($0) }
                        let exhausted = eligibility != .other && !committedToCandidate
                        DiagnosticsLogger.log(
                            exhausted ? "Gemini Pi rotation exhausted all candidates" : "Pi agent stream failed",
                            category: .network,
                            requestID: requestID,
                            metadata: [
                                "provider": normalizedProvider,
                                "model": candidate.model,
                                "geminiCandidate": String(candidateIndex),
                                "outputCommitted": String(committedToCandidate)
                            ],
                            error: error
                        )
                        continuation.finish(throwing: error)
                        return
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func startGeminiCandidate(
        request: ProviderRequest,
        providerID: String,
        settings: AppSettings,
        candidate: GeminiRotationCandidate,
        candidateIndex: Int,
        requestID: String,
        normalizedProvider: String
    ) async throws -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        let configuration = try await configuration(
            providerID: providerID,
            request: request,
            settings: settings,
            geminiAPIKeyOverride: candidate.apiKey
        )
        DiagnosticsLogger.log(
            "Pi agent configuration ready",
            category: .network,
            requestID: requestID,
            metadata: [
                "provider": normalizedProvider,
                "piProvider": configuration.provider,
                "model": configuration.model,
                "contractVersion": String(configuration.contractVersion),
                "credential": "present",
                "thinkingLevel": configuration.thinkingLevel ?? "none",
                "geminiCandidate": String(candidateIndex),
                "geminiKeyIndex": String(candidate.keyIndex)
            ]
        )
        let stream = try await piStream(request, configuration, resolveLocalTools())
        DiagnosticsLogger.log(
            "Pi agent stream created",
            category: .network,
            requestID: requestID,
            metadata: [
                "provider": normalizedProvider,
                "model": candidate.model,
                "geminiCandidate": String(candidateIndex)
            ]
        )
        return stream
    }

    private func logGeminiRotation(
        candidate: GeminiRotationCandidate,
        candidateIndex: Int,
        nextCandidateIndex: Int,
        eligibility: GeminiRotationEligibility,
        requestID: String,
        error: Error
    ) {
        DiagnosticsLogger.log(
            "Gemini Pi candidate failed; rotating",
            category: .network,
            requestID: requestID,
            metadata: [
                "model": candidate.model,
                "keyIndex": String(candidate.keyIndex),
                "classification": eligibility == .authFailure ? "auth" : "rateLimit",
                "candidateIndex": String(candidateIndex),
                "nextCandidateIndex": String(nextCandidateIndex)
            ],
            error: error
        )
    }

    private static func commitsGeminiCandidate(_ event: ProviderStreamEvent) -> Bool {
        switch event {
        case let .textDelta(value), let .reasoningDelta(value):
            return value.trimmedNonEmpty != nil
        case .toolActivity, .completed:
            return true
        case .answerStart, .executionSnapshot:
            return false
        }
    }

    private static func geminiRotationEligibility(_ error: Error) -> GeminiRotationEligibility {
        guard let providerError = error as? ProviderClientError else { return .other }
        let statusCode: Int?
        let code: String?
        let message: String
        switch providerError {
        case let .httpStatus(status, body):
            statusCode = status
            code = nil
            message = body
        case let .providerFailure(status, providerCode, providerMessage):
            statusCode = status
            code = providerCode
            message = providerMessage
        default:
            return .other
        }

        let normalizedCode = code?.uppercased() ?? ""
        let normalizedMessage = message.uppercased()
        if statusCode == 429 || normalizedCode == "RESOURCE_EXHAUSTED" || normalizedMessage.contains("RESOURCE_EXHAUSTED") {
            return .rateLimited
        }
        if statusCode == 401 || statusCode == 403 ||
            ["UNAUTHENTICATED", "PERMISSION_DENIED", "API_KEY_INVALID"].contains(normalizedCode) {
            return .authFailure
        }
        return .other
    }

    private static func nextGeminiCandidateIndex(
        after candidateIndex: Int,
        failedKeyIndex: Int,
        candidates: [GeminiRotationCandidate],
        eligibility: GeminiRotationEligibility
    ) -> Int? {
        guard eligibility != .other else { return nil }
        var nextIndex = candidateIndex + 1
        if eligibility == .authFailure {
            while nextIndex < candidates.count,
                  candidates[nextIndex].keyIndex == failedKeyIndex {
                nextIndex += 1
            }
        }
        return nextIndex < candidates.count ? nextIndex : nil
    }

    private func configuration(
        providerID: String,
        request: ProviderRequest,
        settings: AppSettings,
        geminiAPIKeyOverride: String? = nil
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
            apiKey = try geminiAPIKeyOverride?.trimmedNonEmpty ?? credential(.gemini)
        case .openRouter:
            piProvider = "openrouter"
            apiKey = try credential(.openRouter)
            headers = Self.openRouterAttributionHeaders
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

        let catalogContract: PiCatalogModelContract?
        let openRouterModels: [SimpleModel]
        if provider == .openRouter, let openRouterModelService {
            openRouterModels = await openRouterModelService.getAvailableModels()
        } else {
            openRouterModels = []
        }
        if let model = openRouterModels.first(where: { $0.id == request.model }) {
            catalogContract = PiCatalogModelContract(
                npm: "@openrouter/ai-sdk-provider",
                api: "https://openrouter.ai/api/v1",
                shape: nil,
                toolCall: model.supportsTools,
                provenance: "official_provider_catalog",
                name: model.name,
                reasoning: model.supportsReasoning,
                input: model.inputModalities,
                contextWindow: model.contextLength,
                maxTokens: model.maxCompletionTokens
            )
        } else {
            catalogContract = nil
        }
        return PiAgentConfiguration(
            provider: piProvider,
            model: normalizedModel(request.model, provider: provider),
            apiKey: apiKey,
            headers: headers,
            catalogContract: catalogContract,
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
                providerName: catalog.name,
                npm: model.providerContract?.npm,
                api: model.providerContract?.api,
                shape: model.providerContract?.shape,
                toolCall: model.toolCall,
                provenance: model.providerContract?.provenance,
                name: model.name,
                reasoning: model.reasoning,
                input: model.inputModalities,
                contextWindow: model.limits.context,
                maxTokens: model.limits.output
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
