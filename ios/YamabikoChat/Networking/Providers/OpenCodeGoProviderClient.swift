import CryptoKit
import Foundation

struct OpenCodeGoProviderClient: ProviderClient {
    let provider: LLMProvider = .openCodeGo

    private static let anthropicVersion = "2023-06-01"
    private static let defaultMaxTokens = 4096

    private struct ChatStreamOptions: Encodable {
        var includeUsage: Bool = true

        enum CodingKeys: String, CodingKey {
            case includeUsage = "include_usage"
        }
    }

    private struct ChatRequestBody: Encodable {
        var model: String
        var messages: [OpenAICompatibleWireMessage]
        var stream: Bool
        var tools: [[String: AnyEncodable]]?
        var maxTokens: Int?
        var temperature: Double?
        var promptCacheKey: String?
        var streamOptions: ChatStreamOptions?

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case stream
            case tools
            case maxTokens = "max_tokens"
            case temperature
            case promptCacheKey = "prompt_cache_key"
            case streamOptions = "stream_options"
        }
    }

    private struct MessageRequestBody: Encodable {
        var model: String
        var messages: [AnthropicCompatibleWireMessage]
        var system: String?
        var maxTokens: Int
        var stream: Bool
        var tools: [AnyEncodable]?

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case system
            case maxTokens = "max_tokens"
            case stream
            case tools
        }
    }

    func generate(
        request: ProviderRequest,
        settings: AppSettings,
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol
    ) async throws -> ProviderResponse {
        let route = try route(for: request)
        let apiKey = try resolvedCredential(credentialStore: credentialStore)
        let httpRequest: HTTPRequest
        switch route.endpointKind {
        case .chatCompletions:
            httpRequest = try chatRequest(request: request, route: route, apiKey: apiKey, stream: false)
        case .messages:
            httpRequest = try messagesRequest(request: request, route: route, apiKey: apiKey, stream: false)
        }

        let (data, response) = try await httpClient.send(httpRequest)
        guard (200 ... 299).contains(response.statusCode) else {
            throw ProviderClientError.httpStatus(response.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        switch route.endpointKind {
        case .chatCompletions:
            return try parseChatResponse(data: data)
        case .messages:
            return try parseMessagesResponse(data: data)
        }
    }

    func stream(
        request: ProviderRequest,
        settings: AppSettings,
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol
    ) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let route = try route(for: request)
                    let apiKey = try resolvedCredential(credentialStore: credentialStore)
                    let httpRequest: HTTPRequest
                    switch route.endpointKind {
                    case .chatCompletions:
                        httpRequest = try chatRequest(request: request, route: route, apiKey: apiKey, stream: true)
                    case .messages:
                        httpRequest = try messagesRequest(request: request, route: route, apiKey: apiKey, stream: true)
                    }

                    let (lineStream, response) = try await httpClient.stream(httpRequest)
                    guard (200 ... 299).contains(response.statusCode) else {
                        throw ProviderClientError.httpStatus(response.statusCode, "Streaming endpoint returned \(response.statusCode)")
                    }

                    switch route.endpointKind {
                    case .chatCompletions:
                        try await streamChat(lineStream, continuation: continuation)
                    case .messages:
                        try await streamMessages(lineStream, continuation: continuation)
                    }
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func route(for request: ProviderRequest) throws -> OpenCodeGoModel {
        guard let model = OpenCodeGoModelCatalog.model(for: request.model) else {
            throw ProviderClientError.invalidBaseURL("Unsupported OpenCode Go model: \(request.model)")
        }
        return model
    }

    private func resolvedCredential(credentialStore: SecureCredentialStore) throws -> String {
        guard let apiKey = try credentialStore.credential(for: .openCodeGo)?.trimmedNonEmpty else {
            throw ProviderClientError.missingCredential(LLMProvider.openCodeGo.rawValue)
        }
        return apiKey
    }

    private func chatRequest(
        request: ProviderRequest,
        route: OpenCodeGoModel,
        apiKey: String,
        stream: Bool
    ) throws -> HTTPRequest {
        let endpoint = AppConstants.defaultOpenCodeGoBaseURL.appendingPathComponent("chat/completions")
        let body = ChatRequestBody(
            model: route.id,
            messages: OpenAICompatibleWireMapper.messages(
                request.messages,
                systemPrompt: request.systemPrompt,
                embedImages: ProviderAttachmentEncoder.shouldEmbedImages(metadata: request.metadata),
                providerLabel: "OpenCode Go chat"
            ),
            stream: stream,
            tools: request.tools.isEmpty ? nil : try request.tools.map(openAIToolPayload),
            maxTokens: positiveIntMetadata("max_output_tokens", from: request),
            temperature: doubleMetadata("temperature", from: request),
            promptCacheKey: promptCacheKey(for: request, route: route),
            streamOptions: stream ? ChatStreamOptions() : nil
        )
        var headers = [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json"
        ]
        if stream {
            headers["Accept"] = "text/event-stream"
        }
        return HTTPRequest(
            url: endpoint,
            headers: headers,
            body: try JSONEncoder().encode(body),
            timeoutInterval: request.timeoutInterval
        )
    }

    private func messagesRequest(
        request: ProviderRequest,
        route: OpenCodeGoModel,
        apiKey: String,
        stream: Bool
    ) throws -> HTTPRequest {
        let endpoint = AppConstants.defaultOpenCodeGoBaseURL.appendingPathComponent("messages")
        let body = MessageRequestBody(
            model: route.id,
            messages: AnthropicCompatibleWireMapper.messages(
                request.messages,
                embedImages: ProviderAttachmentEncoder.shouldEmbedImages(metadata: request.metadata),
                providerLabel: "OpenCode Go messages"
            ),
            system: request.systemPrompt?.trimmedNonEmpty,
            maxTokens: positiveIntMetadata("max_output_tokens", from: request) ?? Self.defaultMaxTokens,
            stream: stream,
            tools: AnthropicCompatibleWireMapper.tools(request.tools)
        )
        var headers = [
            "Content-Type": "application/json",
            "x-api-key": apiKey,
            "anthropic-version": Self.anthropicVersion
        ]
        if stream {
            headers["Accept"] = "text/event-stream"
        }
        return HTTPRequest(
            url: endpoint,
            headers: headers,
            body: try JSONEncoder().encode(body),
            timeoutInterval: request.timeoutInterval
        )
    }

    private func promptCacheKey(for request: ProviderRequest, route: OpenCodeGoModel) -> String {
        if let explicit = request.metadata["promptCacheKey"]?.trimmedNonEmpty {
            return explicit
        }
        let seed = [
            route.id,
            request.systemPrompt?.trimmedNonEmpty ?? "",
            request.messages.first?.role ?? "",
            request.messages.first?.content ?? ""
        ].joined(separator: "\n")
        let digest = SHA256.hash(data: Data(seed.utf8)).map { String(format: "%02x", $0) }.joined()
        return "opencode-go-\(String(digest.prefix(48)))"
    }

    private func positiveIntMetadata(_ key: String, from request: ProviderRequest) -> Int? {
        guard let value = Int(request.metadata[key] ?? ""), value > 0 else { return nil }
        return value
    }

    private func doubleMetadata(_ key: String, from request: ProviderRequest) -> Double? {
        guard let value = Double(request.metadata[key] ?? ""), value.isFinite else { return nil }
        return value
    }

    private func parseChatResponse(data: Data) throws -> ProviderResponse {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw ProviderClientError.parseFailure("OpenCode Go chat response is missing choices[0].message")
        }
        let content = OpenAICompatibleStreamParser.openAICompatibleText(from: message["content"])
        let reasoning = OpenAICompatibleStreamParser.reasoningText(from: message)
        return ProviderResponse(
            text: content,
            reasoningSummary: reasoning,
            raw: String(data: data, encoding: .utf8),
            usage: parseUsage(root["usage"] as? [String: Any]),
            toolCalls: parseToolCalls(message["tool_calls"])
        )
    }

    private func parseMessagesResponse(data: Data) throws -> ProviderResponse {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderClientError.parseFailure("OpenCode Go messages response root is not dictionary")
        }
        let text = extractText(from: root["content"]).joined()
        let toolCalls = extractToolCalls(from: root["content"])
        if text.isEmpty && toolCalls.isEmpty {
            throw ProviderClientError.parseFailure("OpenCode Go messages response does not contain text or tool use content")
        }
        return ProviderResponse(
            text: text,
            reasoningSummary: nil,
            raw: String(data: data, encoding: .utf8),
            usage: parseUsage(root["usage"] as? [String: Any]),
            toolCalls: toolCalls
        )
    }

    private func streamChat(
        _ lineStream: AsyncThrowingStream<String, Error>,
        continuation: AsyncThrowingStream<ProviderStreamEvent, Error>.Continuation
    ) async throws {
        try await ProviderSSEStreamRunner.pump(
            lineStream: lineStream,
            continuation: continuation,
            options: openCodeGoSSEOptions(
                usageFromRoot: { parseUsage($0["usage"] as? [String: Any]) },
                eventsFromRoot: { root, fullText, fullReasoning in
                    OpenAICompatibleStreamParser.events(
                        fromRoot: root,
                        fullText: &fullText,
                        fullReasoning: &fullReasoning
                    )
                }
            )
        )
    }

    private func streamMessages(
        _ lineStream: AsyncThrowingStream<String, Error>,
        continuation: AsyncThrowingStream<ProviderStreamEvent, Error>.Continuation
    ) async throws {
        try await ProviderSSEStreamRunner.pump(
            lineStream: lineStream,
            continuation: continuation,
            options: openCodeGoSSEOptions(
                usageFromRoot: parseMessagesStreamUsage,
                eventsFromRoot: { root, fullText, fullReasoning in
                    guard let event = AnthropicMessagesStreamParser.event(
                        from: root,
                        fullText: &fullText,
                        fullReasoning: &fullReasoning
                    ) else {
                        return []
                    }
                    return [event]
                }
            )
        )
    }

    private func openCodeGoSSEOptions(
        usageFromRoot: @escaping ([String: Any]) -> ProviderUsage?,
        eventsFromRoot: @escaping ([String: Any], inout String, inout String) -> [ProviderStreamEvent]
    ) -> ProviderSSEStreamRunner.Options {
        ProviderSSEStreamRunner.Options(
            usageFromRoot: usageFromRoot,
            eventsFromRoot: eventsFromRoot,
            streamEndReasoningSummary: { $0.trimmedNonEmpty },
            mergeInlineCompleted: { response, latestUsage in
                ProviderResponse(
                    text: response.text,
                    reasoningSummary: response.reasoningSummary?.trimmedNonEmpty,
                    raw: response.raw,
                    usage: response.usage ?? latestUsage
                )
            }
        )
    }

    private func parseMessagesStreamUsage(_ root: [String: Any]) -> ProviderUsage? {
        if let usage = parseUsage(root["usage"] as? [String: Any]) {
            return usage
        }
        if let message = root["message"] as? [String: Any],
           let usage = parseUsage(message["usage"] as? [String: Any]) {
            return usage
        }
        return nil
    }

    private func extractText(from rawContent: Any?) -> [String] {
        guard let blocks = rawContent as? [[String: Any]] else { return [] }
        return blocks.compactMap { block in
            guard (block["type"] as? String)?.lowercased() == "text" else { return nil }
            return (block["text"] as? String)?.trimmedNonEmpty
        }
    }

    private func extractToolCalls(from rawContent: Any?) -> [ToolCall] {
        guard let blocks = rawContent as? [[String: Any]] else { return [] }
        return blocks.compactMap { block in
            guard (block["type"] as? String)?.lowercased() == "tool_use",
                  let id = (block["id"] as? String)?.trimmedNonEmpty,
                  let name = (block["name"] as? String)?.trimmedNonEmpty else { return nil }
            let argumentsJSON: String
            if let input = block["input"], JSONSerialization.isValidJSONObject(input),
               let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]),
               let encoded = String(data: data, encoding: .utf8) {
                argumentsJSON = encoded
            } else {
                argumentsJSON = "{}"
            }
            return ToolCall(id: id, name: name, argumentsJSON: argumentsJSON, providerMetadata: nil)
        }
    }

    private func parseUsage(_ object: [String: Any]?) -> ProviderUsage? {
        OpenAICompatibleUsageParser.parse(object)
    }

    private func openAIToolPayload(_ tool: ProviderTool) throws -> [String: AnyEncodable] {
        guard tool.type == "function" else {
            return ["type": AnyEncodable(tool.type), "payload": AnyEncodable(tool.payload)]
        }
        guard let name = tool.payload["name"]?.trimmedNonEmpty,
              let parametersJSON = tool.payload["parameters"]?.trimmedNonEmpty,
              let data = parametersJSON.data(using: .utf8),
              let parameters = try? JSONDecoder().decode(JSONValue.self, from: data)
        else {
            throw ProviderClientError.parseFailure(
                "Invalid OpenCode Go function definition: \(tool.payload["name"] ?? "unnamed")"
            )
        }
        var function: [String: AnyEncodable] = [
            "name": AnyEncodable(name),
            "parameters": AnyEncodable(parameters)
        ]
        if let description = tool.payload["description"]?.trimmedNonEmpty {
            function["description"] = AnyEncodable(description)
        }
        return ["type": AnyEncodable("function"), "function": AnyEncodable(function)]
    }

    private func parseToolCalls(_ rawValue: Any?) -> [ToolCall] {
        guard let values = rawValue as? [[String: Any]] else { return [] }
        return values.enumerated().compactMap { index, value in
            guard let function = value["function"] as? [String: Any],
                  let name = (function["name"] as? String)?.trimmedNonEmpty else { return nil }
            return ToolCall(
                id: (value["id"] as? String)?.trimmedNonEmpty ?? "tool-call-\(index)",
                name: name,
                argumentsJSON: (function["arguments"] as? String)?.trimmedNonEmpty ?? "{}",
                providerMetadata: nil
            )
        }
    }

}
