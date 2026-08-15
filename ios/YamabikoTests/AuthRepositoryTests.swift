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
            loginHandler: { provider, method, _ in
                XCTAssertEqual(provider, .codex)
                XCTAssertEqual(method, .browser)
                return oauthResolution()
            },
            resolveHandler: { _, _, _ in oauthResolution() }
        )

        let result = await repo.loginWithBrowser()
        guard case let .success(state) = result else { return XCTFail("Expected Pi login success") }
        XCTAssertTrue(state.isLoggedIn)
        XCTAssertFalse(state.hasApiKey)
        XCTAssertEqual(state.email, "user@example.com")
        XCTAssertEqual(state.accountId, "acc_123")
        XCTAssertNotNil(try store.readSecret(key: "pi_oauth_openai_codex_v1"))
        XCTAssertNil(try store.readSecret(key: "codex_access_token"))
    }

    func testCodexResolutionPersistsRotatedPiCredential() async throws {
        let store = PiAuthTestCredentialStore()
        try store.saveSecret(
            try PiAgentRuntime.credentialJSONString(oauthResolution().credential),
            key: "pi_oauth_openai_codex_v1"
        )
        let repo = CodexAuthRepository(
            credentialStore: store,
            loginHandler: { _, _, _ in oauthResolution() },
            resolveHandler: { provider, _, force in
                XCTAssertEqual(provider, .codex)
                XCTAssertTrue(force)
                return oauthResolution(access: "rotated-token")
            }
        )

        guard case let .success(state) = await repo.refreshIfNeeded(force: true) else {
            return XCTFail("Expected Pi refresh success")
        }
        XCTAssertTrue(state.isLoggedIn)
        let stored = try XCTUnwrap(store.readSecret(key: "pi_oauth_openai_codex_v1"))
        XCTAssertTrue(stored.contains("rotated-token"))
    }
}
