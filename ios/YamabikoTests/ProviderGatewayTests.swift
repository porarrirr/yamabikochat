import XCTest
import GRDB
@testable import YamabikoChat

private final class GatewayTestCredentialStore: SecureCredentialStore {
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

private struct StaticGeminiOAuthConfigProvider: GeminiOAuthConfigProviding {
    let config: GeminiOAuthClientConfig

    func loadOAuthClientConfig() -> GeminiOAuthClientConfig {
        config
    }
}

private final class GeminiRefreshHTTPClient: HTTPClientProtocol {
    private(set) var refreshCallCount: Int = 0
    private let refreshedToken: String

    init(refreshedToken: String) {
        self.refreshedToken = refreshedToken
    }

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        if request.url.absoluteString == "https://oauth2.googleapis.com/token" {
            refreshCallCount += 1
            let body = """
            {
              "access_token": "\(refreshedToken)",
              "expires_in": 3600,
              "token_type": "Bearer"
            }
            """
            return (Data(body.utf8), Self.makeResponse(url: request.url, statusCode: 200))
        }
        return (Data("{}".utf8), Self.makeResponse(url: request.url, statusCode: 404))
    }

    func stream(_ request: HTTPRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        let stream = AsyncThrowingStream<String, Error> { continuation in
            continuation.finish()
        }
        return (stream, Self.makeResponse(url: request.url, statusCode: 404))
    }

    private static func makeResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}

private final class GeminiGenerateRetryHTTPClient: HTTPClientProtocol {
    private(set) var authorizationHeaders: [String] = []

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        let authHeader = request.headers["Authorization"] ?? ""
        authorizationHeaders.append(authHeader)

        if authorizationHeaders.count == 1 {
            return (Data("{}".utf8), Self.makeResponse(url: request.url, statusCode: 401))
        }

        let body = #"{"response":{"candidates":[{"content":{"parts":[{"text":"generate recovered"}]}}]}}"#
        return (Data(body.utf8), Self.makeResponse(url: request.url, statusCode: 200))
    }

    func stream(_ request: HTTPRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        let stream = AsyncThrowingStream<String, Error> { continuation in
            continuation.finish()
        }
        return (stream, Self.makeResponse(url: request.url, statusCode: 500))
    }

    private static func makeResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}

private final class GeminiStreamRetryHTTPClient: HTTPClientProtocol {
    private(set) var authorizationHeaders: [String] = []

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        return (Data("{}".utf8), Self.makeResponse(url: request.url, statusCode: 500))
    }

    func stream(_ request: HTTPRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        let authHeader = request.headers["Authorization"] ?? ""
        authorizationHeaders.append(authHeader)

        if authorizationHeaders.count == 1 {
            let failed = AsyncThrowingStream<String, Error> { continuation in
                continuation.finish()
            }
            return (failed, Self.makeResponse(url: request.url, statusCode: 401))
        }

        let recovered = AsyncThrowingStream<String, Error> { continuation in
            continuation.yield(#"data: {"response":{"candidates":[{"content":{"parts":[{"text":"stream recovered"}]}}]}}"#)
            continuation.yield("")
            continuation.yield("data: [DONE]")
            continuation.yield("")
            continuation.finish()
        }
        return (recovered, Self.makeResponse(url: request.url, statusCode: 200))
    }

    private static func makeResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}

private final class QwenRefreshHTTPClient: HTTPClientProtocol {
    private(set) var refreshCallCount: Int = 0
    private let refreshedToken: String
    private let refreshedResourceURL: String

    init(refreshedToken: String, refreshedResourceURL: String) {
        self.refreshedToken = refreshedToken
        self.refreshedResourceURL = refreshedResourceURL
    }

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        if request.url.absoluteString == "https://chat.qwen.ai/api/v1/oauth2/token" {
            refreshCallCount += 1
            let body = """
            {
              "access_token": "\(refreshedToken)",
              "refresh_token": "qwen-refresh-token-2",
              "expires_in": 3600,
              "token_type": "Bearer",
              "resource_url": "\(refreshedResourceURL)"
            }
            """
            return (Data(body.utf8), Self.makeResponse(url: request.url, statusCode: 200))
        }
        return (Data("{}".utf8), Self.makeResponse(url: request.url, statusCode: 404))
    }

    func stream(_ request: HTTPRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        let stream = AsyncThrowingStream<String, Error> { continuation in
            continuation.finish()
        }
        return (stream, Self.makeResponse(url: request.url, statusCode: 404))
    }

    private static func makeResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}

