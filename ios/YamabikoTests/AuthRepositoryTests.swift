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

private struct CodexRefreshFailureHTTPClient: HTTPClientProtocol {
    let body: String
    let statusCode: Int

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (Data(body.utf8), response)
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

    func testCodexRefreshErrorClassification() {
        let body = """
        {
          "error": {
            "message": "Your session has ended. Please log in again.",
            "type": "invalid_request_error",
            "param": null,
            "code": "refresh_token_invalidated"
          }
        }
        """

        XCTAssertEqual(
            CodexAuthRefreshError.extractErrorCode(from: body),
            "refresh_token_invalidated"
        )
        XCTAssertEqual(CodexAuthRefreshError.classified(from: body), .invalidated)
    }

    func testCodexUnrecoverableRefreshClearsOAuthTokens() async throws {
        let store = InMemoryCredentialStore()
        let tokens = CodexTokenData(
            idToken: "id-token",
            accessToken: "access-token",
            refreshToken: "refresh-token",
            accountId: "acc_123"
        )
        let auth = CodexAuthJSON(
            openAIAPIKey: nil,
            tokens: tokens,
            lastRefresh: "2020-01-01T00:00:00Z"
        )
        let authData = try JSONEncoder().encode(auth)
        try store.saveSecret(String(decoding: authData, as: UTF8.self), key: "codex_auth_json_v2")
        try store.setCodexAccessToken("access-token")
        try store.saveSecret("2020-01-01T00:00:00Z", key: "codex_last_refresh")

        let failureBody = """
        {
          "error": {
            "message": "Your session has ended. Please log in again.",
            "code": "refresh_token_invalidated"
          }
        }
        """
        let repo = CodexAuthRepository(
            credentialStore: store,
            httpClient: CodexRefreshFailureHTTPClient(body: failureBody, statusCode: 401)
        )

        let result = await repo.refreshIfNeeded(force: true)

        guard case let .failure(error as CodexAuthRefreshError) = result else {
            return XCTFail("Expected CodexAuthRefreshError failure")
        }
        XCTAssertEqual(error, .invalidated)

        let state = repo.currentState()
        XCTAssertFalse(state.isLoggedIn)

        let rawAuth = try store.readSecret(key: "codex_auth_json_v2")
        XCTAssertNil(rawAuth)
        XCTAssertNil(try store.codexAccessToken())
    }

    func testCodexRefreshPreservesApiKeyAfterUnrecoverableFailure() async throws {
        let store = InMemoryCredentialStore()
        let tokens = CodexTokenData(
            idToken: "id-token",
            accessToken: "access-token",
            refreshToken: "refresh-token",
            accountId: "acc_123"
        )
        let auth = CodexAuthJSON(
            openAIAPIKey: "sk-codex",
            tokens: tokens,
            lastRefresh: "2020-01-01T00:00:00Z"
        )
        let authData = try JSONEncoder().encode(auth)
        try store.saveSecret(String(decoding: authData, as: UTF8.self), key: "codex_auth_json_v2")
        try store.setCredential("sk-codex", for: .codexAuth)
        try store.setCodexAccessToken("access-token")
        try store.saveSecret("2020-01-01T00:00:00Z", key: "codex_last_refresh")

        let failureBody = """
        {
          "error": {
            "code": "refresh_token_invalidated"
          }
        }
        """
        let repo = CodexAuthRepository(
            credentialStore: store,
            httpClient: CodexRefreshFailureHTTPClient(body: failureBody, statusCode: 401)
        )

        let result = await repo.refreshIfNeeded(force: true)
        guard case let .failure(error as CodexAuthRefreshError) = result else {
            return XCTFail("Expected CodexAuthRefreshError failure")
        }
        XCTAssertEqual(error, .invalidated)

        let state = repo.currentState()
        XCTAssertTrue(state.hasApiKey)
        XCTAssertTrue(state.isLoggedIn)

        let persisted = try store.readSecret(key: "codex_auth_json_v2")
        let decoded = try JSONDecoder().decode(CodexAuthJSON.self, from: Data((persisted ?? "").utf8))
        XCTAssertEqual(decoded.openAIAPIKey, "sk-codex")
        XCTAssertNil(decoded.tokens)
        XCTAssertNil(try store.codexAccessToken())
    }
}
