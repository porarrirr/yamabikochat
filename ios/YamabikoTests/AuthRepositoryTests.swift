import XCTest
@testable import YamabikoChat

final class PiAuthTestCredentialStore: SecureCredentialStore {
    private var storage: [String: String] = [:]

    func saveSecret(_ value: String?, key: String) throws {
        if let value { storage[key] = value } else { storage.removeValue(forKey: key) }
    }

    func readSecret(key: String) throws -> String? { storage[key] }
    func deleteSecret(key: String) throws { storage.removeValue(forKey: key) }
}

func oauthResolution(
    access: String = "access-token",
    email: String = "user@example.com",
    accountID: String? = "acc_123"
) -> PiOAuthResolution {
    PiOAuthResolution(
        credential: .object([
            "type": .string("oauth"),
            "access": .string(access),
            "refresh": .string("refresh-token"),
            "expires": .number(4_102_444_800_000),
            "accountId": accountID.map(JSONValue.string) ?? .null
        ]),
        accessToken: access,
        accountId: accountID,
        profile: PiOAuthProfile(email: email, planType: "plus", accountId: accountID)
    )
}

final class AuthRepositoryTests: XCTestCase {
    func testCodexLoginUsesPiAndPersistsOpaqueCredential() async throws {
        let store = PiAuthTestCredentialStore()
        let repo = CodexAuthRepository(
            credentialStore: store,
            loginHandler: { hostID, registration, onRegistration in
                XCTAssertTrue(hostID.hasPrefix("urn:uuid:"))
                XCTAssertNil(registration)
                try await onRegistration(.object(["clientId": .string("oaiapp_test"), "hostId": .string(hostID)]))
                return chatGPTResolution(hostID: hostID)
            },
            resolveHandler: { _, _, _ in chatGPTResolution() }
        )

        let result = await repo.loginWithBrowser()
        guard case let .success(state) = result else { return XCTFail("Expected Pi login success") }
        XCTAssertTrue(state.isLoggedIn)
        XCTAssertFalse(state.hasApiKey)
        XCTAssertEqual(state.email, "user@example.com")
        XCTAssertEqual(state.accountId, "oaiapp_test")
        XCTAssertTrue(state.planUsageEnabled)
        XCTAssertNotNil(try store.readSecret(key: "pi_chatgpt_accounts_v1"))
        XCTAssertNil(try store.readSecret(key: "pi_oauth_openai_codex_v1"))
        XCTAssertNil(try store.readSecret(key: "codex_access_token"))
    }

    func testCancelledLoginDoesNotPersistLateCredentialsAndCanRetry() async throws {
        let store = PiAuthTestCredentialStore()
        let repo = CodexAuthRepository(credentialStore: store, loginHandler: { host, _, _ in
            // Simulate a provider returning a result after cancellation.
            withUnsafeCurrentTask { $0?.cancel() }
            return chatGPTResolution(hostID: host)
        })
        let result = await Task { await repo.loginWithBrowser() }.value
        guard case let .failure(error) = result else { return XCTFail("Cancelled login succeeded") }
        XCTAssertTrue(error is CancellationError)
        XCTAssertFalse(repo.currentState().isLoggedIn)
        XCTAssertNil(try store.readSecret(key: "pi_chatgpt_accounts_v1"))
        let retry = CodexAuthRepository(credentialStore: store, loginHandler: { host, _, _ in
            chatGPTResolution(hostID: host)
        })
        guard case .success = await retry.loginWithBrowser() else { return XCTFail("Retry failed") }
        XCTAssertTrue(retry.currentState().planUsageEnabled)
    }

