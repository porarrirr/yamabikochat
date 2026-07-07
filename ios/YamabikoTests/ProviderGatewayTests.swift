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

private final class CallCounter: @unchecked Sendable {
    var count = 0
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

    func testGeminiGenerateRetriesTransientInternalServerError() async throws {
        let fixture = try makeFixture()
        try fixture.credentials.setCredential("gemini-key", for: .gemini)

        let counter = CallCounter()
        fixture.httpClient.sendResponder = { request in
            counter.count += 1
            if counter.count == 1 {
                let data = #"{"error":{"code":500,"message":"Internal error encountered.","status":"INTERNAL"}}"#
                    .data(using: .utf8)!
                return (data, Self.httpResponse(url: request.url, statusCode: 500))
            }
            let data = #"{"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}"#.data(using: .utf8)!
            return (data, Self.httpResponse(url: request.url, statusCode: 200))
        }

        let response = try await fixture.gateway.generate(
            request: ProviderRequest(
                model: "gemma-4-31b-it",
                messages: [ProviderRequestMessage(role: "user", content: "hi")],
                stream: false
            ),
            provider: .gemini
        )

        XCTAssertEqual(response.text, "ok")
        XCTAssertEqual(counter.count, 2, "should have retried once after the transient 500")
    }

    func testGeminiGenerateDoesNotRetryNonTransientErrors() async throws {
        let fixture = try makeFixture()
        try fixture.credentials.setCredential("gemini-key", for: .gemini)

        let counter = CallCounter()
        fixture.httpClient.sendResponder = { request in
            counter.count += 1
            let data = #"{"error":{"code":400,"message":"Bad request.","status":"INVALID_ARGUMENT"}}"#
                .data(using: .utf8)!
            return (data, Self.httpResponse(url: request.url, statusCode: 400))
        }

        do {
            _ = try await fixture.gateway.generate(
                request: ProviderRequest(
                    model: "gemini-2.5-flash",
                    messages: [ProviderRequestMessage(role: "user", content: "hi")],
                    stream: false
                ),
                provider: .gemini
            )
            XCTFail("Expected a 400 to be thrown")
        } catch {
            // expected
        }

        XCTAssertEqual(counter.count, 1, "a 400 is not transient and should not be retried")
    }

    func testGeminiStreamRetriesTransientInternalServerErrorBeforeAnyEventYielded() async throws {
        let fixture = try makeFixture()
        try fixture.credentials.setCredential("gemini-key", for: .gemini)

        let counter = CallCounter()
        fixture.httpClient.streamResponder = { request in
            counter.count += 1
            if counter.count == 1 {
                let stream = AsyncThrowingStream<String, Error> { continuation in
                    continuation.finish()
                }
                return (stream, Self.httpResponse(url: request.url, statusCode: 500))
            }
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield(#"data: {"candidates":[{"content":{"parts":[{"text":"hello"}]}}]}"#)
                continuation.yield("")
                continuation.finish()
            }
            return (stream, Self.httpResponse(url: request.url, statusCode: 200))
        }

        let stream = try await fixture.gateway.stream(
            request: ProviderRequest(
                model: "gemma-4-31b-it",
                messages: [ProviderRequestMessage(role: "user", content: "hi")],
                stream: true
            ),
            provider: .gemini
        )

        var textDeltas: [String] = []
        for try await event in stream {
            if case let .textDelta(text) = event {
                textDeltas.append(text)
            }
        }

        XCTAssertEqual(counter.count, 2, "should have retried the stream once after the transient 500")
        XCTAssertEqual(textDeltas, ["hello"])
    }

    func testGeminiGenerateRotatesToNextModelOnSameKeyAfterRateLimit() async throws {
        let fixture = try makeFixture()
        try fixture.credentials.setCredential("gemini-key", for: .gemini)
        var settings = try fixture.settings.load()
        settings.setGeminiRotationModelsList(["gemini-2.5-flash-lite"])
        try fixture.settings.save(settings)

        let counter = CallCounter()
        fixture.httpClient.sendResponder = { request in
            counter.count += 1
            if counter.count == 1 {
                return (Self.rateLimitedResponseData(), Self.httpResponse(url: request.url, statusCode: 429))
            }
            return (Self.geminiSuccessResponseData(), Self.httpResponse(url: request.url, statusCode: 200))
        }

        let response = try await fixture.gateway.generate(
            request: ProviderRequest(
                model: "gemini-2.5-flash",
                messages: [ProviderRequestMessage(role: "user", content: "hi")],
                stream: false
            ),
            provider: .gemini
        )

        XCTAssertEqual(response.text, "ok")
        XCTAssertEqual(fixture.httpClient.sentRequests.count, 2)
        XCTAssertTrue(fixture.httpClient.sentRequests[0].url.absoluteString.contains("gemini-2.5-flash:generateContent"))
        XCTAssertTrue(fixture.httpClient.sentRequests[1].url.absoluteString.contains("gemini-2.5-flash-lite:generateContent"))
        XCTAssertTrue(fixture.httpClient.sentRequests[1].url.absoluteString.contains("key=gemini-key"))
    }

