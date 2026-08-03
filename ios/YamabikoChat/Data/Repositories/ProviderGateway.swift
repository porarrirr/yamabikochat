import Foundation

final class ProviderGateway {
    private let settingsRepository: SettingsRepository
    private let credentialStore: SecureCredentialStore
    private let registry: ProviderRegistry
    private let httpClient: HTTPClientProtocol
    private let superGrokAuthRepository: SuperGrokAuthRepository?
    private let modelsDevCatalogRepository: ModelsDevCatalogRepository?

    /// Google's Gemini API intermittently returns a generic HTTP 500 "Internal error
    /// encountered" (status "INTERNAL") for some models regardless of request content -
    /// observed most on smaller/experimental models. Retrying the identical request usually
    /// succeeds, so this is treated as transient rather than surfaced immediately.
    private static let transientGeminiRetryLimit = 2
    private static let transientGeminiRetryDelayNanoseconds: UInt64 = 400_000_000

    private let geminiRotationStateLock = NSLock()
    private var lastGoodGeminiRotationCandidate: GeminiRotationCandidate?

    init(
        settingsRepository: SettingsRepository,
        credentialStore: SecureCredentialStore,
        registry: ProviderRegistry = .init(),
        httpClient: HTTPClientProtocol = URLSessionHTTPClient(),
        superGrokAuthRepository: SuperGrokAuthRepository? = nil,
        modelsDevCatalogRepository: ModelsDevCatalogRepository? = nil
    ) {
        self.settingsRepository = settingsRepository
        self.credentialStore = credentialStore
        self.registry = registry
        self.httpClient = httpClient
        self.superGrokAuthRepository = superGrokAuthRepository
        self.modelsDevCatalogRepository = modelsDevCatalogRepository
    }

    private static func isUnauthorized(_ error: Error) -> Bool {
        guard case let ProviderClientError.httpStatus(status, _) = error else { return false }
        return status == 401
    }

    private func prepareSuperGrokAuth(force: Bool = false) async throws {
        guard let superGrokAuthRepository else { return }
        let result = await superGrokAuthRepository.refreshIfNeeded(force: force)
        if case let .failure(error) = result {
            throw error
        }
    }

    private func generateWithProviderAuth(
        request: ProviderRequest,
        provider: LLMProvider,
        settings: AppSettings,
        client: ProviderClient,
        credentialStore: SecureCredentialStore
    ) async throws -> ProviderResponse {
        if provider == .superGrok {
            try await prepareSuperGrokAuth()
            do {
                return try await generateOnce(
                    request: request,
                    provider: provider,
                    settings: settings,
                    client: client,
                    credentialStore: credentialStore
                )
            } catch {
                guard Self.isUnauthorized(error) else { throw error }
                try await prepareSuperGrokAuth(force: true)
                return try await generateOnce(
                    request: request,
                    provider: provider,
                    settings: settings,
                    client: client,
                    credentialStore: credentialStore
                )
            }
        }
        return try await generateOnce(
            request: request,
            provider: provider,
            settings: settings,
            client: client,
            credentialStore: credentialStore
        )
    }

    private static func isTransientGeminiServerError(_ error: Error) -> Bool {
        guard case let ProviderClientError.httpStatus(status, _) = error else { return false }
        return status == 500
    }

    // MARK: - Gemini key/model rotation

    /// One (API key, model) combination to try for a Gemini request. `keyIndex` groups
    /// candidates that share the same key so an auth failure can skip the rest of that key's
    /// models without re-deriving the grouping.
    private struct GeminiRotationCandidate {
        let apiKey: String
        let model: String
        let keyIndex: Int
    }

    /// Wraps the app's real credential store so a specific Gemini API key can be substituted
    /// for a single rotation attempt without changing `GeminiProviderClient` or the shared
    /// `ProviderClient` protocol - only the exact Keychain key Gemini reads is intercepted.
    private struct GeminiCredentialOverride: SecureCredentialStore {
        let base: SecureCredentialStore
        let apiKey: String
        private let overrideKey = "provider_key_\(CredentialProvider.gemini.rawValue)"

