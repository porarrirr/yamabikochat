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

    func testSavedAccountsAreKeptSeparateAcrossSwitches() async throws {
        let store = PiAuthTestCredentialStore()
        let first = CodexAuthRepository(credentialStore: store, loginHandler: { host, _, _ in chatGPTResolution(hostID: host) })
        _ = await first.loginWithBrowser()
        let second = CodexAuthRepository(credentialStore: store, loginHandler: { host, registration, _ in
            XCTAssertNil(registration)
            return chatGPTResolution(access: "second-access", clientID: "oaiapp_second", hostID: host)
        })
        _ = await second.loginWithBrowser(newAccount: true)
        XCTAssertEqual(second.currentState().savedAccounts.count, 2)
        XCTAssertEqual(second.currentState().accountId, "oaiapp_second")
        let returning = CodexAuthRepository(credentialStore: store, loginHandler: { host, registration, _ in
            XCTAssertTrue(registration?.contains("oaiapp_test") == true)
            XCTAssertFalse(registration?.contains("second-access") == true)
            return chatGPTResolution(hostID: host)
        })
        _ = await returning.loginWithBrowser(clientID: "oaiapp_test")
        XCTAssertEqual(returning.currentState().accountId, "oaiapp_test")
        XCTAssertEqual(returning.currentState().savedAccounts.count, 2)
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
