import XCTest
@testable import YamabikoChat

private final class InMemoryCredentialStore: SecureCredentialStore {
    private var storage: [String: String] = [:]

    func saveSecret(_ value: String?, key: String) throws {
        if let value {
            storage[key] = value
        } else {
            storage.removeValue(forKey: key)
        }
    }

    func readSecret(key: String) throws -> String? {
        storage[key]
    }

    func deleteSecret(key: String) throws {
        storage.removeValue(forKey: key)
    }
}

private struct StubHTTPClient: HTTPClientProtocol {
    var data: Data
    var statusCode: Int

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

    func stream(_ request: HTTPRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (AsyncThrowingStream { continuation in continuation.finish() }, response)
    }
}

private struct StubGeminiOAuthConfigProvider: GeminiOAuthConfigProviding {
    let config: GeminiOAuthClientConfig

    func loadOAuthClientConfig() -> GeminiOAuthClientConfig {
        config
    }
}

final class AuthRepositoryTests: XCTestCase {
    func testCodexRedirectURIUsesLocalhostForParity() {
        XCTAssertEqual(
            CodexAuthRepository.redirectURI(port: 1455),
            "http://localhost:1455/auth/callback"
        )
    }

    func testCodexLoginUpdatesState() async {
        let store = InMemoryCredentialStore()
        let repo = CodexAuthRepository(credentialStore: store)

        let result = await repo.login(
            apiKey: "sk-test",
            accessToken: nil,
            email: "user@example.com",
            planType: "plus",
            accountId: "acc_123"
        )

        switch result {
        case let .success(state):
            XCTAssertTrue(state.isLoggedIn)
            XCTAssertTrue(state.hasApiKey)
            XCTAssertEqual(state.email, "user@example.com")
            XCTAssertEqual(state.accountId, "acc_123")
        case let .failure(error):
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGeminiQuotaParse() async {
        let store = InMemoryCredentialStore()
        try? store.setGeminiAccessToken("token")
        try? store.saveSecret("my-project", key: "gemini_project_id")

        let payload = """
        {
          "buckets": [
            {
              "remainingAmount": "1000",
              "remainingFraction": 0.5,
              "resetTime": "2026-02-10T00:00:00Z",
              "tokenType": "INPUT",
              "modelId": "gemini-2.5-flash"
            }
          ]
        }
        """.data(using: .utf8)!

        let repo = GeminiAuthRepository(
            credentialStore: store,
            httpClient: StubHTTPClient(data: payload, statusCode: 200)
        )

        let result = await repo.retrieveUserQuota()
        switch result {
        case let .success(quota):
            XCTAssertEqual(quota.buckets.count, 1)
            XCTAssertEqual(quota.buckets.first?.modelId, "gemini-2.5-flash")
        case let .failure(error):
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGeminiOAuthConfigValidationRejectsPlaceholder() {
        let store = InMemoryCredentialStore()
        let placeholderRepo = GeminiAuthRepository(
            credentialStore: store,
            oauthConfigProvider: StubGeminiOAuthConfigProvider(
                config: GeminiOAuthClientConfig(
                    clientID: "__SET_ME__",
                    clientSecret: "secret-value"
                )
            )
        )
        XCTAssertFalse(placeholderRepo.isOAuthClientConfigured())

        let blankSecretRepo = GeminiAuthRepository(
            credentialStore: store,
            oauthConfigProvider: StubGeminiOAuthConfigProvider(
                config: GeminiOAuthClientConfig(
                    clientID: "client-id",
                    clientSecret: "   "
                )
            )
        )
        XCTAssertFalse(blankSecretRepo.isOAuthClientConfigured())
    }

    func testGeminiOAuthConfigValidationAcceptsConcreteValues() {
        let store = InMemoryCredentialStore()
        let repo = GeminiAuthRepository(
            credentialStore: store,
            oauthConfigProvider: StubGeminiOAuthConfigProvider(
                config: GeminiOAuthClientConfig(
                    clientID: "client-id.apps.googleusercontent.com",
                    clientSecret: "client-secret-value"
                )
            )
        )
        XCTAssertTrue(repo.isOAuthClientConfigured())
    }

    func testGeminiLoginWithBrowserFailsFastWhenOAuthMissing() async {
        let store = InMemoryCredentialStore()
        let repo = GeminiAuthRepository(
            credentialStore: store,
            oauthConfigProvider: StubGeminiOAuthConfigProvider(
                config: GeminiOAuthClientConfig(
                    clientID: "",
                    clientSecret: ""
                )
            )
        )

        let result = await repo.loginWithBrowser()
        switch result {
        case .success:
            XCTFail("Expected loginWithBrowser to fail without Gemini OAuth credentials")
        case let .failure(error):
            guard let providerError = error as? ProviderClientError else {
                XCTFail("Unexpected error type: \(error)")
                return
            }
            guard case let .missingCredential(provider) = providerError else {
                XCTFail("Expected missingCredential, got \(providerError)")
                return
            }
            XCTAssertEqual(provider, "GEMINI_OAUTH_CLIENT")
        }
    }
}
