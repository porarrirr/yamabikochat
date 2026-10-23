import XCTest
@testable import YamabikoChat

final class SuperGrokAuthRepositoryTests: XCTestCase {
    func testDeviceCodeLoginUsesPiGrokAndPublishesChallenge() async throws {
        let store = PiAuthTestCredentialStore()
        let repo = SuperGrokAuthRepository(
            credentialStore: store,
            loginHandler: { provider, method, onDeviceCode in
                XCTAssertEqual(provider, .supergrok)
                XCTAssertEqual(method, .device)
                await onDeviceCode?(
                    SuperGrokDeviceCodeChallenge(
                        verificationURI: "https://accounts.x.ai/device",
                        userCode: "ABCD-EFGH",
                        browserURL: "https://accounts.x.ai/device"
                    )
                )
                return oauthResolution(accountID: nil)
            },
            resolveHandler: { _, _, _ in oauthResolution(accountID: nil) }
        )

        guard case let .success(state) = await repo.loginWithDeviceCode() else {
            return XCTFail("Expected pi-grok login success")
        }
        XCTAssertTrue(state.isLoggedIn)
        XCTAssertEqual(state.email, "user@example.com")
        XCTAssertNotNil(try store.readSecret(key: "pi_oauth_supergrok_v1"))
        XCTAssertNil(try store.readSecret(key: "supergrok_access_token"))
    }

    func testSuperGrokModelCatalogIncludesPiGrokModels() {
        XCTAssertEqual(SuperGrokModelCatalog.normalizedModelID("supergrok/grok-4.3"), "grok-4.3")
        XCTAssertEqual(SuperGrokModelCatalog.model(for: "grok-4.5")?.supportsReasoning, true)
        XCTAssertEqual(SuperGrokModelCatalog.defaultModel, "grok-4.5")
    }

    func testLogoutClearsRuntimeAndLocalCredential() async throws {
        let store = PiAuthTestCredentialStore()
        let cleared = expectation(description: "runtime logout")
        let repo = SuperGrokAuthRepository(credentialStore: store,
            loginHandler: { _, _, _ in oauthResolution(accountID: nil) },
            revokeHandler: { credential in XCTAssertTrue(credential.contains("refresh-token")) },
            logoutHandler: { cleared.fulfill() })
        guard case .success = await repo.loginWithBrowser() else { return XCTFail("login") }
        guard case .success = await repo.logout() else { return XCTFail("logout") }
        await fulfillment(of: [cleared], timeout: 1)
        XCTAssertNil(try store.readSecret(key: "pi_oauth_supergrok_v1"))
        XCTAssertFalse(repo.hasAuthToken())
    }

    func testRuntimeLogoutFailureStillRemovesLocalTokensAndIsReported() async throws {
        let store = PiAuthTestCredentialStore()
        let repo = SuperGrokAuthRepository(credentialStore: store,
            loginHandler: { _, _, _ in oauthResolution(accountID: nil) },
            revokeHandler: { _ in },
            logoutHandler: { throw URLError(.cannotConnectToHost) })
        _ = await repo.loginWithBrowser()
        guard case .failure = await repo.logout() else { return XCTFail("Runtime cleanup failure must be reported") }
        XCTAssertNil(try store.readSecret(key: "pi_oauth_supergrok_v1"))
        XCTAssertFalse(repo.currentState().isLoggedIn)
    }

    func testRevocationFailureStillCleansRuntimeAndKeychainAndReportsUnconfirmedState() async throws {
        let store = PiAuthTestCredentialStore()
        let cleanup = expectation(description: "runtime cleanup")
        let repo = SuperGrokAuthRepository(credentialStore: store,
            loginHandler: { _, _, _ in oauthResolution(accountID: nil) },
            revokeHandler: { _ in throw URLError(.notConnectedToInternet) },
            logoutHandler: { cleanup.fulfill() })
        _ = await repo.loginWithBrowser()
        guard case let .success(state) = await repo.logout() else { return XCTFail("Expected local sign-out") }
        await fulfillment(of: [cleanup], timeout: 1)
        XCTAssertTrue(state.revocationUnconfirmed)
        XCTAssertFalse(state.isLoggedIn)
        XCTAssertNil(try store.readSecret(key: "pi_oauth_supergrok_v1"))
        XCTAssertNil(try store.readSecret(key: "supergrok_email"))
    }
}
