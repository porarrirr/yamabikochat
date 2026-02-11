import XCTest
@testable import YamabikoChat

private final class ProviderTestCredentialStore: SecureCredentialStore {
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

private final class CapturingHTTPClient: HTTPClientProtocol {
    var lastRequest: HTTPRequest?
    var sendResponder: ((HTTPRequest) throws -> (Data, HTTPURLResponse))?
    var streamResponder: ((HTTPRequest) throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse))?

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        guard let sendResponder else {
            throw ProviderClientError.invalidResponse
        }
        return try sendResponder(request)
    }

    func stream(_ request: HTTPRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        lastRequest = request
        guard let streamResponder else {
            throw ProviderClientError.invalidResponse
        }
        return try streamResponder(request)
    }
}

final class ProviderClientParityTests: XCTestCase {
    func testCodexGenerateUsesResponsesPayloadAndSessionHeader() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCodexAccessToken("codex-access-token")
        try store.saveSecret("acc_123", key: "codex_account_id")

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"{"output_text":"ok"}"#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = CodexProviderClient()
        let settings = AppSettings()
        let request = ProviderRequest(
            model: "/openai/gpt-5-codex",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: false,
            tools: [],
            thinking: ProviderThinkingConfig(enabled: nil, budget: nil, effort: "medium", includeThoughts: true, exclude: nil),
            metadata: [
                "provider": "CODEX_AUTH",
                "codexReasoningSummary": "auto",
                "codexVerbosity": "medium",
                "codexWebSearchEnabled": "true",
                "codexWebSearchContextSize": "medium",
                "codexSessionId": "session-123"
            ]
        )

        let response = try await client.generate(
            request: request,
            settings: settings,
            credentialStore: store,
            httpClient: httpClient
        )

        XCTAssertEqual(response.text, "ok")
        let captured = try XCTUnwrap(httpClient.lastRequest)
        XCTAssertEqual(captured.headers["session_id"], "session-123")
        XCTAssertEqual(captured.headers["ChatGPT-Account-ID"], "acc_123")
        XCTAssertTrue(captured.url.absoluteString.contains("/responses"))

        let bodyData = try XCTUnwrap(captured.body)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(root["model"] as? String, "gpt-5-codex")
        XCTAssertEqual(root["store"] as? Bool, false)
        XCTAssertEqual(root["prompt_cache_key"] as? String, "session-123")

        let include = (root["include"] as? [String]) ?? []
        XCTAssertTrue(include.contains("reasoning.encrypted_content"))

        let reasoning = root["reasoning"] as? [String: Any]
        XCTAssertEqual(reasoning?["effort"] as? String, "medium")
        XCTAssertEqual(reasoning?["summary"] as? String, "auto")