    func testGeminiGenerateRotatesToNextKeyAfterModelsExhaustedOnSameKey() async throws {
        let fixture = try makeFixture()
        try fixture.credentials.setCredential("key1", for: .gemini)
        try fixture.credentials.setGeminiAPIKey(name: "slot-a", value: "key2")
        var settings = try fixture.settings.load()
        settings.setGeminiKeyNames(["slot-a"])
        settings.setGeminiRotationModelsList(["gemini-2.5-flash-lite"])
        try fixture.settings.save(settings)

        let counter = CallCounter()
        fixture.httpClient.sendResponder = { request in
            counter.count += 1
            if counter.count <= 2 {
                return (Self.rateLimitedResponseData(), Self.httpResponse(url: request.url, statusCode: 429))
            }
            return (Self.geminiSuccessResponseData(), Self.httpResponse(url: request.url, statusCode: 200))
        }

        let response = try await fixture.gateway.generate(
            request: ProviderRequest(
                model: "gemini-2.5-flash",
                messages: [ProviderRequestMessage(role: "user", content: "hi")],
                stream: false
            ),
            provider: .gemini
        )

        XCTAssertEqual(response.text, "ok")
        XCTAssertEqual(fixture.httpClient.sentRequests.count, 3, "should try both models on key1 before moving to key2")
        XCTAssertTrue(fixture.httpClient.sentRequests[0].url.absoluteString.contains("key=key1"))
        XCTAssertTrue(fixture.httpClient.sentRequests[1].url.absoluteString.contains("key=key1"))
        XCTAssertTrue(fixture.httpClient.sentRequests[2].url.absoluteString.contains("key=key2"))
    }

    func testGeminiGenerateSkipsRemainingModelsOnAuthFailure() async throws {
        let fixture = try makeFixture()
        try fixture.credentials.setCredential("bad-key", for: .gemini)
        try fixture.credentials.setGeminiAPIKey(name: "slot-a", value: "good-key")
        var settings = try fixture.settings.load()
        settings.setGeminiKeyNames(["slot-a"])
        settings.setGeminiRotationModelsList(["gemini-2.5-flash-lite"])
        try fixture.settings.save(settings)

        let counter = CallCounter()
        fixture.httpClient.sendResponder = { request in
            counter.count += 1
            if counter.count == 1 {
                return (Self.authFailureResponseData(), Self.httpResponse(url: request.url, statusCode: 401))
            }
            return (Self.geminiSuccessResponseData(), Self.httpResponse(url: request.url, statusCode: 200))
        }

        let response = try await fixture.gateway.generate(
            request: ProviderRequest(
                model: "gemini-2.5-flash",
                messages: [ProviderRequestMessage(role: "user", content: "hi")],
                stream: false
            ),
            provider: .gemini
        )

        XCTAssertEqual(response.text, "ok")
        XCTAssertEqual(fixture.httpClient.sentRequests.count, 2, "an auth failure should skip the bad key's remaining model, not retry it")
        XCTAssertTrue(fixture.httpClient.sentRequests[0].url.absoluteString.contains("key=bad-key"))
        XCTAssertTrue(fixture.httpClient.sentRequests[1].url.absoluteString.contains("key=good-key"))
    }

    func testGeminiGenerateDoesNotRotateOnNonRotationEligibleError() async throws {
        let fixture = try makeFixture()
        try fixture.credentials.setCredential("key1", for: .gemini)
        try fixture.credentials.setGeminiAPIKey(name: "slot-a", value: "key2")
        var settings = try fixture.settings.load()
        settings.setGeminiKeyNames(["slot-a"])
        try fixture.settings.save(settings)

        let counter = CallCounter()
        fixture.httpClient.sendResponder = { request in
            counter.count += 1
            let data = #"{"error":{"code":400,"message":"Bad request.","status":"INVALID_ARGUMENT"}}"#
                .data(using: .utf8)!
            return (data, Self.httpResponse(url: request.url, statusCode: 400))
        }

        do {
            _ = try await fixture.gateway.generate(
                request: ProviderRequest(
                    model: "gemini-2.5-flash",
                    messages: [ProviderRequestMessage(role: "user", content: "hi")],
                    stream: false
                ),
                provider: .gemini
            )
            XCTFail("Expected a 400 to be thrown")
        } catch {
            // expected
        }

        XCTAssertEqual(counter.count, 1, "a 400 is not rotation-eligible even with multiple keys configured")
    }

    func testGeminiGenerateExhaustsAllCandidatesAndThrowsLastError() async throws {
        let fixture = try makeFixture()
        try fixture.credentials.setCredential("key1", for: .gemini)
        try fixture.credentials.setGeminiAPIKey(name: "slot-a", value: "key2")
        var settings = try fixture.settings.load()
        settings.setGeminiKeyNames(["slot-a"])
        settings.setGeminiRotationModelsList(["gemini-2.5-flash-lite"])
        try fixture.settings.save(settings)

        fixture.httpClient.sendResponder = { request in
            (Self.rateLimitedResponseData(), Self.httpResponse(url: request.url, statusCode: 429))
        }

        do {
            _ = try await fixture.gateway.generate(
                request: ProviderRequest(
                    model: "gemini-2.5-flash",
                    messages: [ProviderRequestMessage(role: "user", content: "hi")],
                    stream: false
                ),
                provider: .gemini
            )
            XCTFail("Expected rotation to exhaust all candidates and throw")
        } catch let ProviderClientError.httpStatus(status, _) {
            XCTAssertEqual(status, 429)
        }

        XCTAssertEqual(fixture.httpClient.sentRequests.count, 4, "2 keys x 2 models should all be attempted")
    }