    func testCodexResolutionPersistsRotatedPiCredential() async throws {
        let store = PiAuthTestCredentialStore()
        let repo = CodexAuthRepository(
            credentialStore: store,
            loginHandler: { hostID, _, _ in chatGPTResolution(hostID: hostID) },
            resolveHandler: { provider, _, force in
                XCTAssertEqual(provider, .chatgpt)
                XCTAssertTrue(force)
                return chatGPTResolution(access: "rotated-token")
            }
        )
        _ = await repo.loginWithBrowser()
        guard case let .success(state) = await repo.refreshIfNeeded(force: true) else {
            return XCTFail("Expected Pi refresh success")
        }
        XCTAssertTrue(state.isLoggedIn)
        let stored = try XCTUnwrap(store.readSecret(key: "pi_chatgpt_accounts_v1"))
        XCTAssertTrue(stored.contains("rotated-token"))
    }

    func testLegacyCodexCredentialsRequireReauthorizationAndAreNeverResolved() async throws {
        let store = PiAuthTestCredentialStore()
        try store.saveSecret("legacy credential", key: "pi_oauth_openai_codex_v1")
        let repo = CodexAuthRepository(credentialStore: store, resolveHandler: { _, _, _ in
            XCTFail("Legacy Codex token must not use the new flow")
            return chatGPTResolution()
        })
        XCTAssertFalse(repo.currentState().isLoggedIn)
        XCTAssertTrue(repo.currentState().requiresReauthentication)
        let token = await repo.getBearerToken()
        XCTAssertNil(token)
    }

    func testIssuedRegistrationSurvivesFailedCodeExchange() async throws {
        let store = PiAuthTestCredentialStore()
        let repo = CodexAuthRepository(credentialStore: store, loginHandler: { host, _, save in
            try await save(.object(["clientId": .string("oaiapp_issued"), "hostId": .string(host)]))
            throw ProviderClientError.parseFailure("invalid_grant")
        })
        _ = await repo.loginWithBrowser()
        XCTAssertFalse(repo.currentState().isLoggedIn)
        let reconnect = CodexAuthRepository(credentialStore: store, loginHandler: { host, registration, _ in
            XCTAssertTrue(registration?.contains("oaiapp_issued") == true)
            return chatGPTResolution(clientID: "oaiapp_issued", hostID: host)
        })
        _ = await reconnect.loginWithBrowser()
        XCTAssertTrue(reconnect.currentState().isLoggedIn)
    }

    func testLogoutRetainsRegistrationAndHostButClearsTokensAndLoginHint() async throws {
        let store = PiAuthTestCredentialStore()
        let repo = CodexAuthRepository(
            credentialStore: store,
            loginHandler: { host, _, _ in chatGPTResolution(hostID: host) },
            revokeHandler: { credential in XCTAssertTrue(credential.contains("refresh-token")) }
        )
        _ = await repo.loginWithBrowser()
        let host = try store.readSecret(key: "pi_chatgpt_host_v1")
        guard case let .success(state) = await repo.logout() else { return XCTFail("Expected sign-out") }
        XCTAssertFalse(state.isLoggedIn)
        XCTAssertFalse(state.revocationUnconfirmed)
        let saved = try XCTUnwrap(store.readSecret(key: "pi_chatgpt_accounts_v1"))
        XCTAssertTrue(saved.contains("oaiapp_test"))
        for secret in ["access-token", "refresh-token", "id-token-hint"] { XCTAssertFalse(saved.contains(secret)) }
        XCTAssertEqual(try store.readSecret(key: "pi_chatgpt_host_v1"), host)
    }

    func testUnconfirmedRevocationIsReportedAndLocalTokensAreCleared() async {
        let repo = CodexAuthRepository(
            credentialStore: PiAuthTestCredentialStore(),
            loginHandler: { host, _, _ in chatGPTResolution(hostID: host) },
            revokeHandler: { _ in throw URLError(.notConnectedToInternet) }
        )
        _ = await repo.loginWithBrowser()
        guard case let .success(state) = await repo.logout() else { return XCTFail("Expected local sign-out") }
        XCTAssertTrue(state.revocationUnconfirmed)
        XCTAssertFalse(state.isLoggedIn)
        XCTAssertFalse(repo.hasAuthToken())
    }

