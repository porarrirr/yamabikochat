import Foundation

final class ProviderGateway {
    private let settingsRepository: SettingsRepository
    private let credentialStore: SecureCredentialStore
    private let registry: ProviderRegistry
    private let httpClient: HTTPClientProtocol

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
        httpClient: HTTPClientProtocol = URLSessionHTTPClient()
    ) {
        self.settingsRepository = settingsRepository
        self.credentialStore = credentialStore
        self.registry = registry
        self.httpClient = httpClient
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
            return try await generateOnce(
                request: request,
                provider: provider,
                settings: settings,
                client: client,
                credentialStore: credentialStore
            )
        }

        let candidates = geminiRotationCandidates(for: request, settings: settings)
        guard candidates.count > 1 else {
            return try await generateOnce(
                request: request,
                provider: provider,
                settings: settings,
                client: client,
                credentialStore: credentialStore
            )
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
                var streamHadAnswerText = false
                var transientAttempt = 0
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
}