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
}