    func testIdentityOnlySignInDoesNotEnablePlanRequests() async {
        let repo = CodexAuthRepository(credentialStore: PiAuthTestCredentialStore(), loginHandler: { host, _, _ in
            chatGPTResolution(hostID: host, planEnabled: false)
        }, resolveHandler: { _, _, _ in XCTFail("No plan permission"); return chatGPTResolution() })
        _ = await repo.loginWithBrowser()
        XCTAssertTrue(repo.currentState().isLoggedIn)
        XCTAssertFalse(repo.currentState().planUsageEnabled)
        let token = await repo.getBearerToken()
        XCTAssertNil(token)
    }

    func testReconnectUsesSavedRegistration() async throws {
        let store = PiAuthTestCredentialStore()
        let first = CodexAuthRepository(credentialStore: store, loginHandler: { host, _, _ in chatGPTResolution(hostID: host) })
        guard case .success = await first.loginWithBrowser() else { return XCTFail("Expected initial sign-in") }
        let returning = CodexAuthRepository(credentialStore: store, loginHandler: { host, registration, _ in
            XCTAssertTrue(registration?.contains("oaiapp_test") == true)
            XCTAssertTrue(registration?.contains("access-token") == true)
            return chatGPTResolution(access: "reconnected-access", hostID: host)
        })
        guard case let .success(state) = await returning.loginWithBrowser() else { return XCTFail("Expected reconnect") }
        XCTAssertEqual(state.accountId, "oaiapp_test")
        XCTAssertTrue(state.isLoggedIn)
        XCTAssertTrue(try XCTUnwrap(store.readSecret(key: "pi_chatgpt_accounts_v1")).contains("reconnected-access"))
    }

    func testConcurrentTokenResolutionPersistsOneRotation() async throws {
        let counter = ChatGPTRefreshCounter()
        let repo = CodexAuthRepository(
            credentialStore: PiAuthTestCredentialStore(),
            loginHandler: { host, _, _ in chatGPTResolution(hostID: host) },
            resolveHandler: { _, _, _ in
                await counter.increment()
                try await Task.sleep(for: .milliseconds(50))
                return chatGPTResolution(access: "rotated-access")
            }
        )
        _ = await repo.loginWithBrowser()
        let tokens = await withTaskGroup(of: CodexAuthRepository.BearerToken?.self) { group in
            for _ in 0 ..< 6 { group.addTask { await repo.getBearerToken() } }
            var results: [CodexAuthRepository.BearerToken?] = []
            for await token in group { results.append(token) }
            return results
        }
        let count = await counter.count
        XCTAssertEqual(count, 1)
        XCTAssertTrue(tokens.allSatisfy { $0?.token == "rotated-access" })
    }

    func testModelsPassesCatalogContractsThroughToPi() async throws {
        let calls = CatalogCallRecorder()
        let repo = CodexAuthRepository(
            credentialStore: PiAuthTestCredentialStore(),
            loginHandler: { host, _, _ in chatGPTResolution(hostID: host) },
            resolveHandler: { _, _, _ in chatGPTResolution() },
            catalogHandler: { _, contracts in
                await calls.record(contracts)
                return [PiCodexModel(id: "gpt-6.1-sol", name: "GPT 6.1 Sol", supported: true)]
            }
        )
        _ = await repo.loginWithBrowser()
        let contract = PiCatalogModelContract(
            npm: "@ai-sdk/openai",
            api: "https://api.openai.com/v1",
            provenance: "provider",
            reasoning: true,
            input: ["text", "image"],
            contextWindow: 1_050_000,
            maxTokens: 128_000,
            reasoningEfforts: ["low", "medium", "high", "xhigh", "max"]
        )

        let models = try await repo.models(contracts: ["gpt-6.1-sol": contract])

        XCTAssertEqual(models.map(\.id), ["gpt-6.1-sol"])
        XCTAssertEqual(repo.cachedModels().map(\.id), ["gpt-6.1-sol"])
        let sentContracts = await calls.contracts
        XCTAssertEqual(sentContracts.count, 1)
        XCTAssertEqual(sentContracts.first?["gpt-6.1-sol"]?.reasoningEfforts, ["low", "medium", "high", "xhigh", "max"])
    }

