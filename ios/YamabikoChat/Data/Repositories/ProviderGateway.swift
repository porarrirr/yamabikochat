import Foundation

final class ProviderGateway {
    private let settingsRepository: SettingsRepository
    private let credentialStore: SecureCredentialStore
    private let registry: ProviderRegistry
    private let httpClient: HTTPClientProtocol

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

    func generate(
        request: ProviderRequest,
        provider: LLMProvider
    ) async throws -> ProviderResponse {
        let settings = try settingsRepository.load()
        let client = registry.client(for: provider)

        var request = request
        request.metadata["provider"] = provider.rawValue

        do {
            return try await client.generate(
                request: request,
                settings: settings,
                credentialStore: credentialStore,
                httpClient: httpClient
            )
        } catch {
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

        return AsyncThrowingStream { continuation in
            let task = Task {
                var fullText = ""
                var fullReasoning = ""
                do {
                    let stream = client.stream(
                        request: request,
                        settings: settings,
                        credentialStore: credentialStore,
                        httpClient: httpClient
                    )
                    for try await event in stream {
                        accumulate(event, fullText: &fullText, fullReasoning: &fullReasoning)
                        continuation.yield(event)
                    }

                    if provider.retriesNonStreamingWhenStreamReturnsNoText,
                       fullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        DiagnosticsLogger.log(
                            "Stream completed without text; retrying non-streaming",
                            category: .network,
                            metadata: [
                                "provider": provider.rawValue,
                                "model": request.model
                            ]
                        )
                        let fallback = try await client.generate(
                            request: request,
                            settings: settings,
                            credentialStore: credentialStore,
                            httpClient: httpClient
                        )
                        fullText = fallback.text
                        fullReasoning = fallback.reasoningSummary ?? fullReasoning
                        continuation.yield(
                            .completed(
                                ProviderResponse(
                                    text: fullText,
                                    reasoningSummary: fullReasoning.trimmedNonEmpty,
                                    raw: fallback.raw,
                                    usage: fallback.usage
                                )
                            )
                        )
                    }
                    continuation.finish()
                } catch {
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
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func accumulate(
        _ event: ProviderStreamEvent,
        fullText: inout String,
        fullReasoning: inout String
    ) {
        switch event {
        case let .textDelta(delta):
            fullText += delta
        case let .reasoningDelta(delta):
            fullReasoning += delta
        case let .completed(response):
            if fullText.isEmpty, !response.text.isEmpty {
                fullText = response.text
            }
            if let reasoning = response.reasoningSummary, !reasoning.isEmpty {
                fullReasoning = reasoning
            }
        case .toolCallDelta:
            break
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
