import Foundation

final class ProviderGateway {
    private let settingsRepository: SettingsRepository
    private let credentialStore: SecureCredentialStore
    private let geminiAuthRepository: GeminiAuthRepository?
    private let qwenAuthRepository: QwenAuthRepository?
    private let registry: ProviderRegistry
    private let httpClient: HTTPClientProtocol

    init(
        settingsRepository: SettingsRepository,
        credentialStore: SecureCredentialStore,
        geminiAuthRepository: GeminiAuthRepository? = nil,
        qwenAuthRepository: QwenAuthRepository? = nil,
        registry: ProviderRegistry = .init(),
        httpClient: HTTPClientProtocol = URLSessionHTTPClient()
    ) {
        self.settingsRepository = settingsRepository
        self.credentialStore = credentialStore
        self.geminiAuthRepository = geminiAuthRepository
        self.qwenAuthRepository = qwenAuthRepository
        self.registry = registry
        self.httpClient = httpClient
    }

    func generate(
        request: ProviderRequest,
        provider: LLMProvider
    ) async throws -> ProviderResponse {
        let settings = try settingsRepository.load()
        let client = registry.client(for: provider)

        var request = request
        request.metadata["provider"] = provider.rawValue

        await prepareGeminiAuthIfNeeded(provider: provider, model: request.model)
        await prepareQwenAuthIfNeeded(provider: provider, model: request.model)

        func performGenerate() async throws -> ProviderResponse {
            try await client.generate(
                request: request,
                settings: settings,
                credentialStore: credentialStore,
                httpClient: httpClient
            )
        }

        do {
            return try await performGenerate()
        } catch {
            if shouldRetryGeminiAuth401(provider: provider, error: error),
               await forceRefreshGeminiAuth(model: request.model) {
                do {
                    return try await performGenerate()
                } catch {
                    DiagnosticsLogger.log(
                        "Provider generate retry failed after Gemini auth refresh",
                        category: .network,
                        metadata: [
                            "provider": provider.rawValue,
                            "model": request.model
                        ],
                        error: error
                    )
                    throw error
                }
            }
            if shouldRetryQwenAuth401(provider: provider, error: error),
               await forceRefreshQwenAuth(model: request.model) {
                do {
                    return try await performGenerate()
                } catch {
                    DiagnosticsLogger.log(
                        "Provider generate retry failed after Qwen auth refresh",
                        category: .network,
                        metadata: [
                            "provider": provider.rawValue,
                            "model": request.model
                        ],
                        error: error
                    )
                    throw error
                }
            }
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
    }

    func stream(
        request: ProviderRequest,
        provider: LLMProvider
    ) async throws -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        let settings = try settingsRepository.load()
        let client = registry.client(for: provider)

        var request = request
        request.metadata["provider"] = provider.rawValue

        await prepareGeminiAuthIfNeeded(provider: provider, model: request.model)
        await prepareQwenAuthIfNeeded(provider: provider, model: request.model)

        return AsyncThrowingStream { continuation in
            let task = Task {
                var didRetryAfterRefresh = false

                while !Task.isCancelled {
                    let stream = client.stream(
                        request: request,
                        settings: settings,
                        credentialStore: credentialStore,
                        httpClient: httpClient
                    )
                    do {
                        for try await event in stream {
                            continuation.yield(event)
                        }
                        continuation.finish()
                        return
                    } catch {
                        if !didRetryAfterRefresh,
                           shouldRetryGeminiAuth401(provider: provider, error: error),
                           await forceRefreshGeminiAuth(model: request.model) {
                            didRetryAfterRefresh = true
                            DiagnosticsLogger.log(
                                "Provider stream retrying after Gemini auth refresh",
                                category: .network,
                                metadata: [
                                    "provider": provider.rawValue,
                                    "model": request.model
                                ]
                            )
                            continue
                        }
                        if !didRetryAfterRefresh,
                           shouldRetryQwenAuth401(provider: provider, error: error),
                           await forceRefreshQwenAuth(model: request.model) {
                            didRetryAfterRefresh = true
                            DiagnosticsLogger.log(
                                "Provider stream retrying after Qwen auth refresh",
                                category: .network,
                                metadata: [
                                    "provider": provider.rawValue,
                                    "model": request.model
                                ]
                            )
                            continue
                        }

                        DiagnosticsLogger.log(
                            "Provider stream failed",
                            category: .network,
                            metadata: [
                                "provider": provider.rawValue,
                                "model": request.model
                            ],
                            error: error
                        )
                        continuation.finish(throwing: error)
                        return
                    }
                }

                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func prepareGeminiAuthIfNeeded(provider: LLMProvider, model: String) async {
        guard provider == .geminiAuth, let geminiAuthRepository else { return }
        let result = await geminiAuthRepository.refreshIfNeeded(force: false)
        if case let .failure(error) = result {
            DiagnosticsLogger.log(
                "Gemini auth preflight refresh failed; continuing with current token",
                level: .warning,
                category: .network,
                metadata: [
                    "provider": provider.rawValue,
                    "model": model
                ],
                error: error
            )
        }
    }

    private func prepareQwenAuthIfNeeded(provider: LLMProvider, model: String) async {
        guard provider == .qwenCode, let qwenAuthRepository else { return }
        let result = await qwenAuthRepository.refreshIfNeeded(force: false)
        if case let .failure(error) = result {
            DiagnosticsLogger.log(
                "Qwen auth preflight refresh failed; continuing with current token",
                level: .warning,
                category: .network,
                metadata: [
                    "provider": provider.rawValue,
                    "model": model
                ],
                error: error
            )
        }
    }

    private func forceRefreshGeminiAuth(model: String) async -> Bool {
        guard let geminiAuthRepository else { return false }
        let result = await geminiAuthRepository.refreshIfNeeded(force: true)
        switch result {
        case .success:
            DiagnosticsLogger.log(
                "Gemini auth force refresh succeeded",
                category: .network,
                metadata: [
                    "provider": LLMProvider.geminiAuth.rawValue,
                    "model": model
                ]
            )
            return true
        case let .failure(error):
            DiagnosticsLogger.log(
                "Gemini auth force refresh failed",
                level: .warning,
                category: .network,
                metadata: [
                    "provider": LLMProvider.geminiAuth.rawValue,
                    "model": model
                ],
                error: error
            )
            return false
        }
    }

    private func forceRefreshQwenAuth(model: String) async -> Bool {
        guard let qwenAuthRepository else { return false }
        let result = await qwenAuthRepository.refreshIfNeeded(force: true)
        switch result {
        case .success:
            DiagnosticsLogger.log(
                "Qwen auth force refresh succeeded",
                category: .network,
                metadata: [
                    "provider": LLMProvider.qwenCode.rawValue,
                    "model": model
                ]
            )
            return true
        case let .failure(error):
            DiagnosticsLogger.log(
                "Qwen auth force refresh failed",
                level: .warning,
                category: .network,
                metadata: [
                    "provider": LLMProvider.qwenCode.rawValue,
                    "model": model
                ],
                error: error
            )
            return false
        }
    }

    private func shouldRetryGeminiAuth401(provider: LLMProvider, error: Error) -> Bool {
        guard provider == .geminiAuth else { return false }
        guard case let ProviderClientError.httpStatus(status, _) = error else { return false }
        return status == 401
    }

    private func shouldRetryQwenAuth401(provider: LLMProvider, error: Error) -> Bool {
        guard provider == .qwenCode else { return false }
        guard case let ProviderClientError.httpStatus(status, _) = error else { return false }
        return status == 401
    }
}
