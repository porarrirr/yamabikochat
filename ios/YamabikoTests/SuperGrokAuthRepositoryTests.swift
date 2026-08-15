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
}
