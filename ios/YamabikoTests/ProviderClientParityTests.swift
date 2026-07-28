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
                "codexSessionId": "session-123",
                "promptCacheKey": "conversation-42"
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
        XCTAssertEqual(captured.headers["session-id"], "session-123")
        XCTAssertEqual(captured.headers["ChatGPT-Account-ID"], "acc_123")
        XCTAssertTrue(captured.url.absoluteString.contains("/responses"))

        let bodyData = try XCTUnwrap(captured.body)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(root["model"] as? String, "gpt-5-codex")
        XCTAssertEqual(root["store"] as? Bool, false)
        XCTAssertEqual(root["prompt_cache_key"] as? String, "conversation-42")

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

    func testCodexGenerateOmitsPromptCacheKeyWhenDisabledButKeepsSessionHeader() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCodexAccessToken("codex-access-token")

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"{"output_text":"ok"}"#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = CodexProviderClient()
        let request = ProviderRequest(
            model: "gpt-5-codex",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: false,
            tools: [],
            thinking: nil,
            metadata: [
                "provider": "CODEX_AUTH",
                "codexSessionId": "session-123",
                "promptCacheKey": "conversation-42",
                "codexPromptCacheEnabled": "false"
            ]
        )

        _ = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        let captured = try XCTUnwrap(httpClient.lastRequest)
        XCTAssertEqual(captured.headers["session-id"], "session-123")

        let bodyData = try XCTUnwrap(captured.body)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertNil(root["prompt_cache_key"])
    }

    func testCodexStreamParsesReasoningTextAndOutputItemDone() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCodexAccessToken("codex-access-token")

        let httpClient = CapturingHTTPClient()
        httpClient.streamResponder = { request in
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield(#"data: {"type":"response.reasoning_text.delta","delta":"reason"}"#)
                continuation.yield("")
                continuation.yield(#"data: {"type":"response.output_text.delta","delta":"A"}"#)
                continuation.yield("")
                continuation.yield(#"data: {"type":"response.output_item.done","item":{"type":"message","role":"assistant","content":[{"type":"output_text","text":"AB"}]}}"#)
                continuation.yield("")
                continuation.yield("data: [DONE]")
                continuation.yield("")
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

    func testCodexStreamDedupesCumulativeJapaneseOutputTextDelta() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCodexAccessToken("codex-access-token")

        let greeting = "こんにちは！\n今日はどんなことでお手伝いしましょうか？"
        let httpClient = CapturingHTTPClient()
        httpClient.streamResponder = { request in
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield(
                    #"data: {"type":"response.output_text.delta","delta":"こんにちは！"}"#
                )
                continuation.yield("")
                continuation.yield(
                    #"data: {"type":"response.output_text.delta","delta":"こんにちは！\n今日はどんなことでお手伝いしましょうか？"}"#
                )
                continuation.yield("")
                continuation.yield("data: [DONE]")
                continuation.yield("")
                continuation.finish()
            }
            return (stream, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = CodexProviderClient()
        let request = ProviderRequest(
            model: "gpt-5.4-mini",
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

        var textDeltas: [String] = []
        var final: ProviderResponse?
        for try await event in stream {
            switch event {
            case let .textDelta(delta):
                textDeltas.append(delta)
            case let .completed(response):
                final = response
            default:
                break
            }
        }

        XCTAssertEqual(textDeltas, ["こんにちは！", "\n今日はどんなことでお手伝いしましょうか？"])
        XCTAssertEqual(final?.text, greeting)
    }

    func testCodexStreamOutputTextFallbackDoesNotDuplicateAfterDeltas() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCodexAccessToken("codex-access-token")

        let httpClient = CapturingHTTPClient()
        httpClient.streamResponder = { request in
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield(#"data: {"type":"response.output_text.delta","delta":"Hi"}"#)
                continuation.yield("")
                continuation.yield(#"data: {"output_text":"Hi there"}"#)
                continuation.yield("")
                continuation.yield("data: [DONE]")
                continuation.yield("")
                continuation.finish()
            }
            return (stream, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = CodexProviderClient()
        let request = ProviderRequest(
            model: "gpt-5.4-mini",
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

        var textDeltas: [String] = []
        var final: ProviderResponse?
        for try await event in stream {
            switch event {
            case let .textDelta(delta):
                textDeltas.append(delta)
            case let .completed(response):
                final = response
            default:
                break
            }
        }

        XCTAssertEqual(textDeltas, ["Hi", " there"])
        XCTAssertEqual(final?.text, "Hi there")
    }

    func testOpenAICompatibleStreamDedupesCumulativeContent() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("openrouter-key", for: .openRouter)

        let httpClient = CapturingHTTPClient()
        httpClient.streamResponder = { request in
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield(#"data: {"choices":[{"delta":{"content":"Hello"}}]}"#)
                continuation.yield("")
                continuation.yield(#"data: {"choices":[{"delta":{"content":"Hello world"}}]}"#)
                continuation.yield("")
                continuation.yield("data: [DONE]")
                continuation.yield("")
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

        var textDeltas: [String] = []
        var final: ProviderResponse?
        for try await event in stream {
            switch event {
            case let .textDelta(delta):
                textDeltas.append(delta)
            case let .completed(response):
                final = response
            default:
                break
            }
        }

        XCTAssertEqual(textDeltas, ["Hello", " world"])
        XCTAssertEqual(final?.text, "Hello world")
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
            metadata: ["provider": "GEMINI", "supportsVision": "true"]
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
            metadata: ["provider": "GEMINI", "supportsVision": "true"]
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

    func testOpenAICompatibleEncodesFunctionLoopAndParsesToolCall() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("openai-key", for: .openAI)
        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"""
            {
              "choices":[{
                "message":{
                  "content":null,
                  "tool_calls":[{
                    "id":"call_2",
                    "type":"function",
                    "function":{"name":"fetch_url","arguments":"{\"url\":\"https://example.com\"}"}
                  }]
                }
              }]
            }
            """#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }
        let priorCall = ToolCall(
            id: "call_1",
            name: "web_search",
            argumentsJSON: #"{"query":"swift"}"#,
            providerMetadata: nil
        )
        let request = ProviderRequest(
            model: "gpt-4o-mini",
            messages: [
                ProviderRequestMessage(role: "user", content: "search"),
                ProviderRequestMessage(role: "assistant", content: "", toolCalls: [priorCall]),
                ProviderRequestMessage(
                    role: "tool",
                    content: #"{"results":[]}"#,
                    toolCallId: "call_1",
                    toolName: "web_search"
                )
            ],
            stream: false,
            tools: [
                ToolDefinition(
                    name: "web_search",
                    description: "Search",
                    parametersJSON: #"{"type":"object","properties":{"query":{"type":"string"}}}"#
                )
                .providerTool
            ],
            metadata: ["provider": "OPENAI"]
        )

        let response = try await OpenAICompatibleProviderClient().generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        XCTAssertEqual(response.toolCalls.first?.name, "fetch_url")
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(httpClient.lastRequest?.body)) as? [String: Any]
        )
        let tools = try XCTUnwrap(root["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.first?["type"] as? String, "function")
        let function = try XCTUnwrap(tools.first?["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, "web_search")
        XCTAssertNotNil(function["parameters"] as? [String: Any])

        let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
        XCTAssertEqual(messages[1]["role"] as? String, "assistant")
        XCTAssertEqual((messages[1]["tool_calls"] as? [[String: Any]])?.first?["id"] as? String, "call_1")
        XCTAssertEqual(messages[2]["role"] as? String, "tool")
        XCTAssertEqual(messages[2]["tool_call_id"] as? String, "call_1")
    }

    func testAnthropicCompatibleEncodesFunctionLoopAndParsesToolUse() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("alibaba-key", for: .alibabaCodingPlan)
        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"""
            {
              "content":[{
                "type":"tool_use",
                "id":"toolu_2",
                "name":"fetch_url",
                "input":{"url":"https://example.com"}
              }]
            }
            """#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }
        let priorCall = ToolCall(
            id: "toolu_1",
            name: "web_search",
            argumentsJSON: #"{"query":"swift"}"#,
            providerMetadata: nil
        )
        let request = ProviderRequest(
            model: "qwen3.5-plus",
            messages: [
                ProviderRequestMessage(role: "user", content: "search"),
                ProviderRequestMessage(role: "assistant", content: "", toolCalls: [priorCall]),
                ProviderRequestMessage(
                    role: "tool",
                    content: #"{"results":[]}"#,
                    toolCallId: "toolu_1",
                    toolName: "web_search"
                )
            ],
            stream: false,
            tools: [
                ToolDefinition(
                    name: "web_search",
                    description: "Search",
                    parametersJSON: #"{"type":"object","properties":{"query":{"type":"string"}}}"#
                )
                .providerTool
            ],
            metadata: ["provider": "ALIBABA_CODING_PLAN"]
        )

        let response = try await AnthropicCompatibleProviderClient().generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        XCTAssertEqual(response.toolCalls.first?.id, "toolu_2")
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(httpClient.lastRequest?.body)) as? [String: Any]
        )
        let tools = try XCTUnwrap(root["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.first?["name"] as? String, "web_search")
        XCTAssertNotNil(tools.first?["input_schema"] as? [String: Any])
        let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
        let assistantContent = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(assistantContent.first?["type"] as? String, "tool_use")
        let resultContent = try XCTUnwrap(messages[2]["content"] as? [[String: Any]])
        XCTAssertEqual(resultContent.first?["type"] as? String, "tool_result")
        XCTAssertEqual(resultContent.first?["tool_use_id"] as? String, "toolu_1")
    }

    func testGeminiEncodesFunctionLoopAndParsesFunctionCall() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("gemini-key", for: .gemini)
        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"""
            {
              "candidates":[{
                "content":{
                  "parts":[{
                    "functionCall":{
                      "id":"gemini_2",
                      "name":"fetch_url",
                      "args":{"url":"https://example.com"}
                    },
                    "thoughtSignature":"signature-2"
                  }]
                }
              }]
            }
            """#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }
        let priorCall = ToolCall(
            id: "gemini_1",
            name: "web_search",
            argumentsJSON: #"{"query":"swift"}"#,
            providerMetadata: ["thoughtSignature": "signature-1"]
        )
        let request = ProviderRequest(
            model: "gemini-2.5-flash",
            messages: [
                ProviderRequestMessage(role: "user", content: "search"),
                ProviderRequestMessage(role: "assistant", content: "", toolCalls: [priorCall]),
                ProviderRequestMessage(
                    role: "tool",
                    content: #"{"results":[]}"#,
                    toolCallId: "gemini_1",
                    toolName: "web_search"
                )
            ],
            stream: false,
            tools: [
                ToolDefinition(
                    name: "web_search",
                    description: "Search",
                    parametersJSON: #"{"type":"object","properties":{"query":{"type":"string"}}}"#
                )
                .providerTool
            ],
            metadata: ["provider": "GEMINI"]
        )

        let response = try await GeminiProviderClient().generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        XCTAssertEqual(response.toolCalls.first?.name, "fetch_url")
        XCTAssertEqual(response.toolCalls.first?.providerMetadata?["thoughtSignature"], "signature-2")
        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(httpClient.lastRequest?.body)) as? [String: Any]
        )
        let tools = try XCTUnwrap(root["tools"] as? [[String: Any]])
        let declarations = try XCTUnwrap(tools.last?["functionDeclarations"] as? [[String: Any]])
        XCTAssertEqual(declarations.first?["name"] as? String, "web_search")
        let contents = try XCTUnwrap(root["contents"] as? [[String: Any]])
        let assistantParts = try XCTUnwrap(contents[1]["parts"] as? [[String: Any]])
        XCTAssertEqual(assistantParts.first?["thoughtSignature"] as? String, "signature-1")
        let resultParts = try XCTUnwrap(contents[2]["parts"] as? [[String: Any]])
        XCTAssertNotNil(resultParts.first?["functionResponse"] as? [String: Any])
    }

    /// Gemini's Schema does not accept JSON Schema's `additionalProperties` field. The Gemini
    /// provider must strip it (and consolidate all function declarations into one array) so the
    /// client web tools do not trigger HTTP 400 "Cannot find field" rejections.
    func testGeminiStripsAdditionalPropertiesFromFunctionSchema() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("gemini-key", for: .gemini)
        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            // Minimal Gemini non-stream response with no function calls.
            let data = #"""
            {
              "candidates": [{
                "content": {
                  "parts": [{ "text": "ok" }]
                }
              }]
            }
            """#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let request = ProviderRequest(
            model: "gemini-2.5-flash",
            messages: [ProviderRequestMessage(role: "user", content: "hi")],
            stream: false,
            tools: [
                ToolDefinition(
                    name: "web_search",
                    description: "Search",
                    parametersJSON: """
                    {
                      "type": "object",
                      "properties": {
                        "query": { "type": "string", "description": "The search query." },
                        "max_results": { "type": "integer", "minimum": 1, "maximum": 8, "default": 8 }
                      },
                      "required": ["query"],
                      "additionalProperties": false
                    }
                    """
                ).providerTool,
                ToolDefinition(
                    name: "fetch_url",
                    description: "Fetch",
                    parametersJSON: """
                    {
                      "type": "object",
                      "properties": {
                        "url": { "type": "string", "description": "The URL to fetch." }
                      },
                      "required": ["url"],
                      "additionalProperties": false
                    }
                    """
                ).providerTool
            ],
            metadata: ["provider": "GEMINI"]
        )

        _ = try await GeminiProviderClient().generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(httpClient.lastRequest?.body)) as? [String: Any]
        )
        let tools = try XCTUnwrap(root["tools"] as? [[String: Any]])

        // All function declarations must be consolidated into a single functionDeclarations array.
        let declarationEntries = tools.filter { $0["functionDeclarations"] != nil }
        XCTAssertEqual(declarationEntries.count, 1, "function declarations should be consolidated into one tools entry")

        let declarations = try XCTUnwrap(declarationEntries.first?["functionDeclarations"] as? [[String: Any]])
        XCTAssertEqual(declarations.count, 2)
        let names = declarations.compactMap { $0["name"] as? String }
        XCTAssertEqual(Set(names), Set(["web_search", "fetch_url"]))

        // No serialized payload may mention additionalProperties anywhere in the request body.
        let bodyString = String(data: try XCTUnwrap(httpClient.lastRequest?.body), encoding: .utf8) ?? ""
        XCTAssertFalse(
            bodyString.contains("additionalProperties"),
            "Gemini request must not include additionalProperties in tool schemas"
        )

        // The supported schema fields should still be present.
        let webSearchParams = try XCTUnwrap(declarations.first { $0["name"] as? String == "web_search" }?["parameters"] as? [String: Any])
        XCTAssertNotNil(webSearchParams["properties"])
        XCTAssertEqual(webSearchParams["required"] as? [String], ["query"])
    }

    func testGeminiSanitizesCustomFunctionDeclarationsIncludingOpenAIWrapperShape() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("gemini-key", for: .gemini)
        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"""
            {
              "candidates": [{
                "content": {
                  "parts": [{ "text": "ok" }]
                }
              }]
            }
            """#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        // Pasted in OpenAI's nested {"type": "function", "function": {...}} shape, as a user
        // sharing tool definitions across providers might do.
        let openAIStyleDeclarations = """
        [
          {
            "type": "function",
            "function": {
              "name": "custom_tool",
              "description": "A custom tool",
              "parameters": {
                "type": "object",
                "properties": {
                  "query": { "type": "string" }
                },
                "required": ["query"],
                "additionalProperties": false,
                "oneOf": [{ "required": ["query"] }]
              }
            }
          }
        ]
        """

        let request = ProviderRequest(
            model: "gemini-2.5-flash",
            messages: [ProviderRequestMessage(role: "user", content: "hi")],
            stream: false,
            tools: [ProviderTool(type: "function_declarations", payload: ["json": openAIStyleDeclarations])],
            metadata: ["provider": "GEMINI"]
        )

        _ = try await GeminiProviderClient().generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        let root = try XCTUnwrap(
            JSONSerialization.jsonObject(with: XCTUnwrap(httpClient.lastRequest?.body)) as? [String: Any]
        )
        let tools = try XCTUnwrap(root["tools"] as? [[String: Any]])
        let declarationEntries = tools.filter { $0["functionDeclarations"] != nil }
        XCTAssertEqual(declarationEntries.count, 1)

        let declarations = try XCTUnwrap(declarationEntries.first?["functionDeclarations"] as? [[String: Any]])
        XCTAssertEqual(declarations.count, 1)
        XCTAssertEqual(declarations.first?["name"] as? String, "custom_tool")
        XCTAssertNil(declarations.first?["function"], "the OpenAI wrapper key should be unwrapped, not forwarded")
        XCTAssertNil(declarations.first?["type"], "the OpenAI wrapper's own type field should not leak through")

        let bodyString = String(data: try XCTUnwrap(httpClient.lastRequest?.body), encoding: .utf8) ?? ""
        XCTAssertFalse(bodyString.contains("additionalProperties"))
        XCTAssertFalse(bodyString.contains("oneOf"))

        let parameters = try XCTUnwrap(declarations.first?["parameters"] as? [String: Any])
        XCTAssertNotNil(parameters["properties"])
        XCTAssertEqual(parameters["required"] as? [String], ["query"])
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

    func testOpenRouterClaudeRequestEnablesPromptCacheControl() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("openrouter-key", for: .openRouter)

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = OpenAICompatibleProviderClient()
        let request = ProviderRequest(
            model: "anthropic/claude-sonnet-4.6",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: false,
            tools: [],
            thinking: nil,
            metadata: ["provider": "OPENROUTER"]
        )

        _ = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        let captured = try XCTUnwrap(httpClient.lastRequest)
        let bodyData = try XCTUnwrap(captured.body)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let cacheControl = try XCTUnwrap(root["cache_control"] as? [String: Any])
        XCTAssertEqual(cacheControl["type"] as? String, "ephemeral")
        XCTAssertNil(root["prompt_cache_key"])
    }

    func testOpenAIGenerateIncludesConversationPromptCacheKey() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("openai-key", for: .openAI)

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = OpenAICompatibleProviderClient()
        let request = ProviderRequest(
            model: "gpt-4o-mini",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: false,
            tools: [],
            thinking: nil,
            metadata: [
                "provider": "OPENAI",
                "promptCacheKey": "conversation-42"
            ]
        )

        _ = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        let captured = try XCTUnwrap(httpClient.lastRequest)
        let bodyData = try XCTUnwrap(captured.body)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(root["prompt_cache_key"] as? String, "conversation-42")
        XCTAssertNil(root["cache_control"])
    }


    func testAlibabaCodingPlanGenerateUsesDedicatedBaseURLAndCredential() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("alibaba-key", for: .alibabaCodingPlan)

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"""
            {
              "content":[{"type":"text","text":"ok"}],
              "usage":{
                "input_tokens":12,
                "output_tokens":7,
                "cache_creation_input_tokens":4,
                "cache_read_input_tokens":2
              }
            }
            """#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = AnthropicCompatibleProviderClient()
        let request = ProviderRequest(
            model: "qwen3.5-plus",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            systemPrompt: "be helpful",
            stream: false,
            tools: [],
            thinking: nil,
            metadata: ["provider": "ALIBABA_CODING_PLAN"]
        )

        let response = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        XCTAssertEqual(response.text, "ok")

        let captured = try XCTUnwrap(httpClient.lastRequest)
        XCTAssertEqual(
            captured.url.absoluteString,
            "https://coding-intl.dashscope.aliyuncs.com/apps/anthropic/v1/messages"
        )
        XCTAssertEqual(captured.headers["x-api-key"], "alibaba-key")
        XCTAssertEqual(captured.headers["anthropic-version"], "2023-06-01")
        XCTAssertNil(captured.headers["Authorization"])

        let bodyData = try XCTUnwrap(captured.body)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(root["model"] as? String, "qwen3.5-plus")
        XCTAssertEqual(root["system"] as? String, "be helpful")
        XCTAssertEqual(root["max_tokens"] as? Int, 4096)
        let messages = try XCTUnwrap(root["messages"] as? [[String: Any]])
        let first = try XCTUnwrap(messages.first)
        XCTAssertEqual(first["role"] as? String, "user")
        let content = try XCTUnwrap(first["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "text")
        XCTAssertEqual(content.first?["text"] as? String, "hello")

        let usage = try XCTUnwrap(response.usage)
        XCTAssertEqual(usage.inputTokens, 12)
        XCTAssertEqual(usage.outputTokens, 7)
        XCTAssertEqual(usage.totalTokens, 19)
        XCTAssertEqual(usage.cachedInputTokens, 2)
        XCTAssertEqual(usage.cacheCreationInputTokens, 4)
    }

    func testAlibabaCodingPlanGenerateIncludesRemoteMCPConnectorPayload() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("alibaba-key", for: .alibabaCodingPlan)
        try store.saveSecret("mcp-token", key: AppConstants.alibabaMCPAuthorizationTokenKey)

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"""
            {
              "content":[{"type":"text","text":"ok"}]
            }
            """#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = AnthropicCompatibleProviderClient()
        let request = ProviderRequest(
            model: "qwen3.5-plus",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: false,
            tools: [
                ProviderTool(
                    type: "mcp_toolset",
                    payload: [
                        "server_url": "https://mcp.firecrawl.dev/fc-key/v2/mcp",
                        "server_name": "firecrawl",
                        "allowed_tools": "search, extract"
                    ]
                )
            ],
            thinking: nil,
            metadata: ["provider": "ALIBABA_CODING_PLAN"]
        )

        _ = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        let captured = try XCTUnwrap(httpClient.lastRequest)
        XCTAssertEqual(captured.headers["anthropic-beta"], "mcp-client-2025-11-20")

        let bodyData = try XCTUnwrap(captured.body)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let mcpServers = try XCTUnwrap(root["mcp_servers"] as? [[String: Any]])
        XCTAssertEqual(mcpServers.count, 1)
        XCTAssertEqual(mcpServers.first?["type"] as? String, "url")
        XCTAssertEqual(mcpServers.first?["url"] as? String, "https://mcp.firecrawl.dev/fc-key/v2/mcp")
        XCTAssertEqual(mcpServers.first?["name"] as? String, "firecrawl")
        XCTAssertEqual(mcpServers.first?["authorization_token"] as? String, "mcp-token")

        let tools = try XCTUnwrap(root["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools.first?["type"] as? String, "mcp_toolset")
        XCTAssertEqual(tools.first?["mcp_server_name"] as? String, "firecrawl")
        let defaultConfig = try XCTUnwrap(tools.first?["default_config"] as? [String: Any])
        XCTAssertEqual(defaultConfig["enabled"] as? Bool, false)
        let configs = try XCTUnwrap(tools.first?["configs"] as? [String: Any])
        let searchConfig = try XCTUnwrap(configs["search"] as? [String: Any])
        let extractConfig = try XCTUnwrap(configs["extract"] as? [String: Any])
        XCTAssertEqual(searchConfig["enabled"] as? Bool, true)
        XCTAssertEqual(extractConfig["enabled"] as? Bool, true)
    }

    func testAlibabaStreamMessageStartUsageOnly() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("alibaba-key", for: .alibabaCodingPlan)

        let httpClient = CapturingHTTPClient()
        httpClient.streamResponder = { request in
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield(#"data: {"type":"message_start","message":{"usage":{"input_tokens":21,"cache_creation_input_tokens":6,"cache_read_input_tokens":3}}}"#)
                continuation.yield("")
                continuation.yield(#"data: {"type":"message_stop"}"#)
                continuation.yield("")
                continuation.finish()
            }
            return (stream, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = AnthropicCompatibleProviderClient()
        let request = ProviderRequest(
            model: "qwen3.5-plus",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: true,
            tools: [],
            thinking: nil,
            metadata: ["provider": "ALIBABA_CODING_PLAN"]
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

        XCTAssertEqual(final?.usage?.inputTokens, 21)
        XCTAssertEqual(final?.usage?.cachedInputTokens, 3)
        XCTAssertEqual(final?.usage?.cacheCreationInputTokens, 6)
    }

    func testAlibabaCodingPlanStreamParsesAnthropicStyleChunks() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("alibaba-key", for: .alibabaCodingPlan)

        let httpClient = CapturingHTTPClient()
        httpClient.streamResponder = { request in
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield("event: message_start")
                continuation.yield(#"data: {"type":"message_start","message":{"usage":{"input_tokens":21,"cache_creation_input_tokens":6,"cache_read_input_tokens":3}}}"#)
                continuation.yield("")
                continuation.yield("event: content_block_delta")
                continuation.yield(#"data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"Plan "}}"#)
                continuation.yield("")
                continuation.yield("event: content_block_delta")
                continuation.yield(#"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Ali"}}"#)
                continuation.yield("")
                continuation.yield(#"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"baba"}}"#)
                continuation.yield("")
                continuation.yield(
                    #"data: {"type":"message_delta","usage":{"input_tokens":21,"output_tokens":8,"cache_read_input_tokens":3,"cache_creation_input_tokens":6}}"#
                )
                continuation.yield("")
                continuation.yield(#"data: {"type":"message_stop"}"#)
                continuation.yield("")
                continuation.finish()
            }
            return (stream, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = AnthropicCompatibleProviderClient()
        let request = ProviderRequest(
            model: "qwen3.5-plus",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: true,
            tools: [],
            thinking: nil,
            metadata: ["provider": "ALIBABA_CODING_PLAN"]
        )

        let stream = client.stream(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        var events: [ProviderStreamEvent] = []
        var final: ProviderResponse?
        for try await event in stream {
            events.append(event)
            if case let .completed(response) = event {
                final = response
            }
        }

        XCTAssertEqual(events[0], .reasoningDelta("Plan "))
        XCTAssertEqual(events[1], .textDelta("Ali"))
        XCTAssertEqual(events[2], .textDelta("baba"))
        XCTAssertEqual(final?.text, "Alibaba")
        XCTAssertEqual(final?.reasoningSummary, "Plan ")
        let usage = try XCTUnwrap(final?.usage)
        XCTAssertEqual(usage.inputTokens, 21)
        XCTAssertEqual(usage.outputTokens, 8)
        XCTAssertEqual(usage.totalTokens, 29)
        XCTAssertEqual(usage.cachedInputTokens, 3)
        XCTAssertEqual(usage.cacheCreationInputTokens, 6)

        let captured = try XCTUnwrap(httpClient.lastRequest)
        XCTAssertEqual(captured.headers["Accept"], "text/event-stream")
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
                continuation.yield("")
                continuation.yield(#"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#)
                continuation.yield("")
                continuation.yield(#"data: {"usage":{"prompt_tokens":100,"completion_tokens":20,"total_tokens":120,"completion_tokens_details":{"reasoning_tokens":4},"prompt_tokens_details":{"cached_tokens":16}}}"#)
                continuation.yield("")
                continuation.yield("data: [DONE]")
                continuation.yield("")
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

    func testOpenRouterStreamIncludesErrorBodyOnHTTP404() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("openrouter-key", for: .openRouter)

        let httpClient = CapturingHTTPClient()
        httpClient.streamResponder = { request in
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield(
                    #"{"error":{"message":"No allowed providers are available for the selected model."}}"#
                )
                continuation.finish()
            }
            return (stream, Self.makeHTTPResponse(url: request.url, statusCode: 404))
        }

        let client = OpenAICompatibleProviderClient()
        let request = ProviderRequest(
            model: "liquid/lfm-2.5-1.2b-thinking:free",
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

        do {
            for try await _ in stream {}
            XCTFail("Expected stream to fail with HTTP 404")
        } catch let error as ProviderClientError {
            guard case let .httpStatus(code, body) = error else {
                return XCTFail("Unexpected ProviderClientError: \(error)")
            }
            XCTAssertEqual(code, 404)
            XCTAssertTrue(body.contains("No allowed providers are available for the selected model."))
        }
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

    func testOpenCodeGoChatModelUsesChatCompletionsEndpointAndCacheKey() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("go-key", for: .openCodeGo)

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"{"choices":[{"message":{"content":"ok"}}],"usage":{"prompt_tokens":20,"completion_tokens":5,"prompt_tokens_details":{"cached_tokens":12}}}"#
                .data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = OpenCodeGoProviderClient()
        let request = ProviderRequest(
            model: "opencode-go/kimi-k2.6",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            systemPrompt: "stable system",
            stream: false,
            tools: [],
            thinking: nil,
            metadata: ["provider": "OPENCODE_GO", "promptCacheKey": "conversation-42"]
        )

        let response = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        XCTAssertEqual(response.text, "ok")
        XCTAssertEqual(response.usage?.cachedInputTokens, 12)

        let captured = try XCTUnwrap(httpClient.lastRequest)
        XCTAssertEqual(captured.url.absoluteString, "https://opencode.ai/zen/go/v1/chat/completions")
        XCTAssertEqual(captured.headers["Authorization"], "Bearer go-key")

        let bodyData = try XCTUnwrap(captured.body)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "kimi-k2.6")
        XCTAssertEqual(body["prompt_cache_key"] as? String, "conversation-42")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["role"] as? String, "system")
        XCTAssertEqual(messages.first?["content"] as? String, "stable system")
    }

    func testOpenCodeGoChatModelPassesBackAssistantReasoningContent() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("go-key", for: .openCodeGo)

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = OpenCodeGoProviderClient()
        let request = ProviderRequest(
            model: "deepseek-v4-flash",
            messages: [
                ProviderRequestMessage(role: "user", content: "hello"),
                ProviderRequestMessage(role: "assistant", content: "answer", reasoningContent: "kept reasoning"),
                ProviderRequestMessage(role: "user", content: "again", reasoningContent: "ignored")
            ],
            stream: false,
            tools: [],
            thinking: nil,
            metadata: ["provider": "OPENCODE_GO"]
        )

        _ = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        let bodyData = try XCTUnwrap(httpClient.lastRequest?.body)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages[1]["role"] as? String, "assistant")
        XCTAssertEqual(messages[1]["reasoning_content"] as? String, "kept reasoning")
        XCTAssertNil(messages[2]["reasoning_content"])
    }

    func testOpenCodeGoMiniMaxModelUsesMessagesEndpoint() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("go-key", for: .openCodeGo)

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"{"content":[{"type":"text","text":"ok"}],"usage":{"input_tokens":10,"output_tokens":3,"cache_read_input_tokens":7}}"#
                .data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = OpenCodeGoProviderClient()
        let request = ProviderRequest(
            model: "minimax-m2.7",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            systemPrompt: "stable system",
            stream: false,
            tools: [],
            thinking: nil,
            metadata: ["provider": "OPENCODE_GO"]
        )

        let response = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        XCTAssertEqual(response.text, "ok")
        XCTAssertEqual(response.usage?.cachedInputTokens, 7)

        let captured = try XCTUnwrap(httpClient.lastRequest)
        XCTAssertEqual(captured.url.absoluteString, "https://opencode.ai/zen/go/v1/messages")
        XCTAssertEqual(captured.headers["x-api-key"], "go-key")
        XCTAssertEqual(captured.headers["anthropic-version"], "2023-06-01")

        let bodyData = try XCTUnwrap(captured.body)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "minimax-m2.7")
        XCTAssertEqual(body["system"] as? String, "stable system")
        XCTAssertNil(body["prompt_cache_key"])
    }

    func testOpenCodeGoQwenPlusModelUsesMessagesEndpoint() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("go-key", for: .openCodeGo)

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"{"content":[{"type":"text","text":"qwen ok"}],"usage":{"input_tokens":4,"output_tokens":2}}"#
                .data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = OpenCodeGoProviderClient()
        let request = ProviderRequest(
            model: "qwen3.7-plus",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: false,
            tools: [],
            thinking: nil,
            metadata: ["provider": "OPENCODE_GO"]
        )

        let response = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        XCTAssertEqual(response.text, "qwen ok")
        let captured = try XCTUnwrap(httpClient.lastRequest)
        XCTAssertEqual(captured.url.absoluteString, "https://opencode.ai/zen/go/v1/messages")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(captured.body)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "qwen3.7-plus")
    }

    func testOpenCodeGoQwenMaxModelUsesMessagesEndpoint() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("go-key", for: .openCodeGo)

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"{"content":[{"type":"text","text":"qwen max ok"}],"usage":{"input_tokens":4,"output_tokens":2}}"#
                .data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = OpenCodeGoProviderClient()
        let request = ProviderRequest(
            model: "opencode-go/qwen3.7-max",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: false,
            tools: [],
            thinking: nil,
            metadata: ["provider": "OPENCODE_GO"]
        )

        let response = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        XCTAssertEqual(response.text, "qwen max ok")
        let captured = try XCTUnwrap(httpClient.lastRequest)
        XCTAssertEqual(captured.url.absoluteString, "https://opencode.ai/zen/go/v1/messages")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(captured.body)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "qwen3.7-max")
    }

    func testOpenCodeGoMessagesStreamParsesAnthropicStyleChunks() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("go-key", for: .openCodeGo)

        let httpClient = CapturingHTTPClient()
        httpClient.streamResponder = { request in
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield("event: content_block_delta")
                continuation.yield(#"data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"Plan "}}"#)
                continuation.yield("")
                continuation.yield("event: content_block_delta")
                continuation.yield(#"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Go"}}"#)
                continuation.yield("")
                continuation.yield(#"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":" stream"}}"#)
                continuation.yield("")
                continuation.yield(#"data: {"type":"message_stop"}"#)
                continuation.yield("")
                continuation.finish()
            }
            return (stream, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = OpenCodeGoProviderClient()
        let request = ProviderRequest(
            model: "minimax-m2.7",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: true,
            tools: [],
            thinking: nil,
            metadata: ["provider": "OPENCODE_GO"]
        )

        let stream = client.stream(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        var textDeltas: [String] = []
        var reasoningDeltas: [String] = []
        var final: ProviderResponse?
        for try await event in stream {
            switch event {
            case let .textDelta(delta):
                textDeltas.append(delta)
            case let .reasoningDelta(delta):
                reasoningDeltas.append(delta)
            case let .completed(response):
                final = response
            default:
                break
            }
        }

        XCTAssertEqual(reasoningDeltas, ["Plan "])
        XCTAssertEqual(textDeltas, ["Go", " stream"])
        XCTAssertEqual(final?.text, "Go stream")
        XCTAssertEqual(final?.reasoningSummary, "Plan")

        let captured = try XCTUnwrap(httpClient.lastRequest)
        XCTAssertEqual(captured.headers["Accept"], "text/event-stream")
        XCTAssertEqual(captured.url.absoluteString, "https://opencode.ai/zen/go/v1/messages")
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(captured.body)) as? [String: Any])
        XCTAssertEqual(body["stream"] as? Bool, true)
    }

    func testOpenCodeGoChatModelEmbedsImageAsImageURL() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("go-key", for: .openCodeGo)

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        try imageData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let client = OpenCodeGoProviderClient()
        let request = ProviderRequest(
            model: "kimi-k2.6",
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
            metadata: ["provider": "OPENCODE_GO", "supportsVision": "true"]
        )

        _ = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        let bodyData = try XCTUnwrap(httpClient.lastRequest?.body)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let userMessage = try XCTUnwrap(messages.last)
        let content = try XCTUnwrap(userMessage["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "text")
        XCTAssertEqual(content.first?["text"] as? String, "describe this image")
        XCTAssertEqual(content.last?["type"] as? String, "image_url")
        let imageURL = try XCTUnwrap(content.last?["image_url"] as? [String: Any])
        let url = try XCTUnwrap(imageURL["url"] as? String)
        XCTAssertTrue(url.hasPrefix("data:image/png;base64,"))
        XCTAssertFalse(url.contains("Attachments:"))
        XCTAssertFalse(url.contains("file://"))
    }

    func testOpenCodeGoMiniMaxModelEmbedsImageBlock() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("go-key", for: .openCodeGo)

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"{"content":[{"type":"text","text":"ok"}],"usage":{"input_tokens":1,"output_tokens":1}}"#
                .data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        let imageData = Data([0x89, 0x50, 0x4E, 0x47])
        try imageData.write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let client = OpenCodeGoProviderClient()
        let request = ProviderRequest(
            model: "minimax-m2.7",
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
            metadata: ["provider": "OPENCODE_GO", "supportsVision": "true"]
        )

        _ = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        let bodyData = try XCTUnwrap(httpClient.lastRequest?.body)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let content = try XCTUnwrap(messages.first?["content"] as? [[String: Any]])
        XCTAssertEqual(content.first?["type"] as? String, "text")
        XCTAssertEqual(content.last?["type"] as? String, "image")
        let source = try XCTUnwrap(content.last?["source"] as? [String: Any])
        XCTAssertEqual(source["type"] as? String, "base64")
        XCTAssertEqual(source["media_type"] as? String, "image/png")
        XCTAssertEqual(source["data"] as? String, imageData.base64EncodedString())
    }

    func testOpenCodeGoChatModelSkipsImageWhenVisionDisabled() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("go-key", for: .openCodeGo)

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("png")
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: tempURL)
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let client = OpenCodeGoProviderClient()
        let request = ProviderRequest(
            model: "kimi-k2.6",
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
            metadata: ["provider": "OPENCODE_GO", "supportsVision": "false"]
        )

        _ = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        let bodyData = try XCTUnwrap(httpClient.lastRequest?.body)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        let userMessage = try XCTUnwrap(messages.last)
        let content = userMessage["content"]
        if let text = content as? String {
            XCTAssertEqual(text, "describe this image")
            XCTAssertFalse(text.contains("Attachments:"))
            XCTAssertFalse(text.contains("file://"))
        } else {
            XCTFail("Expected plain string content when vision is disabled")
        }
    }

    func testOpenCodeGoDeepSeekStreamParsesBackToBackDataLines() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("go-key", for: .openCodeGo)

        let httpClient = CapturingHTTPClient()
        httpClient.streamResponder = { request in
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield(#"data: {"choices":[{"delta":{"reasoning_content":"考"}}]}"#)
                continuation.yield(#"data: {"choices":[{"delta":{"reasoning_content":"え"}}]}"#)
                continuation.yield(#"data: {"choices":[{"delta":{"content":"答"}}]}"#)
                continuation.yield(#"data: {"choices":[{"delta":{"content":"え"}}]}"#)
                continuation.yield("data: [DONE]")
                continuation.finish()
            }
            return (stream, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = OpenCodeGoProviderClient()
        let request = ProviderRequest(
            model: "deepseek-v4-flash",
            messages: [ProviderRequestMessage(role: "user", content: "hi")],
            stream: true,
            tools: [],
            thinking: nil,
            metadata: ["provider": "OPENCODE_GO"]
        )

        let stream = client.stream(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        var textDeltas: [String] = []
        var reasoningDeltas: [String] = []
        var final: ProviderResponse?
        for try await event in stream {
            switch event {
            case let .textDelta(delta):
                textDeltas.append(delta)
            case let .reasoningDelta(delta):
                reasoningDeltas.append(delta)
            case let .completed(response):
                final = response
            default:
                break
            }
        }

        XCTAssertEqual(reasoningDeltas, ["考", "え"])
        XCTAssertEqual(textDeltas, ["答", "え"])
        XCTAssertEqual(final?.text, "答え")
        XCTAssertEqual(final?.reasoningSummary, "考え")

        let captured = try XCTUnwrap(httpClient.lastRequest)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(captured.body)) as? [String: Any])
        XCTAssertEqual(body["stream"] as? Bool, true)
        let streamOptions = try XCTUnwrap(body["stream_options"] as? [String: Any])
        XCTAssertEqual(streamOptions["include_usage"] as? Bool, true)
    }

    func testOpenCodeGoChatStreamParsesReasoningContent() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("go-key", for: .openCodeGo)

        let httpClient = CapturingHTTPClient()
        httpClient.streamResponder = { request in
            let stream = AsyncThrowingStream<String, Error> { continuation in
                continuation.yield(#"data: {"choices":[{"delta":{"reasoning_content":"考"}}]}"#)
                continuation.yield("")
                continuation.yield(#"data: {"choices":[{"delta":{"reasoning_content":"考え中"}}]}"#)
                continuation.yield("")
                continuation.yield(#"data: {"choices":[{"delta":{"content":"こんにちは"}}]}"#)
                continuation.yield("")
                continuation.yield("data: [DONE]")
                continuation.yield("")
                continuation.finish()
            }
            return (stream, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = OpenCodeGoProviderClient()
        let request = ProviderRequest(
            model: "deepseek-v4-flash",
            messages: [ProviderRequestMessage(role: "user", content: "た")],
            stream: true,
            tools: [],
            thinking: nil,
            metadata: ["provider": "OPENCODE_GO"]
        )

        let stream = client.stream(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        var textDeltas: [String] = []
        var reasoningDeltas: [String] = []
        var final: ProviderResponse?
        for try await event in stream {
            switch event {
            case let .textDelta(delta):
                textDeltas.append(delta)
            case let .reasoningDelta(delta):
                reasoningDeltas.append(delta)
            case let .completed(response):
                final = response
            default:
                break
            }
        }

        XCTAssertEqual(reasoningDeltas, ["考", "え中"])
        XCTAssertEqual(textDeltas, ["こんにちは"])
        XCTAssertEqual(final?.text, "こんにちは")
        XCTAssertEqual(final?.reasoningSummary, "考え中")
    }

    func testOpenCodeGoChatResponseParsesArrayContent() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("go-key", for: .openCodeGo)

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"{"choices":[{"message":{"content":[{"type":"text","text":"ok"}],"reasoning_content":"think"}}],"usage":{"prompt_tokens":1,"completion_tokens":1}}"#
                .data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = OpenCodeGoProviderClient()
        let request = ProviderRequest(
            model: "deepseek-v4-flash",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: false,
            tools: [],
            thinking: nil,
            metadata: ["provider": "OPENCODE_GO"]
        )

        let response = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        XCTAssertEqual(response.text, "ok")
        XCTAssertEqual(response.reasoningSummary, "think")
    }

    func testOpenCodeGoUnsupportedModelFailsInsteadOfFallback() async throws {
        let store = ProviderTestCredentialStore()
        try store.setCredential("go-key", for: .openCodeGo)

        let client = OpenCodeGoProviderClient()
        let request = ProviderRequest(
            model: "not-official",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: false,
            tools: [],
            thinking: nil,
            metadata: ["provider": "OPENCODE_GO"]
        )

        do {
            _ = try await client.generate(
                request: request,
                settings: AppSettings(),
                credentialStore: store,
                httpClient: CapturingHTTPClient()
            )
            XCTFail("Expected unsupported model to fail")
        } catch let error as ProviderClientError {
            guard case let .invalidBaseURL(message) = error else {
                return XCTFail("Expected invalidBaseURL, got \(error)")
            }
            XCTAssertTrue(message.contains("Unsupported OpenCode Go model"))
        }
    }

    func testSuperGrokGenerateUsesChatCompletionsEndpointAndBearerToken() async throws {
        let store = ProviderTestCredentialStore()
        try store.setSuperGrokAccessToken("supergrok-oauth-token")

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"{"choices":[{"message":{"content":"ok","reasoning_content":"plan"}}],"usage":{"prompt_tokens":20,"completion_tokens":5,"completion_tokens_details":{"reasoning_tokens":3}}}"#
                .data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = SuperGrokProviderClient()
        let request = ProviderRequest(
            model: "grok-build-0.1",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            systemPrompt: "stable system",
            stream: false,
            tools: [],
            thinking: ProviderThinkingConfig(enabled: true, budget: nil, effort: "medium", exclude: nil),
            metadata: ["provider": "SUPERGROK"]
        )

        let response = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        XCTAssertEqual(response.text, "ok")
        XCTAssertEqual(response.reasoningSummary, "plan")
        XCTAssertEqual(response.usage?.reasoningTokens, 3)

        let captured = try XCTUnwrap(httpClient.lastRequest)
        XCTAssertEqual(captured.url.absoluteString, "https://api.x.ai/v1/chat/completions")
        XCTAssertEqual(captured.headers["Authorization"], "Bearer supergrok-oauth-token")

        let bodyData = try XCTUnwrap(captured.body)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "grok-build-0.1")
        XCTAssertEqual((body["reasoning"] as? [String: Any])?["enabled"] as? Bool, true)
        XCTAssertEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, "medium")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.first?["role"] as? String, "system")
        XCTAssertEqual(messages.first?["content"] as? String, "stable system")
    }

    func testSuperGrokPassesBackAssistantReasoningContent() async throws {
        let store = ProviderTestCredentialStore()
        try store.setSuperGrokAccessToken("supergrok-oauth-token")

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = SuperGrokProviderClient()
        let request = ProviderRequest(
            model: "grok-4.3",
            messages: [
                ProviderRequestMessage(role: "user", content: "hello"),
                ProviderRequestMessage(role: "assistant", content: "answer", reasoningContent: "kept reasoning"),
                ProviderRequestMessage(role: "user", content: "again", reasoningContent: "ignored")
            ],
            stream: false,
            tools: [],
            thinking: nil,
            metadata: ["provider": "SUPERGROK"]
        )

        _ = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        let bodyData = try XCTUnwrap(httpClient.lastRequest?.body)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertEqual(messages[1]["role"] as? String, "assistant")
        XCTAssertEqual(messages[1]["reasoning_content"] as? String, "kept reasoning")
        XCTAssertNil(messages[2]["reasoning_content"])
    }

    func testSuperGrokCustomModelPassesThroughWithoutCatalogLookup() async throws {
        let store = ProviderTestCredentialStore()
        try store.setSuperGrokAccessToken("supergrok-oauth-token")

        let httpClient = CapturingHTTPClient()
        httpClient.sendResponder = { request in
            let data = #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!
            return (data, Self.makeHTTPResponse(url: request.url, statusCode: 200))
        }

        let client = SuperGrokProviderClient()
        let request = ProviderRequest(
            model: "supergrok/custom-experimental",
            messages: [ProviderRequestMessage(role: "user", content: "hello")],
            stream: false,
            tools: [],
            thinking: ProviderThinkingConfig(enabled: true, budget: nil, effort: "high", exclude: nil),
            metadata: ["provider": "SUPERGROK"]
        )

        _ = try await client.generate(
            request: request,
            settings: AppSettings(),
            credentialStore: store,
            httpClient: httpClient
        )

        let bodyData = try XCTUnwrap(httpClient.lastRequest?.body)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: bodyData) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "custom-experimental")
        XCTAssertEqual((body["reasoning"] as? [String: Any])?["effort"] as? String, "high")
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

    func testGeminiClassifiesRateLimitOn429() {
        let error = ProviderClientError.httpStatus(429, "")
        XCTAssertEqual(GeminiProviderClient.classifyRotationEligibility(error), .rateLimited)
    }

    func testGeminiClassifiesRateLimitOnResourceExhaustedBodyEvenWithoutStatus429() {
        let body = #"{"error":{"code":429,"message":"quota","status":"RESOURCE_EXHAUSTED"}}"#
        let error = ProviderClientError.httpStatus(500, body)
        XCTAssertEqual(GeminiProviderClient.classifyRotationEligibility(error), .rateLimited)
    }

    func testGeminiClassifiesAuthFailureOn401And403() {
        XCTAssertEqual(GeminiProviderClient.classifyRotationEligibility(ProviderClientError.httpStatus(401, "")), .authFailure)
        XCTAssertEqual(GeminiProviderClient.classifyRotationEligibility(ProviderClientError.httpStatus(403, "")), .authFailure)
    }

    func testGeminiDoesNotClassifyBadRequestOrServerErrorAsRotationEligible() {
        let badRequest = ProviderClientError.httpStatus(400, #"{"error":{"status":"INVALID_ARGUMENT"}}"#)
        let serverError = ProviderClientError.httpStatus(500, #"{"error":{"status":"INTERNAL"}}"#)
        XCTAssertEqual(GeminiProviderClient.classifyRotationEligibility(badRequest), .other)
        XCTAssertEqual(GeminiProviderClient.classifyRotationEligibility(serverError), .other)
    }

    func testGeminiClassifiesNonHTTPStatusErrorAsOther() {
        XCTAssertEqual(GeminiProviderClient.classifyRotationEligibility(ProviderClientError.parseFailure("x")), .other)
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
                continuation.yield("")
                continuation.yield(#"data: {"type":"response.completed","response":{"usage":{"input_tokens":21,"output_tokens":9,"total_tokens":30,"input_tokens_details":{"cached_tokens":3},"output_tokens_details":{"reasoning_tokens":4}}}}"#)
                continuation.yield("")
                continuation.yield("data: [DONE]")
                continuation.yield("")
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
