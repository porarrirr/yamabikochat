import XCTest
import GRDB
@testable import YamabikoChat

private final class ProviderGatewayCredentialStore: SecureCredentialStore {
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

private final class ProviderGatewayHTTPClient: HTTPClientProtocol {
    var sentRequests: [HTTPRequest] = []
    var streamedRequests: [HTTPRequest] = []
    var sendResponder: ((HTTPRequest) throws -> (Data, HTTPURLResponse))?
    var streamResponder: ((HTTPRequest) throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse))?

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        sentRequests.append(request)
        guard let sendResponder else {
            throw ProviderClientError.invalidResponse
        }
        return try sendResponder(request)
    }

    func stream(_ request: HTTPRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        streamedRequests.append(request)
        guard let streamResponder else {
            throw ProviderClientError.invalidResponse
        }
        return try streamResponder(request)
    }
}

final class ProviderGatewayTests: XCTestCase {
    func testGenerateInjectsRequestedProviderBeforeClientResolvesEndpoint() async throws {
        let fixture = try makeFixture()
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)

        fixture.httpClient.sendResponder = { request in
            let data = #"{"choices":[{"message":{"content":"gateway ok"}}],"usage":{"prompt_tokens":2,"completion_tokens":3}}"#
                .data(using: .utf8)!
            return (data, Self.httpResponse(url: request.url, statusCode: 200))
        }

        let response = try await fixture.gateway.generate(
            request: ProviderRequest(
                model: "anthropic/claude-3.5-sonnet",
                messages: [ProviderRequestMessage(role: "user", content: "hello")],
                stream: false
            ),
            provider: .openRouter
        )

        XCTAssertEqual(response.text, "gateway ok")
        XCTAssertEqual(response.usage?.inputTokens, 2)
        XCTAssertEqual(response.usage?.outputTokens, 3)

        let request = try XCTUnwrap(fixture.httpClient.sentRequests.first)
        XCTAssertEqual(request.url.absoluteString, "https://openrouter.ai/api/v1/chat/completions")
        XCTAssertEqual(request.headers["Authorization"], "Bearer openrouter-key")
        XCTAssertEqual(request.headers["HTTP-Referer"], "https://yamabikochat.app")

        let body = try XCTUnwrap(request.body)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(root["model"] as? String, "anthropic/claude-3.5-sonnet")
        XCTAssertEqual(root["stream"] as? Bool, false)
    }

    func testClinePassGenerateUsesFixedChatCompletionsEndpoint() async throws {
        let fixture = try makeFixture()
        try fixture.credentials.setCredential("clinepass-key", for: .clinePass)

        fixture.httpClient.sendResponder = { request in
            let data = #"{"choices":[{"message":{"content":"cline ok"}}]}"#.data(using: .utf8)!
            return (data, Self.httpResponse(url: request.url, statusCode: 200))
        }

        let response = try await fixture.gateway.generate(
            request: ProviderRequest(
                model: "cline-pass/glm-5.2",
                messages: [ProviderRequestMessage(role: "user", content: "hello")],
                stream: false
            ),
            provider: .clinePass
        )

        XCTAssertEqual(response.text, "cline ok")

        let request = try XCTUnwrap(fixture.httpClient.sentRequests.first)
        XCTAssertEqual(request.url.absoluteString, "https://api.cline.bot/api/v1/chat/completions")
        XCTAssertEqual(request.headers["Authorization"], "Bearer clinepass-key")

        let body = try XCTUnwrap(request.body)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(root["model"] as? String, "cline-pass/glm-5.2")
    }

    func testOpenCodeGoStreamRetriesNonStreamingWhenNoAnswerTextArrives() async throws {
        let fixture = try makeFixture()
        try fixture.credentials.setCredential("opencode-key", for: .openCodeGo)

        fixture.httpClient.streamResponder = { request in
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield("data: [DONE]")
                continuation.yield("")
                continuation.finish()
            }
            return (stream, Self.httpResponse(url: request.url, statusCode: 200))
        }
        fixture.httpClient.sendResponder = { request in
            let data = #"{"choices":[{"message":{"content":"fallback answer"}}]}"#
                .data(using: .utf8)!
            return (data, Self.httpResponse(url: request.url, statusCode: 200))
        }

        let stream = try await fixture.gateway.stream(
            request: ProviderRequest(
                model: "glm-5.1",
                messages: [ProviderRequestMessage(role: "user", content: "hello")],
                stream: true
            ),
            provider: .openCodeGo
        )

        var completedResponses: [ProviderResponse] = []
        for try await event in stream {
            if case let .completed(response) = event {
                completedResponses.append(response)
            }
        }

        XCTAssertEqual(fixture.httpClient.streamedRequests.count, 1)
        XCTAssertEqual(fixture.httpClient.sentRequests.count, 1)
        XCTAssertEqual(completedResponses.last?.text, "fallback answer")

        let streamBody = try XCTUnwrap(fixture.httpClient.streamedRequests.first?.body)
        let streamRoot = try XCTUnwrap(try JSONSerialization.jsonObject(with: streamBody) as? [String: Any])
        XCTAssertEqual(streamRoot["stream"] as? Bool, true)
        XCTAssertNotNil(streamRoot["stream_options"])

        let retryBody = try XCTUnwrap(fixture.httpClient.sentRequests.first?.body)
        let retryRoot = try XCTUnwrap(try JSONSerialization.jsonObject(with: retryBody) as? [String: Any])
        XCTAssertEqual(retryRoot["stream"] as? Bool, false)
    }

    private func makeFixture() throws -> (
        gateway: ProviderGateway,
        credentials: ProviderGatewayCredentialStore,
        httpClient: ProviderGatewayHTTPClient
    ) {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)
        let settings = SettingsRepository(dbQueue: dbQueue)
        let credentials = ProviderGatewayCredentialStore()
        let httpClient = ProviderGatewayHTTPClient()
        let gateway = ProviderGateway(
            settingsRepository: settings,
            credentialStore: credentials,
            httpClient: httpClient
        )
        return (gateway, credentials, httpClient)
    }

    private static func httpResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }
}