        func saveSecret(_ value: String?, key: String) throws {
            try base.saveSecret(value, key: key)
        }

        func readSecret(key: String) throws -> String? {
            key == overrideKey ? apiKey : try base.readSecret(key: key)
        }

        func deleteSecret(key: String) throws {
            try base.deleteSecret(key: key)
        }
    }

    /// Builds the ordered list of candidates to try: the default key first, then any
    /// configured extra keys; for each key, `request.model` first, then any configured
    /// rotation models. When the user hasn't configured any extra keys/models this collapses
    /// to a single candidate, so callers must special-case `count <= 1` to preserve the exact
    /// pre-rotation behavior.
    private func geminiRotationCandidates(for request: ProviderRequest, settings: AppSettings) -> [GeminiRotationCandidate] {
        var keys: [String] = []
        let defaultKey = (try? credentialStore.credential(for: .gemini)) ?? nil
        if let trimmed = defaultKey?.trimmedNonEmpty {
            keys.append(trimmed)
        }
        for name in settings.geminiKeyNames() {
            let value = (try? credentialStore.geminiAPIKey(name: name)) ?? nil
            if let trimmed = value?.trimmedNonEmpty, !keys.contains(trimmed) {
                keys.append(trimmed)
            }
        }

        var models: [String] = [request.model]
        for model in settings.geminiRotationModelsList() where !models.contains(model) {
            models.append(model)
        }

        var candidates: [GeminiRotationCandidate] = []
        for (keyIndex, key) in keys.enumerated() {
            for model in models {
                candidates.append(GeminiRotationCandidate(apiKey: key, model: model, keyIndex: keyIndex))
            }
        }
        return candidates
    }

    /// Promotes the whole key-block containing the last successful candidate to the front, so a
    /// subsequent request starts where the previous one left off instead of always retrying an
    /// already-known-exhausted candidate first. In-memory only for the process lifetime.
    private func reorderedForLastGoodGeminiCandidate(_ candidates: [GeminiRotationCandidate]) -> [GeminiRotationCandidate] {
        geminiRotationStateLock.lock()
        let last = lastGoodGeminiRotationCandidate
        geminiRotationStateLock.unlock()

        guard let last,
              let matchIndex = candidates.firstIndex(where: { $0.apiKey == last.apiKey && $0.model == last.model })
        else { return candidates }

        let keyIndex = candidates[matchIndex].keyIndex
        let sameKey = candidates.filter { $0.keyIndex == keyIndex }
        let others = candidates.filter { $0.keyIndex != keyIndex }
        guard let blockIndex = sameKey.firstIndex(where: { $0.model == last.model }) else { return candidates }
        return Array(sameKey[blockIndex...]) + Array(sameKey[..<blockIndex]) + others
    }

    private func rememberGoodGeminiRotationCandidate(_ candidate: GeminiRotationCandidate) {
        geminiRotationStateLock.lock()
        lastGoodGeminiRotationCandidate = candidate
        geminiRotationStateLock.unlock()
    }

    /// The pre-rotation single-attempt behavior: retries the identical request on a transient
    /// Gemini 500, otherwise throws immediately. Shared by the unconfigured path and by each
    /// rotation candidate's attempt.
    private func generateOnce(
        request: ProviderRequest,
        provider: LLMProvider,
        settings: AppSettings,
        client: ProviderClient,
        credentialStore: SecureCredentialStore
    ) async throws -> ProviderResponse {
        var attempt = 0
        while true {
            do {
                return try await client.generate(
                    request: request,
                    settings: settings,
                    credentialStore: credentialStore,
                    httpClient: httpClient
                )
            } catch {
                guard provider == .gemini,
                      attempt < Self.transientGeminiRetryLimit,
                      Self.isTransientGeminiServerError(error)
                else {
                    DiagnosticsLogger.log(
                        "Provider generate failed",
                        category: .network,
                        metadata: [
                            "provider": provider.rawValue,
                            "model": request.model
                        ],
                        error: error
                    )
                    throw error
                }
                attempt += 1
                DiagnosticsLogger.log(
                    "Gemini transient server error; retrying generate",
                    category: .network,
                    metadata: [
                        "provider": provider.rawValue,
                        "model": request.model,
                        "attempt": String(attempt)
                    ]
                )
                try? await Task.sleep(nanoseconds: Self.transientGeminiRetryDelayNanoseconds)
            }
        }
    }