    func testFailedCatalogRequestKeepsTheLastSuccessfulCache() async throws {
        let mode = CatalogFailureMode()
        let repo = CodexAuthRepository(
            credentialStore: PiAuthTestCredentialStore(),
            loginHandler: { host, _, _ in chatGPTResolution(hostID: host) },
            resolveHandler: { _, _, _ in chatGPTResolution() },
            catalogHandler: { _, _ in
                if await mode.isFailing { throw URLError(.notConnectedToInternet) }
                return [PiCodexModel(id: "gpt-6.1-sol", name: "GPT 6.1 Sol", supported: true)]
            }
        )
        _ = await repo.loginWithBrowser()
        _ = try await repo.models(contracts: [:])
        await mode.setFailing(true)

        do {
            _ = try await repo.models(contracts: [:])
            XCTFail("Expected catalog failure")
        } catch {
            XCTAssertTrue(repo.cachedModels().contains(where: { $0.id == "gpt-6.1-sol" }))
        }
    }

    func testCatalogCacheSurvivesRepositoryRecreationWithExactPiMetadata() async throws {
        let store = PiAuthTestCredentialStore()
        let models = [
            PiCodexModel(id: "supported", name: "Account name", supported: true, supportedThinkingLevels: ["high", "max"]),
            PiCodexModel(id: "future", name: "Future", supported: false, reason: "pi_model_missing")
        ]
        let repo = CodexAuthRepository(
            credentialStore: store,
            loginHandler: { host, _, _ in chatGPTResolution(hostID: host) },
            resolveHandler: { _, _, _ in chatGPTResolution() },
            catalogHandler: { _, _ in models },
            revokeHandler: { _ in }
        )
        _ = await repo.loginWithBrowser()
        _ = try await repo.models(contracts: [:])

        let restored = CodexAuthRepository(credentialStore: store)
        XCTAssertEqual(restored.cachedModels(), models)
        XCTAssertEqual(restored.freshCachedModels(), models)

        _ = await repo.logout()
        XCTAssertTrue(CodexAuthRepository(credentialStore: store).cachedModels().isEmpty)
    }

    func testExpiredCatalogRemainsAvailableForDisplayButRequiresRefresh() async throws {
        let store = PiAuthTestCredentialStore()
        let repo = CodexAuthRepository(
            credentialStore: store,
            loginHandler: { host, _, _ in chatGPTResolution(hostID: host) },
            resolveHandler: { _, _, _ in chatGPTResolution() },
            catalogHandler: { _, _ in [PiCodexModel(id: "model", name: "Model", supported: true)] }
        )
        _ = await repo.loginWithBrowser()
        _ = try await repo.models(contracts: [:])
        let json = try XCTUnwrap(store.readSecret(key: "pi_chatgpt_catalog_v1"))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        object["fetchedAt"] = Date().addingTimeInterval(-3600).timeIntervalSinceReferenceDate
        try store.saveSecret(String(decoding: JSONSerialization.data(withJSONObject: object), as: UTF8.self), key: "pi_chatgpt_catalog_v1")

        let restored = CodexAuthRepository(credentialStore: store)
        XCTAssertEqual(restored.cachedModels().map(\.id), ["model"])
        XCTAssertNil(restored.freshCachedModels())

        object["accountID"] = "different-account"
        try store.saveSecret(String(decoding: JSONSerialization.data(withJSONObject: object), as: UTF8.self), key: "pi_chatgpt_catalog_v1")
        XCTAssertTrue(CodexAuthRepository(credentialStore: store).cachedModels().isEmpty)
    }