private final class QwenGenerateRetryHTTPClient: HTTPClientProtocol {
    private(set) var authorizationHeaders: [String] = []
    private(set) var requestedURLs: [String] = []

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        requestedURLs.append(request.url.absoluteString)
        let authHeader = request.headers["Authorization"] ?? ""
        authorizationHeaders.append(authHeader)

        if authorizationHeaders.count == 1 {
            return (Data("{}".utf8), Self.makeResponse(url: request.url, statusCode: 401))
        }

        let body = #"{"choices":[{"message":{"content":"qwen recovered","reasoning_content":"plan"}}]}"#
        return (Data(body.utf8), Self.makeResponse(url: request.url, statusCode: 200))
    }

    func stream(_ request: HTTPRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        let stream = AsyncThrowingStream<String, Error> { continuation in
            continuation.finish()
        }
        return (stream, Self.makeResponse(url: request.url, statusCode: 500))
    }

    private static func makeResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}

final class ProviderGatewayTests: XCTestCase {
    func testGenerateRetriesGeminiAuthAfter401() async throws {
        let store = GatewayTestCredentialStore()
        try seedGeminiAuthCredentials(store: store, accessToken: "expired-token", refreshToken: "refresh-token")

        let refreshHTTP = GeminiRefreshHTTPClient(refreshedToken: "refreshed-token")
        let geminiAuthRepository = GeminiAuthRepository(
            credentialStore: store,
            httpClient: refreshHTTP,
            oauthConfigProvider: StaticGeminiOAuthConfigProvider(
                config: GeminiOAuthClientConfig(
                    clientID: "client-id.apps.googleusercontent.com",
                    clientSecret: "client-secret"
                )
            )
        )
        let providerHTTP = GeminiGenerateRetryHTTPClient()
        let gateway = try makeGateway(
            store: store,
            geminiAuthRepository: geminiAuthRepository,
            providerHTTPClient: providerHTTP
        )

        let response = try await gateway.generate(
            request: ProviderRequest(
                model: "gemini-2.5-flash",
                messages: [ProviderRequestMessage(role: "user", content: "hello")],
                stream: false
            ),
            provider: .geminiAuth
        )

        XCTAssertEqual(response.text, "generate recovered")
        XCTAssertEqual(providerHTTP.authorizationHeaders.count, 2)
        XCTAssertEqual(providerHTTP.authorizationHeaders.first, "Bearer expired-token")
        XCTAssertEqual(providerHTTP.authorizationHeaders.last, "Bearer refreshed-token")
        XCTAssertEqual(refreshHTTP.refreshCallCount, 1)
    }

