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
    var requests: [HTTPRequest] = []
    var sendResponder: ((HTTPRequest) throws -> (Data, HTTPURLResponse))?
    var streamResponder: ((HTTPRequest) throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse))?

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        requests.append(request)
        guard let sendResponder else {
            throw ProviderClientError.invalidResponse
        }
        return try sendResponder(request)
    }

    func stream(_ request: HTTPRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        lastRequest = request
        requests.append(request)
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

    func testGeminiCliHeadersMatchOpencodeAndRequestIDMatchesBody() async throws {
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
        XCTAssertEqual(captured.headers["User-Agent"], "google-api-nodejs-client/9.15.1")
        XCTAssertEqual(captured.headers["X-Goog-Api-Client"], "gl-node/22.17.0")
        XCTAssertEqual(
            captured.headers["Client-Metadata"],
            "ideType=IDE_UNSPECIFIED,platform=PLATFORM_UNSPECIFIED,pluginType=GEMINI"
        )
        XCTAssertTrue(captured.url.absoluteString.contains(":generateContent"))
        let requestID = try XCTUnwrap(captured.headers["x-activity-request-id"])
        assertLowercaseUUIDv4(requestID)
        let bodyData = try XCTUnwrap(captured.body)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(root["user_prompt_id"] as? String, requestID)
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

    func testGeminiBuildBodyAlwaysIncludesTextPartEvenWhenPromptEmpty() async throws {
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
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let request = ProviderRequest(
            model: "gemini-2.5-flash",
            messages: [ProviderRequestMessage(role: "user", content: "", attachments: [tempURL.absoluteString])],
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

        let bodyData = try XCTUnwrap(httpClient.lastRequest?.body)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let contents = try XCTUnwrap(root["contents"] as? [[String: Any]])
        let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
        XCTAssertEqual(parts.first?["text"] as? String, "")
        XCTAssertNotNil(parts.last?["inlineData"])
    }

    func testGeminiAuthBodyIncludesSessionIdWhenMetadataProvided() async throws {
        let store = ProviderTestCredentialStore()
        try store.setGeminiAccessToken("  gemini-access-token  ")
        try store.saveSecret("project-1", key: "gemini_project_id")
        let model = "gemini-3.1-pro-preview"

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"{"response":{"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}}"#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let request = ProviderRequest(
            model: model,
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: false,
            tools: [],
            thinking: nil,
            metadata: [
                "provider": "GEMINI_AUTH",
                "geminiSessionId": "session-123"
            ]
        )

        let client = GeminiProviderClient()
        _ = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        let captured = try XCTUnwrap(httpClient.lastRequest)
        XCTAssertEqual(captured.headers["Authorization"], "Bearer gemini-access-token")
        let bodyData = try XCTUnwrap(captured.body)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(root["model"] as? String, model)
        let inner = try XCTUnwrap(root["request"] as? [String: Any])
        XCTAssertEqual(inner["session_id"] as? String, "session-123")
    }

    func testGeminiAuthBodyUsesStableSessionIDWhenMetadataMissing() async throws {
        let store = ProviderTestCredentialStore()
        try store.setGeminiAccessToken("gemini-access-token")
        try store.saveSecret("project-1", key: "gemini_project_id")

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"{"response":{"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}}"#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let request = ProviderRequest(
            model: "gemini-2.5-flash",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: false,
            tools: [],
            thinking: nil,
            metadata: [
                "provider": "GEMINI_AUTH"
            ]
        )

        let client = GeminiProviderClient()
        _ = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )
        _ = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        XCTAssertEqual(httpClient.requests.count, 2)
        let firstBody = try XCTUnwrap(httpClient.requests[0].body)
        let secondBody = try XCTUnwrap(httpClient.requests[1].body)
        let firstRoot = try XCTUnwrap(try JSONSerialization.jsonObject(with: firstBody) as? [String: Any])
        let secondRoot = try XCTUnwrap(try JSONSerialization.jsonObject(with: secondBody) as? [String: Any])
        let firstInner = try XCTUnwrap(firstRoot["request"] as? [String: Any])
        let secondInner = try XCTUnwrap(secondRoot["request"] as? [String: Any])
        let firstSessionID = try XCTUnwrap(firstInner["session_id"] as? String)
        let secondSessionID = try XCTUnwrap(secondInner["session_id"] as? String)
        XCTAssertFalse(firstSessionID.isEmpty)
        assertLowercaseUUIDv4(firstSessionID)
        XCTAssertEqual(firstSessionID, secondSessionID)
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

        let captured = try XCTUnwrap(httpClient.lastRequest)
        XCTAssertEqual(captured.headers["Accept"], "text/event-stream")
        XCTAssertEqual(captured.headers["User-Agent"], "google-api-nodejs-client/9.15.1")
        XCTAssertEqual(captured.headers["X-Goog-Api-Client"], "gl-node/22.17.0")
        XCTAssertEqual(
            captured.headers["Client-Metadata"],
            "ideType=IDE_UNSPECIFIED,platform=PLATFORM_UNSPECIFIED,pluginType=GEMINI"
        )
        let requestID = try XCTUnwrap(captured.headers["x-activity-request-id"])
        assertLowercaseUUIDv4(requestID)
        let bodyData = try XCTUnwrap(captured.body)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(root["user_prompt_id"] as? String, requestID)

        XCTAssertTrue(events.contains(.textDelta("answer")))
        XCTAssertTrue(events.contains(.reasoningDelta("plan")))
        if case let .completed(final) = try XCTUnwrap(events.last) {
            XCTAssertEqual(final.text, "answer")
            XCTAssertEqual(final.reasoningSummary, "plan")
        } else {
            XCTFail("Expected completed event")
        }
    }

    func testGeminiCliStreamParsesTextOnlyPayloadWithoutCandidates() async throws {
        let store = ProviderTestCredentialStore()
        try store.setGeminiAccessToken("gemini-access-token")
        try store.saveSecret("project-1", key: "gemini_project_id")

        let httpClient = CapturingHTTPClient()
        httpClient.streamResponder = { request in
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield(#"data: {"response":{"text":"A"}}"#)
                continuation.yield(#"data: {"text":"B"}"#)
                continuation.yield("data: [DONE]")
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

        XCTAssertTrue(events.contains(.textDelta("A")))
        XCTAssertTrue(events.contains(.textDelta("B")))
        if case let .completed(final) = try XCTUnwrap(events.last) {
            XCTAssertEqual(final.text, "AB")
            XCTAssertNil(final.reasoningSummary)
        } else {
            XCTFail("Expected completed event")
        }
    }

    func testGeminiCliStreamFlushesOnDataBoundaryWhenBlankLineMissing() async throws {
        let store = ProviderTestCredentialStore()
        try store.setGeminiAccessToken("gemini-access-token")
        try store.saveSecret("project-1", key: "gemini_project_id")

        let httpClient = CapturingHTTPClient()
        httpClient.streamResponder = { request in
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield("data: {")
                continuation.yield(#"data: "response":{"candidates":[{"content":{"parts":[{"text":"A"}]}}]}"#)
                continuation.yield("data: }")
                continuation.yield(#"data: {"response":{"candidates":[{"content":{"parts":[{"text":"B"}]}}]}}"#)
                continuation.yield("data: [DONE]")
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

        XCTAssertTrue(events.contains(.textDelta("A")))
        XCTAssertTrue(events.contains(.textDelta("B")))
        if case let .completed(final) = try XCTUnwrap(events.last) {
            XCTAssertEqual(final.text, "AB")
            XCTAssertNil(final.reasoningSummary)
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

    func testGeminiCliStreamThrowsWhenNoUsableData() async throws {
        let store = ProviderTestCredentialStore()
        try store.setGeminiAccessToken("gemini-access-token")
        try store.saveSecret("project-1", key: "gemini_project_id")

        let httpClient = CapturingHTTPClient()
        httpClient.streamResponder = { request in
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield(#"data: {"event":"keepalive"}"#)
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

        do {
            for try await _ in stream {}
            XCTFail("Expected stream to fail for empty Gemini CLI payload")
        } catch let ProviderClientError.parseFailure(reason) {
            XCTAssertEqual(reason, GeminiProviderClient.noUsableStreamDataReason)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testGeminiCliStreamRetriesRateLimit429AndSucceeds() async throws {
        let store = ProviderTestCredentialStore()
        try store.setGeminiAccessToken("gemini-access-token")
        try store.saveSecret("project-1", key: "gemini_project_id")

        let httpClient = CapturingHTTPClient()
        var attempts = 0
        httpClient.streamResponder = { request in
            attempts += 1
            if attempts == 1 {
                let stream = AsyncThrowingStream<String, Error> { continuation in
                    continuation.yield(#"data: {"error":{"message":"rate limit","details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"RATE_LIMIT_EXCEEDED","domain":"cloudcode-pa.googleapis.com"}]}}"#)
                    continuation.yield("")
                    continuation.finish()
                }
                return (
                    stream,
                    Self.makeHTTPResponse(
                        url: request.url,
                        statusCode: 429,
                        headers: ["retry-after-ms": "1"]
                    )
                )
            }

            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield(#"data: {"response":{"candidates":[{"content":{"parts":[{"text":"ok"}]}}]}}"#)
                continuation.yield("")
                continuation.yield("data: [DONE]")
                continuation.yield("")
                continuation.finish()
            }
            return (stream, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let request = ProviderRequest(
            model: "gemini-3.1-pro-preview",
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

        var final: ProviderResponse?
        for try await event in stream {
            if case let .completed(response) = event {
                final = response
            }
        }

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(final?.text, "ok")
    }

    func testGeminiCliStreamDoesNotRetryTerminalQuota429() async throws {
        let store = ProviderTestCredentialStore()
        try store.setGeminiAccessToken("gemini-access-token")
        try store.saveSecret("project-1", key: "gemini_project_id")

        let httpClient = CapturingHTTPClient()
        var attempts = 0
        httpClient.streamResponder = { request in
            attempts += 1
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield(#"data: {"error":{"message":"quota exhausted","details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo","reason":"QUOTA_EXHAUSTED","domain":"cloudcode-pa.googleapis.com"}]}}"#)
                continuation.yield("")
                continuation.finish()
            }
            return (stream, Self.makeHTTPResponse(url: request.url, statusCode: 429))
        }

        let request = ProviderRequest(
            model: "gemini-3.1-pro-preview",
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

        do {
            for try await _ in stream {}
            XCTFail("Expected stream failure for terminal quota error")
        } catch let ProviderClientError.httpStatus(status, body) {
            XCTAssertEqual(status, 429)
            XCTAssertTrue(body.contains("Quota exhausted for this account"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertEqual(attempts, 1)
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

    func testOpenRouterGenerateParsesUsageBreakdown() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("openrouter-key", for: .openRouter)

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"""
            {
              "choices":[{"message":{"content":"ok"}}],
              "usage":{
                "prompt_tokens":120,
                "completion_tokens":30,
                "total_tokens":150,
                "completion_tokens_details":{"reasoning_tokens":9},
                "prompt_tokens_details":{"cached_tokens":48},
                "input_tokens_details":{"cache_creation_tokens":12}
              }
            }
            """#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = OpenAICompatibleProviderClient()
        let request = ProviderRequest(
            model: "openai/gpt-4o-mini",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: false,
            tools: [],
            thinking: nil,
            metadata: ["provider": "OPENROUTER"]
        )

        let response = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        let usage = try XCTUnwrap(response.usage)
        XCTAssertEqual(usage.inputTokens, 120)
        XCTAssertEqual(usage.outputTokens, 30)
        XCTAssertEqual(usage.totalTokens, 150)
        XCTAssertEqual(usage.reasoningTokens, 9)
        XCTAssertEqual(usage.cachedInputTokens, 48)
        XCTAssertEqual(usage.cacheCreationInputTokens, 12)
    }

    func testOpenRouterStreamReturnsFinalUsageFromUsageChunk() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("openrouter-key", for: .openRouter)

        let httpClient = CapturingHTTPClient()
        httpClient.streamResponder = { request in
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield(#"data: {"choices":[{"delta":{"content":"A"}}]}"#)
                continuation.yield(#"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#)
                continuation.yield(#"data: {"usage":{"prompt_tokens":100,"completion_tokens":20,"total_tokens":120,"completion_tokens_details":{"reasoning_tokens":4},"prompt_tokens_details":{"cached_tokens":16}}}"#)
                continuation.yield("data: [DONE]")
                continuation.finish()
            }
            return (stream, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = OpenAICompatibleProviderClient()
        let request = ProviderRequest(
            model: "openai/gpt-4o-mini",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: true,
            tools: [],
            thinking: nil,
            metadata: ["provider": "OPENROUTER"]
        )

        let stream = client.stream(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        var final: ProviderResponse?
        for try await event in stream {
            if case let .completed(response) = event {
                final = response
            }
        }

        let usage = try XCTUnwrap(final?.usage)
        XCTAssertEqual(usage.inputTokens, 100)
        XCTAssertEqual(usage.outputTokens, 20)
        XCTAssertEqual(usage.totalTokens, 120)
        XCTAssertEqual(usage.reasoningTokens, 4)
        XCTAssertEqual(usage.cachedInputTokens, 16)
    }

    func testOpenRouterGenerateParsesUsageWithMixedCaseKeys() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("openrouter-key", for: .openRouter)

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"""
            {
              "choices":[{"message":{"content":"ok"}}],
              "usage":{
                "inputTokens":140,
                "outputTokens":60,
                "totalTokens":200,
                "output_tokens_details":{"reasoning":21},
                "input_tokens_details":{"cachedInputTokens":35,"cache_creation_input_tokens":8}
              }
            }
            """#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = OpenAICompatibleProviderClient()
        let request = ProviderRequest(
            model: "openai/gpt-4o-mini",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: false,
            tools: [],
            thinking: nil,
            metadata: ["provider": "OPENROUTER"]
        )

        let response = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        let usage = try XCTUnwrap(response.usage)
        XCTAssertEqual(usage.inputTokens, 140)
        XCTAssertEqual(usage.outputTokens, 60)
        XCTAssertEqual(usage.totalTokens, 200)
        XCTAssertEqual(usage.reasoningTokens, 21)
        XCTAssertEqual(usage.cachedInputTokens, 35)
        XCTAssertEqual(usage.cacheCreationInputTokens, 8)
    }

    func testGeminiGenerateParsesUsageMetadata() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("gemini-key", for: .gemini)

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"""
            {
              "candidates":[{"content":{"parts":[{"text":"ok"}]}}],
              "usageMetadata":{
                "promptTokenCount":50,
                "candidatesTokenCount":15,
                "totalTokenCount":72,
                "cachedContentTokenCount":10,
                "toolUsePromptTokenCount":5,
                "thoughtsTokenCount":7
              }
            }
            """#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = GeminiProviderClient()
        let request = ProviderRequest(
            model: "gemini-2.5-flash",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: false,
            tools: [],
            thinking: nil,
            metadata: ["provider": "GEMINI"]
        )

        let response = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        let usage = try XCTUnwrap(response.usage)
        XCTAssertEqual(usage.inputTokens, 50)
        XCTAssertEqual(usage.outputTokens, 15)
        XCTAssertEqual(usage.totalTokens, 72)
        XCTAssertEqual(usage.cachedInputTokens, 10)
        XCTAssertEqual(usage.reasoningTokens, 7)
    }

    func testGeminiStreamCarriesUsageMetadataFromFinalChunk() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("gemini-key", for: .gemini)

        let httpClient = CapturingHTTPClient()
        httpClient.streamResponder = { request in
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield(#"data: {"candidates":[{"content":{"parts":[{"text":"A"}]}}]}"#)
                continuation.yield("")
                continuation.yield(#"data: {"usageMetadata":{"promptTokenCount":30,"candidatesTokenCount":7,"totalTokenCount":40,"cachedContentTokenCount":5,"thoughtsTokenCount":2}}"#)
                continuation.yield("")
                continuation.yield("data: [DONE]")
                continuation.yield("")
                continuation.finish()
            }
            return (stream, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = GeminiProviderClient()
        let request = ProviderRequest(
            model: "gemini-2.5-flash",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: true,
            tools: [],
            thinking: nil,
            metadata: ["provider": "GEMINI"]
        )

        let stream = client.stream(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        var final: ProviderResponse?
        for try await event in stream {
            if case let .completed(response) = event {
                final = response
            }
        }

        XCTAssertEqual(final?.text, "A")
        let usage = try XCTUnwrap(final?.usage)
        XCTAssertEqual(usage.inputTokens, 30)
        XCTAssertEqual(usage.outputTokens, 7)
        XCTAssertEqual(usage.totalTokens, 40)
        XCTAssertEqual(usage.cachedInputTokens, 5)
        XCTAssertEqual(usage.reasoningTokens, 2)
    }

    func testGeminiGenerateParsesSnakeCaseUsageMetadata() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("gemini-key", for: .gemini)

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"""
            {
              "candidates":[{"content":{"parts":[{"text":"ok"}]}}],
              "usageMetadata":{
                "prompt_token_count":32,
                "candidates_token_count":11,
                "total_token_count":52,
                "cached_content_token_count":9,
                "tool_use_prompt_token_count":2,
                "reasoning_token_count":8,
                "cache_creation_input_token_count":4
              }
            }
            """#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = GeminiProviderClient()
        let request = ProviderRequest(
            model: "gemini-2.5-flash",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: false,
            tools: [],
            thinking: nil,
            metadata: ["provider": "GEMINI"]
        )

        let response = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        let usage = try XCTUnwrap(response.usage)
        XCTAssertEqual(usage.inputTokens, 32)
        XCTAssertEqual(usage.outputTokens, 11)
        XCTAssertEqual(usage.totalTokens, 52)
        XCTAssertEqual(usage.cachedInputTokens, 9)
        XCTAssertEqual(usage.reasoningTokens, 8)
        XCTAssertEqual(usage.cacheCreationInputTokens, 4)
    }

    func testCodexGenerateParsesResponsesUsage() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCodexAccessToken("codex-access-token")

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"""
            {
              "output_text":"ok",
              "usage":{
                "input_tokens":77,
                "output_tokens":19,
                "total_tokens":96,
                "input_tokens_details":{"cached_tokens":22},
                "output_tokens_details":{"reasoning_tokens":8}
              }
            }
            """#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = CodexProviderClient()
        let request = ProviderRequest(
            model: "gpt-5-codex",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: false,
            tools: [],
            thinking: nil,
            metadata: ["provider": "CODEX_AUTH"]
        )

        let response = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        let usage = try XCTUnwrap(response.usage)
        XCTAssertEqual(usage.inputTokens, 77)
        XCTAssertEqual(usage.outputTokens, 19)
        XCTAssertEqual(usage.totalTokens, 96)
        XCTAssertEqual(usage.cachedInputTokens, 22)
        XCTAssertEqual(usage.reasoningTokens, 8)
    }

    func testCodexStreamCarriesResponseCompletedUsage() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCodexAccessToken("codex-access-token")

        let httpClient = CapturingHTTPClient()
        httpClient.streamResponder = { request in
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield(#"data: {"type":"response.output_text.delta","delta":"A"}"#)
                continuation.yield(#"data: {"type":"response.completed","response":{"usage":{"input_tokens":21,"output_tokens":9,"total_tokens":30,"input_tokens_details":{"cached_tokens":3},"output_tokens_details":{"reasoning_tokens":4}}}}"#)
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

        var final: ProviderResponse?
        for try await event in stream {
            if case let .completed(response) = event {
                final = response
            }
        }

        XCTAssertEqual(final?.text, "A")
        let usage = try XCTUnwrap(final?.usage)
        XCTAssertEqual(usage.inputTokens, 21)
        XCTAssertEqual(usage.outputTokens, 9)
        XCTAssertEqual(usage.totalTokens, 30)
        XCTAssertEqual(usage.cachedInputTokens, 3)
        XCTAssertEqual(usage.reasoningTokens, 4)
    }

    func testCodexGenerateParsesUsageWithMixedCaseKeys() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCodexAccessToken("codex-access-token")

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"""
            {
              "output_text":"ok",
              "usage":{
                "inputTokens":90,
                "outputTokens":40,
                "totalTokens":130,
                "completion_tokens_details":{"reasoning":14},
                "prompt_tokens_details":{"cached_input_tokens":20,"cache_creation_tokens":6}
              }
            }
            """#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = CodexProviderClient()
        let request = ProviderRequest(
            model: "gpt-5-codex",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: false,
            tools: [],
            thinking: nil,
            metadata: ["provider": "CODEX_AUTH"]
        )

        let response = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        let usage = try XCTUnwrap(response.usage)
        XCTAssertEqual(usage.inputTokens, 90)
        XCTAssertEqual(usage.outputTokens, 40)
        XCTAssertEqual(usage.totalTokens, 130)
        XCTAssertEqual(usage.reasoningTokens, 14)
        XCTAssertEqual(usage.cachedInputTokens, 20)
        XCTAssertEqual(usage.cacheCreationInputTokens, 6)
    }

    private static func makeHTTPResponse(
        url: URL,
        statusCode: Int,
        headers: [String: String]? = nil
    ) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: headers
        )!
    }

    private func assertLowercaseUUIDv4(
        _ value: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let pattern = #"^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$"#
        XCTAssertNotNil(
            value.range(of: pattern, options: .regularExpression),
            "Expected lowercase UUID v4 but got \(value)",
            file: file,
            line: line
        )
    }
}
