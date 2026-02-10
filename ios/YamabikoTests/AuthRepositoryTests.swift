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

private func createTemporaryBundle(
    infoDictionary: [String: String],
    dedicatedGeminiDictionary: [String: String]? = nil
) throws -> URL {
    let fileManager = FileManager.default
    let bundleURL = fileManager.temporaryDirectory
        .appendingPathComponent("yamabiko-test-\(UUID().uuidString)")
        .appendingPathExtension("bundle")
    try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true, attributes: nil)

    let infoURL = bundleURL.appendingPathComponent("Info.plist")
    let infoNSDictionary = NSDictionary(dictionary: infoDictionary)
    guard infoNSDictionary.write(to: infoURL, atomically: true) else {
        throw NSError(domain: "AuthRepositoryTests", code: 1, userInfo: nil)
    }

    if let dedicatedGeminiDictionary {
        let dedicatedURL = bundleURL.appendingPathComponent("GeminiAuthInfo.plist")
        let dedicatedNSDictionary = NSDictionary(dictionary: dedicatedGeminiDictionary)
        guard dedicatedNSDictionary.write(to: dedicatedURL, atomically: true) else {
            throw NSError(domain: "AuthRepositoryTests", code: 2, userInfo: nil)
        }
    }

    return bundleURL
}

private func createTemporaryPlistFile(dictionary: [String: String]) throws -> URL {
    let fileManager = FileManager.default
    let plistURL = fileManager.temporaryDirectory
        .appendingPathComponent("yamabiko-gemini-oauth-\(UUID().uuidString)")
        .appendingPathExtension("plist")
    let nsDictionary = NSDictionary(dictionary: dictionary)
    guard nsDictionary.write(to: plistURL, atomically: true) else {
        throw NSError(domain: "AuthRepositoryTests", code: 3, userInfo: nil)
    }
    return plistURL
}

final class AuthRepositoryTests: XCTestCase {
    func testBundleGeminiOAuthConfigProviderPrefersDedicatedPlist() throws {
        let bundleURL = try createTemporaryBundle(
            infoDictionary: [
                "CFBundleIdentifier": "test.bundle",
                "GEMINI_OAUTH_CLIENT_ID": "fallback-client-id",
                "GEMINI_OAUTH_CLIENT_SECRET": "fallback-client-secret"
            ],
            dedicatedGeminiDictionary: [
                "GEMINI_OAUTH_CLIENT_ID": "dedicated-client-id",
                "GEMINI_OAUTH_CLIENT_SECRET": "dedicated-client-secret"
            ]
        )
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        guard let bundle = Bundle(url: bundleURL) else {
            XCTFail("Failed to open temporary bundle")
            return
        }
        let provider = BundleGeminiOAuthConfigProvider(bundle: bundle)
        let config = provider.loadOAuthClientConfig()

        XCTAssertEqual(config.clientID, "dedicated-client-id")
        XCTAssertEqual(config.clientSecret, "dedicated-client-secret")
    }

    func testBundleGeminiOAuthConfigProviderFallsBackToInfoPlist() throws {
        let bundleURL = try createTemporaryBundle(
            infoDictionary: [
                "CFBundleIdentifier": "test.bundle",
                "GEMINI_OAUTH_CLIENT_ID": "fallback-client-id",
                "GEMINI_OAUTH_CLIENT_SECRET": "fallback-client-secret"
            ],
            dedicatedGeminiDictionary: nil
        )
        defer { try? FileManager.default.removeItem(at: bundleURL) }

        guard let bundle = Bundle(url: bundleURL) else {
            XCTFail("Failed to open temporary bundle")
            return
        }
        let provider = BundleGeminiOAuthConfigProvider(bundle: bundle)
        let config = provider.loadOAuthClientConfig()

        XCTAssertEqual(config.clientID, "fallback-client-id")
        XCTAssertEqual(config.clientSecret, "fallback-client-secret")
    }

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

    func testGeminiOAuthImportFromFileUsesImportedConfig() throws {
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
        XCTAssertFalse(repo.isOAuthClientConfigured())

        let plistURL = try createTemporaryPlistFile(
            dictionary: [
                "GEMINI_OAUTH_CLIENT_ID": " imported-client-id ",
                "GEMINI_OAUTH_CLIENT_SECRET": " imported-client-secret "
            ]
        )
        defer { try? FileManager.default.removeItem(at: plistURL) }

        let imported = try repo.importOAuthClientConfig(fileURL: plistURL)
        XCTAssertEqual(imported.clientID, "imported-client-id")
        XCTAssertEqual(imported.clientSecret, "imported-client-secret")
        XCTAssertTrue(repo.hasImportedOAuthClientConfig())
        XCTAssertTrue(repo.isOAuthClientConfigured())
    }

    func testGeminiOAuthImportRejectsMissingKeys() throws {
        let store = InMemoryCredentialStore()
        let repo = GeminiAuthRepository(
            credentialStore: store,
            oauthConfigProvider: StubGeminiOAuthConfigProvider(
                config: GeminiOAuthClientConfig(clientID: "", clientSecret: "")
            )
        )

        let plistURL = try createTemporaryPlistFile(
            dictionary: [
                "SOME_OTHER_KEY": "value"
            ]
        )
        defer { try? FileManager.default.removeItem(at: plistURL) }

        XCTAssertThrowsError(try repo.importOAuthClientConfig(fileURL: plistURL))
        XCTAssertFalse(repo.hasImportedOAuthClientConfig())
    }

    func testGeminiOAuthImportedConfigCanBeCleared() throws {
        let store = InMemoryCredentialStore()
        let repo = GeminiAuthRepository(
            credentialStore: store,
            oauthConfigProvider: StubGeminiOAuthConfigProvider(
                config: GeminiOAuthClientConfig(clientID: "", clientSecret: "")
            )
        )

        let plistURL = try createTemporaryPlistFile(
            dictionary: [
                "GEMINI_OAUTH_CLIENT_ID": "client-id",
                "GEMINI_OAUTH_CLIENT_SECRET": "client-secret"
            ]
        )
        defer { try? FileManager.default.removeItem(at: plistURL) }

        _ = try repo.importOAuthClientConfig(fileURL: plistURL)
        XCTAssertTrue(repo.hasImportedOAuthClientConfig())

        try repo.clearImportedOAuthClientConfig()
        XCTAssertFalse(repo.hasImportedOAuthClientConfig())
        XCTAssertFalse(repo.isOAuthClientConfigured())
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