    func testStreamRetriesGeminiAuthAfter401() async throws {
        let store = GatewayTestCredentialStore()
        try seedGeminiAuthCredentials(store: store, accessToken: "expired-token", refreshToken: "refresh-token")

        let refreshHTTP = GeminiRefreshHTTPClient(refreshedToken: "refreshed-token")
        let geminiAuthRepository = GeminiAuthRepository(
            credentialStore: store,
            httpClient: refreshHTTP,
            oauthConfigProvider: StaticGeminiOAuthConfigProvider(
                config: GeminiOAuthClientConfig(
                    clientID: "client-id.apps.googleusercontent.com",
                    clientSecret: "client-secret"
                )
            )
        )
        let providerHTTP = GeminiStreamRetryHTTPClient()
        let gateway = try makeGateway(
            store: store,
            geminiAuthRepository: geminiAuthRepository,
            providerHTTPClient: providerHTTP
        )

        let stream = try await gateway.stream(
            request: ProviderRequest(
                model: "gemini-2.5-flash",
                messages: [ProviderRequestMessage(role: "user", content: "hello")],
                stream: true
            ),
            provider: .geminiAuth
        )

        var events: [ProviderStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(providerHTTP.authorizationHeaders.count, 2)
        XCTAssertEqual(providerHTTP.authorizationHeaders.first, "Bearer expired-token")
        XCTAssertEqual(providerHTTP.authorizationHeaders.last, "Bearer refreshed-token")
        XCTAssertEqual(refreshHTTP.refreshCallCount, 1)
        XCTAssertTrue(events.contains(.textDelta("stream recovered")))
        if case let .completed(final) = try XCTUnwrap(events.last) {
            XCTAssertEqual(final.text, "stream recovered")
        } else {
            XCTFail("Expected completed event")
        }
    }

    func testGenerateRetriesQwenCodeAfter401() async throws {
        let store = GatewayTestCredentialStore()
        try seedQwenAuthCredentials(
            store: store,
            accessToken: "expired-qwen-token",
            refreshToken: "refresh-qwen-token",
            resourceURL: "initial.qwen.ai/runtime"
        )

        let refreshHTTP = QwenRefreshHTTPClient(
            refreshedToken: "refreshed-qwen-token",
            refreshedResourceURL: "new.qwen.ai/runtime"
        )
        let qwenAuthRepository = QwenAuthRepository(
            credentialStore: store,
            httpClient: refreshHTTP
        )
        let providerHTTP = QwenGenerateRetryHTTPClient()
        let gateway = try makeGateway(
            store: store,
            qwenAuthRepository: qwenAuthRepository,
            providerHTTPClient: providerHTTP
        )

        let response = try await gateway.generate(
            request: ProviderRequest(
                model: "coder-model",
                messages: [ProviderRequestMessage(role: "user", content: "hello")],
                stream: false
            ),
            provider: .qwenCode
        )

        XCTAssertEqual(response.text, "qwen recovered")
        XCTAssertEqual(response.reasoningSummary, "plan")
        XCTAssertEqual(providerHTTP.authorizationHeaders, ["Bearer expired-qwen-token", "Bearer refreshed-qwen-token"])
        XCTAssertEqual(providerHTTP.requestedURLs, [
            "https://initial.qwen.ai/runtime/v1/chat/completions",
            "https://new.qwen.ai/runtime/v1/chat/completions"
        ])
        XCTAssertEqual(refreshHTTP.refreshCallCount, 1)
    }

    private func makeGateway(
        store: GatewayTestCredentialStore,
        geminiAuthRepository: GeminiAuthRepository? = nil,
        qwenAuthRepository: QwenAuthRepository? = nil,
        providerHTTPClient: HTTPClientProtocol
    ) throws -> ProviderGateway {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)
        let settingsRepository = SettingsRepository(dbQueue: dbQueue)

        var settings = try settingsRepository.load()
        if qwenAuthRepository != nil {
            settings.apiProvider = "QWEN_CODE"
            settings.defaultModel = "coder-model"
            settings.providerDefaultModelsJSON = #"{"QWEN_CODE":"coder-model"}"#
        } else {
            settings.apiProvider = "GEMINI_AUTH"
            settings.defaultModel = "gemini-2.5-flash"
            settings.providerDefaultModelsJSON = #"{"GEMINI_AUTH":"gemini-2.5-flash"}"#
        }
        try settingsRepository.save(settings)

        return ProviderGateway(
            settingsRepository: settingsRepository,
            credentialStore: store,
            geminiAuthRepository: geminiAuthRepository,
            qwenAuthRepository: qwenAuthRepository,
            httpClient: providerHTTPClient
        )
    }

    private func seedGeminiAuthCredentials(
        store: GatewayTestCredentialStore,
        accessToken: String,
        refreshToken: String
    ) throws {
        try store.setGeminiAccessToken(accessToken)
        try store.saveSecret("project-1", key: "gemini_project_id")
        let now = ISO8601DateFormatter().string(from: Date())
        let expires = ISO8601DateFormatter().string(from: Date().addingTimeInterval(3600))
        let auth = GeminiAuthJSON(
            tokens: GeminiTokenData(
                accessToken: accessToken,
                refreshToken: refreshToken,
                idToken: nil,
                expiresIn: 3600,
                scope: nil,
                tokenType: "Bearer"
            ),
            lastRefresh: now,
            accessExpiresAt: expires,
            userEmail: "user@example.com",
            projectId: "project-1",
            userTier: nil,
            userTierName: nil
        )
        let data = try JSONEncoder().encode(auth)
        try store.saveSecret(String(decoding: data, as: UTF8.self), key: "gemini_auth_json_v2")
    }

    private func seedQwenAuthCredentials(
        store: GatewayTestCredentialStore,
        accessToken: String,
        refreshToken: String,
        resourceURL: String
    ) throws {
        try store.setCredential(accessToken, for: .qwenCode)
        try store.setQwenResourceURL(resourceURL)
        let auth = QwenAuthJSON(
            accessToken: accessToken,
            refreshToken: refreshToken,
            tokenType: "Bearer",
            scope: "openid profile email model.completion",
            resourceURL: resourceURL,
            expiryDate: Int64(Date().addingTimeInterval(3600).timeIntervalSince1970 * 1000),
            lastRefresh: ISO8601DateFormatter().string(from: Date())
        )
        let data = try JSONEncoder().encode(auth)
        try store.saveSecret(String(decoding: data, as: UTF8.self), key: "qwen_auth_json_v1")
    }
}