        let input = try XCTUnwrap(root["input"] as? [[String: Any]])
        let first = try XCTUnwrap(input.first)
        let content = try XCTUnwrap(first["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "input_text")
    }

    func testCodexStreamParsesReasoningTextAndOutputItemDone() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCodexAccessToken("codex-access-token")

        let httpClient = CapturingHTTPClient()
        httpClient.streamResponder = { request in
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield(#"data: {"type":"response.reasoning_text.delta","delta":"reason"}"#)
                continuation.yield(#"data: {"type":"response.output_text.delta","delta":"A"}"#)
                continuation.yield(#"data: {"type":"response.output_item.done","item":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"AB"}]}}"#)
                continuation.yield("data: [DONE]")
                continuation.finish()
            }
            return (stream, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = CodexProviderClient()
        let request = ProviderRequest(
            model: "gpt-5-codex",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: true,
            tools: [],
            thinking: nil,
            metadata: ["provider": "CODEX_AUTH"]
        )

        let stream = client.stream(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        var events: [ProviderStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(events.count, 4)
        XCTAssertEqual(events[0], .reasoningDelta("reason"))
        XCTAssertEqual(events[1], .textDelta("A"))
        XCTAssertEqual(events[2], .textDelta("B"))
        if case let .completed(final) = events[3] {
            XCTAssertEqual(final.text, "AB")
            XCTAssertEqual(final.reasoningSummary, "reason")
        } else {
            XCTFail("Expected completed event")
        }
    }

    func testGeminiCliUserAgentUsesAndroidShape() async throws {
        let store = ProviderTestCredentialStore()
        try store.setGeminiAccessToken("gemini-access-token")
        try store.saveSecret("project-1", key: "gemini_project_id")

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"{"response":{"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}}"#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = GeminiProviderClient()
        let request = ProviderRequest(
            model: "gemini-2.5-flash",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: false,
            tools: [],
            thinking: nil,
            metadata: ["provider": "GEMINI_AUTH"]
        )

        let response = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )
        XCTAssertEqual(response.text, "ok")

        let captured = try XCTUnwrap(httpClient.lastRequest)
        let userAgent = captured.headers["User-Agent"] ?? ""
        XCTAssertTrue(userAgent.hasPrefix("GeminiCLI/"))
        XCTAssertTrue(userAgent.contains("(Android "))
        XCTAssertTrue(captured.url.absoluteString.contains(":generateContent"))
    }

    func testGeminiBuildBodyEmbedsImageAttachmentAsInlineData() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("gemini-key", for: .gemini)

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"{"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}"#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        try imageData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let request = ProviderRequest(
            model: "gemini-2.5-flash",
            messages: [
                ProviderRequestMessage(
                    role: "user",
                    content: "describe this image",
                    attachments: [tempURL.absoluteString]
                )
            ],
            stream: false,
            tools: [],
            thinking: nil,
            metadata: ["provider": "GEMINI"]
        )

        let client = GeminiProviderClient()
        _ = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        let captured = try XCTUnwrap(httpClient.lastRequest)
        let bodyData = try XCTUnwrap(captured.body)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let contents = try XCTUnwrap(root["contents"] as? [[String: Any]])
        let first = try XCTUnwrap(contents.first)
        let parts = try XCTUnwrap(first["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.first?["text"] as? String, "describe this image")

        let inlineData = try XCTUnwrap(parts.last?["inlineData"] as? [String: Any])
        XCTAssertEqual(inlineData["mimeType"] as? String, "image/png")
        XCTAssertEqual(inlineData["data"] as? String, imageData.base64EncodedString())
    }

    func testGeminiStreamSeparatesThoughtIntoReasoningDelta() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("gemini-key", for: .gemini)

        let httpClient = CapturingHTTPClient()
        httpClient.streamResponder = { request in
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield(#"data: {"candidates":[{"content":{"parts":[{"text":"visible "},{"text":"hidden","thought":true}]}}]}"#)
                continuation.yield("")
                continuation.yield("data: [DONE]")
                continuation.yield("")
                continuation.finish()
            }
            return (stream, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let request = ProviderRequest(
            model: "gemini-2.5-flash",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: true,
            tools: [],
            thinking: nil,
            metadata: ["provider": "GEMINI"]
        )

        let client = GeminiProviderClient()
        let stream = client.stream(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        var events: [ProviderStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertTrue(events.contains(.textDelta("visible ")))
        XCTAssertTrue(events.contains(.reasoningDelta("hidden")))
        if case let .completed(final) = try XCTUnwrap(events.last) {
            XCTAssertEqual(final.text, "visible ")
            XCTAssertEqual(final.reasoningSummary, "hidden")
        } else {
            XCTFail("Expected completed event")
        }
    }

    func testGeminiCliStreamSeparatesThoughtAndWrapperPayload() async throws {
        let store = ProviderTestCredentialStore()
        try store.setGeminiAccessToken("gemini-access-token")
        try store.saveSecret("project-1", key: "gemini_project_id")

        let httpClient = CapturingHTTPClient()
        httpClient.streamResponder = { request in
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield(#"data: {"response":{"candidates":[{"content":{"parts":[{"text":"plan","thought":true},{"text":"answer"}]}}]}}"#)
                continuation.yield("")
                continuation.yield("data: [DONE]")
                continuation.yield("")
                continuation.finish()
            }
            return (stream, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let request = ProviderRequest(
            model: "gemini-2.5-flash",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: true,
            tools: [],
            thinking: nil,
            metadata: ["provider": "GEMINI_AUTH"]
        )

        let client = GeminiProviderClient()
        let stream = client.stream(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        var events: [ProviderStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertTrue(events.contains(.textDelta("answer")))
        XCTAssertTrue(events.contains(.reasoningDelta("plan")))
        if case let .completed(final) = try XCTUnwrap(events.last) {
            XCTAssertEqual(final.text, "answer")
            XCTAssertEqual(final.reasoningSummary, "plan")
        } else {
            XCTFail("Expected completed event")
        }
    }

    func testGeminiCliNonStreamingReturnsReasoningFromThoughtParts() async throws {
        let store = ProviderTestCredentialStore()
        try store.setGeminiAccessToken("gemini-access-token")
        try store.saveSecret("project-1", key: "gemini_project_id")

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"{"response":{"candidates":[{"content":{"parts":[{"text":"plan","thought":true},{"text":"answer"}]}}]}}"#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let request = ProviderRequest(
            model: "gemini-2.5-flash",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: false,
            tools: [],
            thinking: nil,
            metadata: ["provider": "GEMINI_AUTH"]
        )

        let client = GeminiProviderClient()
        let response = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        XCTAssertEqual(response.text, "answer")
        XCTAssertEqual(response.reasoningSummary, "plan")
    }

    func testGeminiStreamParsesMultilineSSEDataEvent() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("gemini-key", for: .gemini)

        let httpClient = CapturingHTTPClient()
        httpClient.streamResponder = { request in
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield("data: {")
                continuation.yield("data: \"candidates\":[{\"content\":{\"parts\":[{\"text\":\"A\"}]}}]")
                continuation.yield("data: }")
                continuation.yield("")
                continuation.yield("data: [DONE]")
                continuation.yield("")
                continuation.finish()
            }
            return (stream, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let request = ProviderRequest(
            model: "gemini-2.5-flash",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: true,
            tools: [],
            thinking: nil,
            metadata: ["provider": "GEMINI"]
        )

        let client = GeminiProviderClient()
        let stream = client.stream(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        var events: [ProviderStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertTrue(events.contains(.textDelta("A")))
        if case let .completed(final) = try XCTUnwrap(events.last) {
            XCTAssertEqual(final.text, "A")
            XCTAssertNil(final.reasoningSummary)
        } else {
            XCTFail("Expected completed event")
        }
    }

    func testOpenRouterGenerateIncludesProviderRoutingAndReasoning() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("openrouter-key", for: .openRouter)

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = OpenAICompatibleProviderClient()
        let request = ProviderRequest(
            model: "openai/gpt-4o-mini",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: false,
            tools: [],
            thinking: ProviderThinkingConfig(
                enabled: true,
                budget: 2048,
                effort: nil,
                includeThoughts: false,
                exclude: true
            ),
            provider: ProviderRoutingConfig(
                order: ["openai", "anthropic"],
                allowFallbacks: true,
                requireParameters: true,
                dataCollection: nil,
                quantizations: ["int8"],
                maxPrice: ProviderMaxPriceConfig(prompt: 2.5, completion: 2.5, request: nil, image: nil, audio: nil),
                only: nil,
                ignore: nil,
                sort: "price"
            ),
            metadata: ["provider": "OPENROUTER"]
        )

        let response = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        XCTAssertEqual(response.text, "ok")

        let captured = try XCTUnwrap(httpClient.lastRequest)
        let bodyData = try XCTUnwrap(captured.body)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])

        let provider = try XCTUnwrap(root["provider"] as? [String: Any])
        XCTAssertEqual(provider["order"] as? [String], ["openai", "anthropic"])
        XCTAssertEqual(provider["allow_fallbacks"] as? Bool, true)
        XCTAssertEqual(provider["require_parameters"] as? Bool, true)
        XCTAssertEqual(provider["quantizations"] as? [String], ["int8"])
        XCTAssertEqual(provider["sort"] as? String, "price")
        let maxPrice = try XCTUnwrap(provider["max_price"] as? [String: Any])
        XCTAssertEqual(try XCTUnwrap(maxPrice["prompt"] as? Double), 2.5, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(maxPrice["completion"] as? Double), 2.5, accuracy: 0.0001)

        let reasoning = try XCTUnwrap(root["reasoning"] as? [String: Any])
        XCTAssertEqual(reasoning["enabled"] as? Bool, true)
        XCTAssertEqual(reasoning["max_tokens"] as? Int, 2048)
        XCTAssertEqual(reasoning["exclude"] as? Bool, true)
    }

    private static func makeHTTPResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
    }
}
