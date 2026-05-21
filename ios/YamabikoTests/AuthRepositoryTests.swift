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
}
