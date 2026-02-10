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

final class AuthRepositoryTests: XCTestCase {
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
}