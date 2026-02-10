import Foundation

protocol ProviderClient {
    var provider: LLMProvider { get }

    func generate(
        request: ProviderRequest,
        settings: AppSettings,
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol
    ) async throws -> ProviderResponse

    func stream(
        request: ProviderRequest,
        settings: AppSettings,
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol
    ) -> AsyncThrowingStream<ProviderStreamEvent, Error>
}

extension ProviderClient {
    func stream(
        request: ProviderRequest,
        settings: AppSettings,
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol
    ) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let response = try await generate(
                        request: request,
                        settings: settings,
                        credentialStore: credentialStore,
                        httpClient: httpClient
                    )
                    let chunks = response.text.split(separator: " ", omittingEmptySubsequences: false)
                    if chunks.isEmpty {
                        continuation.yield(.completed(response))
                    } else {
                        for (index, piece) in chunks.enumerated() {
                            let suffix = index == chunks.count - 1 ? "" : " "
                            continuation.yield(.textDelta(String(piece) + suffix))
                        }
                        continuation.yield(.completed(response))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
