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

private final class CapturingAuthHTTPClient: HTTPClientProtocol {
    var lastRequest: HTTPRequest?
    var responseData: Data
    var statusCode: Int

    init(responseData: Data, statusCode: Int) {
        self.responseData = responseData
        self.statusCode = statusCode
    }

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }

    func stream(_ request: HTTPRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        lastRequest = request
        let response = HTTPURLResponse(
            url: request.url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (AsyncThrowingStream { continuation in continuation.finish() }, response)
    }
}

private final class GeminiCompatibilitySyncHTTPClient: HTTPClientProtocol {
    var responses: [String: (Data, Int)] = [:]
    private(set) var requestedURLs: [String] = []

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url.absoluteString
        requestedURLs.append(url)
        let entry = responses[url] ?? (Data(), 404)
        let response = HTTPURLResponse(
            url: request.url,
            statusCode: entry.1,
            httpVersion: nil,
            headerFields: nil
        )!
        return (entry.0, response)
    }

    func stream(_ request: HTTPRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url,
            statusCode: 404,
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

    func testGeminiQuotaParseSupportsFractionOnlyBuckets() async {
        let store = InMemoryCredentialStore()
        try? store.setGeminiAccessToken("token")
        try? store.saveSecret("my-project", key: "gemini_project_id")

        let payload = """
        {
          "buckets": [
            {
              "remainingFraction": 0.75,
              "resetTime": "2026-02-10T00:00:00Z",
              "tokenType": "REQUESTS",
              "modelId": "gemini-3-pro-preview"
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
            XCTAssertEqual(quota.buckets.first?.modelId, "gemini-3-pro-preview")
            XCTAssertNil(quota.buckets.first?.remainingAmount)
            XCTAssertEqual(quota.buckets.first?.remainingFraction, 0.75)
        case let .failure(error):
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGeminiQuotaUsesOpencodeCompatibleHeaders() async {
        let store = InMemoryCredentialStore()
        try? store.setGeminiAccessToken("token")
        try? store.saveSecret("my-project", key: "gemini_project_id")

        let payload = """
        {
          "buckets": []
        }
        """.data(using: .utf8)!

        let httpClient = CapturingAuthHTTPClient(responseData: payload, statusCode: 200)
        let repo = GeminiAuthRepository(
            credentialStore: store,
            httpClient: httpClient
        )

        let result = await repo.retrieveUserQuota()
        switch result {
        case .success:
            break
        case let .failure(error):
            XCTFail("Unexpected error: \(error)")
        }

        guard let request = httpClient.lastRequest else {
            XCTFail("Expected quota request to be captured")
            return
        }
        XCTAssertEqual(request.headers["Authorization"], "Bearer token")
        XCTAssertEqual(request.headers["Content-Type"], "application/json")
        XCTAssertEqual(
            request.headers["User-Agent"],
            GeminiCliCompatibility.buildUserAgent(model: nil)
        )
        XCTAssertNil(request.headers["X-Goog-Api-Client"])
        XCTAssertNil(request.headers["Client-Metadata"])
        let activityRequestID = request.headers["x-activity-request-id"] ?? ""
        XCTAssertFalse(activityRequestID.isEmpty)
        XCTAssertFalse(activityRequestID.contains("-"))
    }

    func testGeminiCodeAssistProjectIDNormalizationSupportsStringAndObject() {
        XCTAssertEqual(
            GeminiAuthRepository.normalizeCodeAssistProjectID("project-1"),
            "project-1"
        )
        XCTAssertEqual(
            GeminiAuthRepository.normalizeCodeAssistProjectID(["id": "project-2"]),
            "project-2"
        )
        XCTAssertNil(GeminiAuthRepository.normalizeCodeAssistProjectID(["name": "missing-id"]))
        XCTAssertNil(GeminiAuthRepository.normalizeCodeAssistProjectID("   "))
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

    func testGeminiOAuthImportAcceptsCaseInsensitiveKeys() throws {
        let store = InMemoryCredentialStore()
        let repo = GeminiAuthRepository(
            credentialStore: store,
            oauthConfigProvider: StubGeminiOAuthConfigProvider(
                config: GeminiOAuthClientConfig(clientID: "", clientSecret: "")
            )
        )

        let plistURL = try createTemporaryPlistFile(
            dictionary: [
                "gemini_oauth_client_id": "case-client-id",
                "GEMINI_oauth_CLIENT_secret": "case-client-secret"
            ]
        )
        defer { try? FileManager.default.removeItem(at: plistURL) }

        let imported = try repo.importOAuthClientConfig(fileURL: plistURL)
        XCTAssertEqual(imported.clientID, "case-client-id")
        XCTAssertEqual(imported.clientSecret, "case-client-secret")
        XCTAssertTrue(repo.hasImportedOAuthClientConfig())
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

    func testQwenLoginPersistsResourceURLAndNormalizedBaseURL() async {
        let store = InMemoryCredentialStore()
        let repo = QwenAuthRepository(credentialStore: store)

        let result = await repo.login(
            accessToken: "qwen-access-token",
            refreshToken: "qwen-refresh-token",
            expiryDate: 1_730_000_000_000,
            resourceURL: "portal.qwen.ai/inference"
        )

        switch result {
        case let .success(state):
            XCTAssertTrue(state.isLoggedIn)
            XCTAssertEqual(state.resourceURL, "portal.qwen.ai/inference")
            XCTAssertEqual(state.baseURL, "https://portal.qwen.ai/inference/v1")
            XCTAssertEqual((try? store.credential(for: .qwenCode)) ?? nil, "qwen-access-token")
            XCTAssertEqual((try? store.qwenResourceURL()) ?? nil, "portal.qwen.ai/inference")
        case let .failure(error):
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testQwenRefreshUpdatesStoredCredentialAndResourceURL() async {
        let store = InMemoryCredentialStore()
        let seedRepo = QwenAuthRepository(credentialStore: store)
        _ = await seedRepo.login(
            accessToken: "expired-token",
            refreshToken: "refresh-token",
            expiryDate: 1,
            resourceURL: "old.qwen.ai/runtime"
        )

        let payload = """
        {
          "access_token": "fresh-token",
          "refresh_token": "fresh-refresh-token",
          "expires_in": 3600,
          "token_type": "Bearer",
          "resource_url": "new.qwen.ai/runtime"
        }
        """.data(using: .utf8)!
        let httpClient = CapturingAuthHTTPClient(responseData: payload, statusCode: 200)
        let repo = QwenAuthRepository(
            credentialStore: store,
            httpClient: httpClient
        )

        let result = await repo.refreshIfNeeded(force: true)

        switch result {
        case let .success(state):
            XCTAssertTrue(state.isLoggedIn)
            XCTAssertEqual(state.baseURL, "https://new.qwen.ai/runtime/v1")
            XCTAssertEqual((try? store.credential(for: .qwenCode)) ?? nil, "fresh-token")
            XCTAssertEqual((try? store.qwenResourceURL()) ?? nil, "new.qwen.ai/runtime")
            let body = String(data: httpClient.lastRequest?.body ?? Data(), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("grant_type=refresh_token"))
            XCTAssertTrue(body.contains("refresh_token=refresh-token"))
        case let .failure(error):
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGeminiOAuthManualSaveStoresNormalizedValues() throws {
        let store = InMemoryCredentialStore()
        let repo = GeminiAuthRepository(
            credentialStore: store,
            oauthConfigProvider: StubGeminiOAuthConfigProvider(
                config: GeminiOAuthClientConfig(clientID: "", clientSecret: "")
            )
        )

        let saved = try repo.saveOAuthClientConfig(
            clientID: " manual-client-id ",
            clientSecret: " manual-client-secret "
        )

        XCTAssertEqual(saved.clientID, "manual-client-id")
        XCTAssertEqual(saved.clientSecret, "manual-client-secret")
        XCTAssertTrue(repo.hasImportedOAuthClientConfig())
        XCTAssertTrue(repo.isOAuthClientConfigured())
    }

    func testGeminiOAuthManualSaveRejectsPlaceholder() {
        let store = InMemoryCredentialStore()
        let repo = GeminiAuthRepository(
            credentialStore: store,
            oauthConfigProvider: StubGeminiOAuthConfigProvider(
                config: GeminiOAuthClientConfig(clientID: "", clientSecret: "")
            )
        )

        XCTAssertThrowsError(
            try repo.saveOAuthClientConfig(clientID: "__set_me__", clientSecret: "secret")
        )
        XCTAssertFalse(repo.hasImportedOAuthClientConfig())
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

    func testGeminiCliCompatibilitySyncStoresFetchedRemoteValuesWithoutImportingOAuthClient() async throws {
        let store = InMemoryCredentialStore()
        let httpClient = GeminiCompatibilitySyncHTTPClient()
        seedUpstreamCompatibilityResponses(into: httpClient)
        let repo = GeminiAuthRepository(credentialStore: store, httpClient: httpClient)

        let result = await repo.syncGeminiCliCompatibilityFromUpstream()
        let compatibility = try result.get()

        XCTAssertEqual(compatibility.version, "9.9.9-test")
        XCTAssertEqual(compatibility.defaultModel, "gemini-3-flash-preview")
        XCTAssertEqual(compatibility.metadata.ideType, "IDE_TEST")
        XCTAssertEqual(compatibility.metadata.platform, "PLATFORM_TEST")
        XCTAssertEqual(compatibility.metadata.pluginType, "GEMINI_TEST")
        XCTAssertEqual(compatibility.codeAssistEndpoint, "https://example.invalid/code-assist")
        XCTAssertEqual(compatibility.codeAssistVersion, "v9internal")
        XCTAssertEqual(compatibility.requestFormat.systemInstructionFieldName, "systemInstruction")
        XCTAssertNil(compatibility.oauthClient)

        let resolved = repo.currentGeminiCliCompatibility()
        XCTAssertEqual(resolved.source, .remote)
        XCTAssertEqual(resolved.remote.version, "9.9.9-test")
        XCTAssertNotNil(resolved.lastSyncISO8601)
        XCTAssertNil(repo.importedOAuthClientConfig())
        XCTAssertFalse(repo.hasImportedOAuthClientConfig())
        XCTAssertFalse(repo.isOAuthClientConfigured())
        XCTAssertEqual(httpClient.requestedURLs.count, GeminiCliCompatibilityStore.upstreamRawFileURLs.count)
    }

    func testGeminiCliCompatibilitySyncPreservesExistingRemoteValueOnParseFailure() async throws {
        let store = InMemoryCredentialStore()
        let existing = GeminiCliRemoteCompatibility(
            version: "1.2.3-existing",
            defaultModel: "gemini-existing",
            metadata: GeminiCliMetadata(
                ideType: "IDE_EXISTING",
                platform: "PLATFORM_EXISTING",
                pluginType: "GEMINI_EXISTING"
            ),
            codeAssistEndpoint: "https://existing.invalid",
            codeAssistVersion: "v1internal",
            requestFormat: GeminiCliCompatibilityStore.builtIn.requestFormat,
            oauthClient: nil
        )
        try GeminiCliCompatibilityStore.saveRemote(
            existing,
            syncedAtISO8601: "2026-03-31T00:00:00Z",
            using: store
        )

        let httpClient = GeminiCompatibilitySyncHTTPClient()
        seedUpstreamCompatibilityResponses(into: httpClient)
        httpClient.responses[GeminiCliCompatibilityStore.upstreamRawFileURLs["gemini-cli-version.ts"]!.absoluteString] = (Data("invalid".utf8), 200)

        let repo = GeminiAuthRepository(credentialStore: store, httpClient: httpClient)
        _ = try repo.saveOAuthClientConfig(
            clientID: "existing-client-id.apps.googleusercontent.com",
            clientSecret: "existing-client-secret"
        )
        let result = await repo.syncGeminiCliCompatibilityFromUpstream()

        switch result {
        case .success:
            XCTFail("Expected sync failure for invalid upstream payload")
        case .failure:
            break
        }

        let resolved = repo.currentGeminiCliCompatibility()
        XCTAssertEqual(resolved.source, .remote)
        XCTAssertEqual(resolved.remote.version, "1.2.3-existing")
        XCTAssertEqual(resolved.remote.defaultModel, "gemini-existing")
        XCTAssertEqual(resolved.lastSyncISO8601, "2026-03-31T00:00:00Z")
        XCTAssertEqual(
            repo.importedOAuthClientConfig(),
            GeminiOAuthClientConfig(
                clientID: "existing-client-id.apps.googleusercontent.com",
                clientSecret: "existing-client-secret"
            )
        )
    }

    private func seedUpstreamCompatibilityResponses(into httpClient: GeminiCompatibilitySyncHTTPClient) {
        let sources: [String: String] = [
            "gemini-cli-version.ts": #"export const GEMINI_CLI_VERSION = "9.9.9-test""#,
            "user-agent.ts": #"const GEMINI_CLI_DEFAULT_MODEL = "gemini-3-flash-preview""#,
            "project-types.ts": #"""
            export const CODE_ASSIST_METADATA = {
              ideType: "IDE_TEST",
              platform: "PLATFORM_TEST",
              pluginType: "GEMINI_TEST",
            } as const;
            """#,
            "request-prepare.ts": #"""
            const STREAM_ACTION = "streamGenerateContent";
            const transformedUrl = `${GEMINI_CODE_ASSIST_ENDPOINT}/v9internal:${rawAction}${
              streaming ? "?alt=sse" : ""
            }`;
            requestPayload.systemInstruction = requestPayload.system_instruction;
            const wrappedBody = {
              project: projectId,
              model: effectiveModel,
              user_prompt_id: userPromptId,
              request: requestPayload,
            };
            """#,
            "constants.ts": #"""
            export const GEMINI_CLIENT_ID = "test-client-id.apps.googleusercontent.com";
            export const GEMINI_CLIENT_SECRET = "test-client-secret";
            export const GEMINI_CODE_ASSIST_ENDPOINT = "https://example.invalid/code-assist";
            """#
        ]

        for (name, url) in GeminiCliCompatibilityStore.upstreamRawFileURLs {
            if let source = sources[name] {
                httpClient.responses[url.absoluteString] = (Data(source.utf8), 200)
            }
        }
    }
}