    func generate(
        request: ProviderRequest,
        provider: LLMProvider
    ) async throws -> ProviderResponse {
        let settings = try settingsRepository.load()
        let client = registry.client(for: provider)

        var request = request
        request.metadata["provider"] = provider.rawValue

        guard provider == .gemini else {
            return try await generateWithProviderAuth(
                request: request,
                provider: provider,
                settings: settings,
                client: client,
                credentialStore: credentialStore
            )
        }

        let candidates = geminiRotationCandidates(for: request, settings: settings)
        guard candidates.count > 1 else {
            return try await generateOnce(request: request, provider: provider, settings: settings, client: client, credentialStore: credentialStore)
        }

        let ordered = reorderedForLastGoodGeminiCandidate(candidates)
        var index = 0
        var lastError: Error = ProviderClientError.invalidResponse
        while index < ordered.count {
            let candidate = ordered[index]
            var candidateRequest = request
            candidateRequest.model = candidate.model
            let scopedStore = GeminiCredentialOverride(base: credentialStore, apiKey: candidate.apiKey)
            do {
                let response = try await generateOnce(
                    request: candidateRequest,
                    provider: provider,
                    settings: settings,
                    client: client,
                    credentialStore: scopedStore
                )
                rememberGoodGeminiRotationCandidate(candidate)
                return response
            } catch {
                let classification = GeminiProviderClient.classifyRotationEligibility(error)
                guard classification != .other else { throw error }
                lastError = error
                DiagnosticsLogger.log(
                    "Gemini candidate failed; rotating",
                    category: .network,
                    metadata: [
                        "model": candidate.model,
                        "keyIndex": String(candidate.keyIndex),
                        "classification": classification == .authFailure ? "auth" : "rateLimit",
                        "candidateIndex": String(index)
                    ],
                    error: error
                )
                index += 1
                if classification == .authFailure {
                    while index < ordered.count, ordered[index].keyIndex == candidate.keyIndex {
                        index += 1
                    }
                }
            }
        }
        DiagnosticsLogger.log(
            "Gemini rotation exhausted all candidates",
            category: .network,
            metadata: ["provider": provider.rawValue],
            error: lastError
        )
        throw lastError
    }

    func generate(request: ProviderRequest, providerID: String) async throws -> ProviderResponse {
        let reference = ProviderReference(persistedID: providerID)
        guard reference.isModelsDev else {
            guard let provider = knownProvider(providerID) else {
                throw ProviderClientError.parseFailure("Unsupported provider: \(providerID)")
            }
            return try await generate(request: request, provider: provider)
        }
        let resolved = try resolveModelsDevRequest(request, reference: reference)
        return try await resolved.client.generate(
            request: resolved.request,
            settings: settingsRepository.load(),
            credentialStore: credentialStore,
            httpClient: httpClient
        )
    }

    func stream(
        request: ProviderRequest,
        provider: LLMProvider
    ) async throws -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        let settings = try settingsRepository.load()
        let client = registry.client(for: provider)

        var request = request
        request.metadata["provider"] = provider.rawValue

        let rotationCandidates: [GeminiRotationCandidate] = provider == .gemini
            ? reorderedForLastGoodGeminiCandidate(geminiRotationCandidates(for: request, settings: settings))
            : []
        let rotationActive = rotationCandidates.count > 1