    func testGeminiStreamRotatesToNextCandidateBeforeAnyEventYielded() async throws {
        let fixture = try makeFixture()
        try fixture.credentials.setCredential("gemini-key", for: .gemini)
        var settings = try fixture.settings.load()
        settings.setGeminiRotationModelsList(["gemini-2.5-flash-lite"])
        try fixture.settings.save(settings)

        let counter = CallCounter()
        fixture.httpClient.streamResponder = { request in
            counter.count += 1
            if counter.count == 1 {
                let stream = AsyncThrowingStream<String, Error> { continuation in
                    continuation.finish()
                }
                return (stream, Self.httpResponse(url: request.url, statusCode: 429))
            }
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield(#"data: {"candidates":[{"content":{"parts":[{"text":"hello"}]}}]}"#)
                continuation.yield("")
                continuation.finish()
            }
            return (stream, Self.httpResponse(url: request.url, statusCode: 200))
        }

        let stream = try await fixture.gateway.stream(
            request: ProviderRequest(
                model: "gemini-2.5-flash",
                messages: [ProviderRequestMessage(role: "user", content: "hi")],
                stream: true
            ),
            provider: .gemini
        )

        var textDeltas: [String] = []
        for try await event in stream {
            if case let .textDelta(text) = event {
                textDeltas.append(text)
            }
        }

        XCTAssertEqual(counter.count, 2, "should have rotated to the next model after a 429 with no events yielded")
        XCTAssertEqual(textDeltas, ["hello"])
        XCTAssertTrue(fixture.httpClient.streamedRequests[1].url.absoluteString.contains("gemini-2.5-flash-lite"))
    }

    func testGeminiRotationRemembersLastGoodCandidateAcrossCalls() async throws {
        let fixture = try makeFixture()
        try fixture.credentials.setCredential("key1", for: .gemini)
        try fixture.credentials.setGeminiAPIKey(name: "slot-a", value: "key2")
        var settings = try fixture.settings.load()
        settings.setGeminiKeyNames(["slot-a"])
        try fixture.settings.save(settings)

        let counter = CallCounter()
        fixture.httpClient.sendResponder = { request in
            counter.count += 1
            if counter.count == 1 {
                return (Self.rateLimitedResponseData(), Self.httpResponse(url: request.url, statusCode: 429))
            }
            return (Self.geminiSuccessResponseData(), Self.httpResponse(url: request.url, statusCode: 200))
        }

        let request = ProviderRequest(
            model: "gemini-2.5-flash",
            messages: [ProviderRequestMessage(role: "user", content: "hi")],
            stream: false
        )
        _ = try await fixture.gateway.generate(request: request, provider: .gemini)
        XCTAssertEqual(fixture.httpClient.sentRequests.count, 2, "first call should rotate past key1 to key2")

        _ = try await fixture.gateway.generate(request: request, provider: .gemini)
        XCTAssertEqual(fixture.httpClient.sentRequests.count, 3, "second call should start directly on key2, not retry key1 first")
        XCTAssertTrue(fixture.httpClient.sentRequests[2].url.absoluteString.contains("key=key2"))
    }

    func testGeminiRotationSettingsDoNotAffectOtherProviders() async throws {
        let fixture = try makeFixture()
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)
        var settings = try fixture.settings.load()
        settings.setGeminiKeyNames(["slot-a"])
        settings.setGeminiRotationModelsList(["gemini-2.5-flash-lite"])
        try fixture.settings.save(settings)

        fixture.httpClient.sendResponder = { request in
            let data = #"{"choices":[{"message":{"content":"gateway ok"}}]}"#.data(using: .utf8)!
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
        XCTAssertEqual(fixture.httpClient.sentRequests.count, 1, "Gemini rotation settings must not affect other providers")
    }

    private func makeFixture() throws -> (
        gateway: ProviderGateway,
        credentials: ProviderGatewayCredentialStore,
        httpClient: ProviderGatewayHTTPClient,
        settings: SettingsRepository
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
        return (gateway, credentials, httpClient, settings)
    }

    private static func rateLimitedResponseData() -> Data {
        #"{"error":{"code":429,"message":"Resource exhausted.","status":"RESOURCE_EXHAUSTED"}}"#
            .data(using: .utf8)!
    }

    private static func authFailureResponseData() -> Data {
        #"{"error":{"code":401,"message":"API key not valid.","status":"UNAUTHENTICATED"}}"#
            .data(using: .utf8)!
    }

    private static func geminiSuccessResponseData() -> Data {
        #"{"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}"#.data(using: .utf8)!
    }

    private static func httpResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }
}