    func testLogoutClearsTheCatalogCache() async throws {
        let store = PiAuthTestCredentialStore()
        let repo = CodexAuthRepository(
            credentialStore: store,
            loginHandler: { host, _, _ in chatGPTResolution(hostID: host) },
            resolveHandler: { _, _, _ in chatGPTResolution() },
            catalogHandler: { _, _ in [PiCodexModel(id: "gpt-6.1-sol", name: "Sol", supported: true)] },
            revokeHandler: { _ in }
        )
        _ = await repo.loginWithBrowser()
        _ = try await repo.models(contracts: [:])
        XCTAssertFalse(repo.cachedModels().isEmpty)

        _ = await repo.logout()

        XCTAssertTrue(repo.cachedModels().isEmpty)
    }

    func testStaleGenerationCatalogResultDoesNotPopulateCache() async throws {
        let gate = CatalogGate()
        let repo = CodexAuthRepository(
            credentialStore: PiAuthTestCredentialStore(),
            loginHandler: { host, _, _ in chatGPTResolution(hostID: host) },
            resolveHandler: { _, _, _ in chatGPTResolution() },
            catalogHandler: { _, _ in
                await gate.wait()
                return [PiCodexModel(id: "stale-model", name: "Stale", supported: true)]
            },
            revokeHandler: { _ in }
        )
        _ = await repo.loginWithBrowser()

        let fetch = Task { try await repo.models(contracts: [:]) }
        await gate.waitUntilStarted()
        _ = await repo.logout()
        await gate.resume()

        do {
            _ = try await fetch.value
            XCTFail("Expected stale catalog result to be discarded")
        } catch {
            XCTAssertTrue(repo.cachedModels().isEmpty)
        }
    }
}

private actor CatalogCallRecorder {
    private(set) var contracts: [[String: PiCatalogModelContract]] = []
    func record(_ value: [String: PiCatalogModelContract]) {
        contracts.append(value)
    }
}

private actor CatalogFailureMode {
    private(set) var isFailing = false
    func setFailing(_ value: Bool) { isFailing = value }
}

private actor CatalogGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var startedContinuations: [CheckedContinuation<Void, Never>] = []
    private var started = false
    private var open = false

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            if started { continuation.resume() } else { startedContinuations.append(continuation) }
        }
    }

    func wait() async {
        started = true
        for continuation in startedContinuations { continuation.resume() }
        startedContinuations.removeAll()
        if open { return }
        await withCheckedContinuation { continuation in
            if open { continuation.resume() } else { self.continuation = continuation }
        }
    }

    func resume() {
        open = true
        continuation?.resume()
        continuation = nil
    }
}

private actor ChatGPTRefreshCounter {
    private(set) var count = 0
    func increment() { count += 1 }
}

func chatGPTResolution(
    access: String = "access-token", clientID: String = "oaiapp_test",
    hostID: String = "urn:uuid:12345678-1234-4123-8123-123456789abc", planEnabled: Bool = true
) -> PiOAuthResolution {
    PiOAuthResolution(
        credential: .object([
            "type": .string("oauth"), "contract": .string("siwc-v1"),
            "access": .string(access), "refresh": .string("refresh-token"),
            "expires": .number(4_102_444_800_000), "clientId": .string(clientID),
            "hostId": .string(hostID), "issuer": .string("https://auth.openai.com"),
            "subject": .string("subject-1"), "email": .string("user@example.com"),
            "idToken": .string("id-token-hint"),
            "scopes": .array(planEnabled ? [.string("chatgpt.tokens.use.direct")] : [.string("openid")])
        ]), accessToken: access, accountId: clientID,
        profile: PiOAuthProfile(email: "user@example.com", planType: nil, accountId: clientID, planUsageEnabled: planEnabled)
    )
}