        return AsyncThrowingStream { continuation in
            let task = Task {
                if provider == .superGrok {
                    do {
                        try await prepareSuperGrokAuth()
                    } catch {
                        continuation.finish(throwing: error)
                        return
                    }
                }

                var streamHadAnswerText = false
                var transientAttempt = 0
                var superGrokAuthRetried = false
                var candidateIndex = 0
                var currentRequest = request
                var currentCredentialStore: SecureCredentialStore = credentialStore
                if rotationActive {
                    currentRequest.model = rotationCandidates[0].model
                    currentCredentialStore = GeminiCredentialOverride(base: credentialStore, apiKey: rotationCandidates[0].apiKey)
                }

                while true {
                    var yieldedAnyEventThisAttempt = false
                    do {
                        let stream = client.stream(
                            request: currentRequest,
                            settings: settings,
                            credentialStore: currentCredentialStore,
                            httpClient: httpClient
                        )
                        for try await event in stream {
                            yieldedAnyEventThisAttempt = true
                            if event.includesNonEmptyAnswerText {
                                streamHadAnswerText = true
                            }
                            continuation.yield(event)
                        }

                        if provider.retriesNonStreamingWhenStreamReturnsNoText, !streamHadAnswerText {
                            DiagnosticsLogger.log(
                                "Stream completed without text; retrying non-streaming",
                                category: .network,
                                metadata: [
                                    "provider": provider.rawValue,
                                    "model": currentRequest.model
                                ]
                            )
                            let fallback = try await client.generate(
                                request: currentRequest,
                                settings: settings,
                                credentialStore: currentCredentialStore,
                                httpClient: httpClient
                            )
                            continuation.yield(
                                .completed(
                                    ProviderResponse(
                                        text: fallback.text,
                                        reasoningSummary: fallback.reasoningSummary,
                                        raw: fallback.raw,
                                        usage: fallback.usage,
                                        toolCalls: fallback.toolCalls
                                    )
                                )
                            )
                        }
                        if rotationActive {
                            rememberGoodGeminiRotationCandidate(rotationCandidates[candidateIndex])
                        }
                        continuation.finish()
                        return
                    } catch {
                        if provider == .superGrok,
                           !yieldedAnyEventThisAttempt,
                           !superGrokAuthRetried,
                           Self.isUnauthorized(error) {
                            superGrokAuthRetried = true
                            do {
                                try await prepareSuperGrokAuth(force: true)
                                continue
                            } catch {
                                continuation.finish(throwing: error)
                                return
                            }
                        }
                        // Only safe to retry when nothing has been yielded yet this attempt -
                        // otherwise a retry would duplicate partial output already shown to the user.
                        if provider == .gemini,
                           !yieldedAnyEventThisAttempt,
                           transientAttempt < Self.transientGeminiRetryLimit,
                           Self.isTransientGeminiServerError(error) {
                            transientAttempt += 1
                            DiagnosticsLogger.log(
                                "Gemini transient server error; retrying stream",
                                category: .network,
                                metadata: [
                                    "provider": provider.rawValue,
                                    "model": currentRequest.model,
                                    "attempt": String(transientAttempt)
                                ]
                            )
                            try? await Task.sleep(nanoseconds: Self.transientGeminiRetryDelayNanoseconds)
                            continue
                        }
                        if rotationActive, !yieldedAnyEventThisAttempt {
                            let classification = GeminiProviderClient.classifyRotationEligibility(error)
                            if classification != .other {
                                let failedKeyIndex = rotationCandidates[candidateIndex].keyIndex
                                var nextIndex = candidateIndex + 1
                                if classification == .authFailure {
                                    while nextIndex < rotationCandidates.count, rotationCandidates[nextIndex].keyIndex == failedKeyIndex {
                                        nextIndex += 1
                                    }
                                }
                                if nextIndex < rotationCandidates.count {
                                    DiagnosticsLogger.log(
                                        "Gemini stream candidate failed; rotating",
                                        category: .network,
                                        metadata: [
                                            "model": rotationCandidates[candidateIndex].model,
                                            "keyIndex": String(failedKeyIndex),
                                            "classification": classification == .authFailure ? "auth" : "rateLimit",
                                            "candidateIndex": String(candidateIndex)
                                        ],
                                        error: error
                                    )
                                    candidateIndex = nextIndex
                                    transientAttempt = 0
                                    currentRequest.model = rotationCandidates[candidateIndex].model
                                    currentCredentialStore = GeminiCredentialOverride(base: credentialStore, apiKey: rotationCandidates[candidateIndex].apiKey)
                                    continue
                                }
                            }
                        }
                        DiagnosticsLogger.log(
                            "Provider stream failed",
                            category: .network,
                            metadata: [
                                "provider": provider.rawValue,
                                "model": currentRequest.model
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

    func stream(request: ProviderRequest, providerID: String) async throws -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        let reference = ProviderReference(persistedID: providerID)
        guard reference.isModelsDev else {
            guard let provider = knownProvider(providerID) else {
                throw ProviderClientError.parseFailure("Unsupported provider: \(providerID)")
            }
            return try await stream(request: request, provider: provider)
        }
        let resolved = try resolveModelsDevRequest(request, reference: reference)
        let settings = try settingsRepository.load()
        return resolved.client.stream(
            request: resolved.request,
            settings: settings,
            credentialStore: credentialStore,
            httpClient: httpClient
        )
    }

    private func resolveModelsDevRequest(
        _ request: ProviderRequest,
        reference: ProviderReference
    ) throws -> (request: ProviderRequest, client: ProviderClient) {
        guard let catalog = modelsDevCatalogRepository?.provider(for: reference) else {
            throw ProviderClientError.parseFailure("models.dev provider is unavailable: \(reference.persistedID)")
        }
        guard let selectedModel = catalog.models.first(where: { $0.id == request.model }) else {
            throw ProviderClientError.parseFailure("Model is unavailable in the current models.dev catalog: \(request.model)")
        }
        if !request.tools.isEmpty, !selectedModel.toolCall {
            throw ProviderClientError.parseFailure("\(selectedModel.name) does not support tool calls")
        }
        if request.messages.contains(where: { !$0.attachments.isEmpty }), !selectedModel.attachment {
            throw ProviderClientError.parseFailure("\(selectedModel.name) does not support attachments")
        }
        if request.thinking?.enabled == true, !selectedModel.reasoning {
            throw ProviderClientError.parseFailure("\(selectedModel.name) does not support reasoning")
        }
        let profile = ModelsDevProviderAdapterRegistry.profile(for: catalog)
        let credentialField = catalog.env.first(where: {
            $0.contains("API_KEY") || $0.contains("TOKEN") || $0.contains("SECRET") || $0.contains("BEARER")
        }) ?? catalog.env.first
        guard let credentialField else { throw ProviderClientError.missingCredential(catalog.id) }
        let credentialKey = modelsDevFieldKey(providerID: catalog.id, fieldName: credentialField)
        guard try credentialStore.readSecret(key: credentialKey)?.trimmedNonEmpty != nil else {
            throw ProviderClientError.missingCredential(catalog.id)
        }
        let manuallyConfiguredBaseURL = try credentialStore.readSecret(
            key: modelsDevFieldKey(providerID: catalog.id, fieldName: "YAMABIKO_BASE_URL")
        )?.trimmedNonEmpty
        let catalogBaseURL = catalog.api?.trimmedNonEmpty.flatMap { $0.contains("${") ? nil : $0 }
        let knownBaseURL = try knownModelsDevBaseURL(catalog, credentialStore: credentialStore)
        let baseURL = catalogBaseURL ?? knownBaseURL ?? manuallyConfiguredBaseURL
        guard let baseURL else { throw ProviderClientError.invalidBaseURL("A completed base URL is required for \(catalog.name)") }

        let client: ProviderClient
        switch profile.adapter {
        case .openAICompatible, .openAI, .providerSpecific, .cohere, .vercelAI,
             .cloudflareAIGateway, .azureOpenAI, .unverifiedOpenAICompatible:
            client = OpenAICompatibleProviderClient()
        case .anthropic:
            client = AnthropicCompatibleProviderClient()
        default:
            throw ProviderClientError.parseFailure("\(catalog.name) requires the \(profile.adapter.rawValue) native adapter")
        }
        if !profile.isVerifiedMapping {
            DiagnosticsLogger.log("models.dev unverified OpenAI-compatible mode", level: .warning, category: .network, metadata: ["provider": catalog.id])
        }
        var dynamicRequest = request
        dynamicRequest.metadata["provider"] = reference.persistedID
        dynamicRequest.metadata["modelsDevProviderID"] = catalog.id
        dynamicRequest.metadata["modelsDevBaseURL"] = baseURL
        dynamicRequest.metadata["modelsDevCredentialKey"] = credentialKey
        dynamicRequest.metadata["modelsDevAuthHeader"] = switch profile.adapter {
        case .azureOpenAI: "api-key"
        case .cloudflareAIGateway: "cf-aig-authorization"
        default: "bearer"
        }
        return (dynamicRequest, client)
    }

    private func modelsDevFieldKey(providerID: String, fieldName: String) -> String {
        let provider = providerID.lowercased().replacingOccurrences(of: "[^a-z0-9._-]+", with: "_", options: .regularExpression)
        let field = fieldName.uppercased().replacingOccurrences(of: "[^A-Z0-9_]+", with: "_", options: .regularExpression)
        return "models_dev_\(provider)_\(field)"
    }

    private func knownProvider(_ providerID: String) -> LLMProvider? {
        switch providerID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "GEMINI_AUTH": return .gemini
        case "QWEN_CODE": return .openRouter
        case let value: return LLMProvider(rawValue: value)
        }
    }

    private func knownModelsDevBaseURL(
        _ provider: CatalogProvider,
        credentialStore: SecureCredentialStore
    ) throws -> String? {
        let fixed = [
            "openai": "https://api.openai.com/v1", "anthropic": "https://api.anthropic.com",
            "xai": "https://api.x.ai/v1", "groq": "https://api.groq.com/openai/v1",
            "mistral": "https://api.mistral.ai/v1", "togetherai": "https://api.together.xyz/v1",
            "cerebras": "https://api.cerebras.ai/v1", "deepinfra": "https://api.deepinfra.com/v1/openai",
            "perplexity": "https://api.perplexity.ai", "cohere": "https://api.cohere.ai/compatibility/v1",
            "vercel": "https://ai-gateway.vercel.sh/v1", "v0": "https://api.v0.dev/v1",
            "venice": "https://api.venice.ai/api/v1", "aihubmix": "https://aihubmix.com/v1",
            "merge-gateway": "https://api-gateway.merge.dev/v1/ai-sdk"
        ][provider.id]
        if let fixed { return fixed }
        if provider.id == "azure" || provider.id == "azure-cognitive-services" {
            guard let field = provider.env.first(where: { $0.contains("RESOURCE_NAME") }),
                  let resource = try credentialStore.readSecret(
                    key: modelsDevFieldKey(providerID: provider.id, fieldName: field)
                  )?.trimmedNonEmpty
            else { return nil }
            return provider.id == "azure"
                ? "https://\(resource).openai.azure.com/openai/v1"
                : "https://\(resource).services.ai.azure.com/openai/v1"
        }
        if provider.id == "cloudflare-ai-gateway" {
            let account = try credentialStore.readSecret(
                key: modelsDevFieldKey(providerID: provider.id, fieldName: "CLOUDFLARE_ACCOUNT_ID")
            )?.trimmedNonEmpty
            let gateway = try credentialStore.readSecret(
                key: modelsDevFieldKey(providerID: provider.id, fieldName: "CLOUDFLARE_GATEWAY_ID")
            )?.trimmedNonEmpty
            guard let account, let gateway else { return nil }
            return "https://gateway.ai.cloudflare.com/v1/\(account)/\(gateway)/compat"
        }
        return nil
    }
}
