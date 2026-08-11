import CryptoKit
import Foundation

struct OpenCodeGoProviderClient: ProviderClient {
    let provider: LLMProvider = .openCodeGo

    private static let anthropicVersion = "2023-06-01"
    private static let defaultMaxTokens = 4096

    private struct ChatMessage: Encodable {
        var role: String
        var content: ProviderAttachmentEncoder.OpenAIMessageContent
        var reasoningContent: String?

        enum CodingKeys: String, CodingKey {
            case role
            case content
            case reasoningContent = "reasoning_content"
        }
    }

    private struct ChatStreamOptions: Encodable {
        var includeUsage: Bool = true

        enum CodingKeys: String, CodingKey {
            case includeUsage = "include_usage"
        }
    }

    private struct ChatRequestBody: Encodable {
        var model: String
        var messages: [ChatMessage]
        var stream: Bool
        var maxTokens: Int?
        var temperature: Double?
        var promptCacheKey: String?
        var streamOptions: ChatStreamOptions?

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case stream
            case maxTokens = "max_tokens"
            case temperature
            case promptCacheKey = "prompt_cache_key"
            case streamOptions = "stream_options"
        }
    }

    private struct MessageRequestMessage: Encodable {
        var role: String
        var content: [ProviderAttachmentEncoder.AnthropicContentBlock]
    }

    private struct MessageRequestBody: Encodable {
        var model: String
        var messages: [MessageRequestMessage]
        var system: String?
        var maxTokens: Int
        var stream: Bool

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case system
            case maxTokens = "max_tokens"
            case stream
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
            messages: mapChatMessages(
                request.messages,
                systemPrompt: request.systemPrompt,
                embedImages: ProviderAttachmentEncoder.shouldEmbedImages(metadata: request.metadata)
            ),
            stream: stream,
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
            messages: mapMessages(
                request.messages,
                embedImages: ProviderAttachmentEncoder.shouldEmbedImages(metadata: request.metadata)
            ),
            system: request.systemPrompt?.trimmedNonEmpty,
            maxTokens: positiveIntMetadata("max_output_tokens", from: request) ?? Self.defaultMaxTokens,
            stream: stream
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

    private func mapChatMessages(
        _ messages: [ProviderRequestMessage],
        systemPrompt: String?,
        embedImages: Bool
    ) -> [ChatMessage] {
        var mapped: [ChatMessage] = []
        if let systemPrompt = systemPrompt?.trimmedNonEmpty {
            mapped.append(
                ChatMessage(
                    role: "system",
                    content: .plain(systemPrompt),
                    reasoningContent: nil
                )
            )
        }
        for message in messages {
            let role = normalizeChatRole(message.role)
            ProviderAttachmentEncoder.logSkippedAttachmentsIfNeeded(
                message.attachments,
                providerLabel: "OpenCode Go chat",
                embedImages: embedImages
            )
            mapped.append(
                ChatMessage(
                    role: role,
                    content: ProviderAttachmentEncoder.buildOpenAIMessageContent(
                        text: message.content,
                        attachments: message.attachments,
                        embedImages: embedImages
                    ),
                    reasoningContent: role == "assistant" ? message.reasoningContent?.trimmedNonEmpty : nil
                )
            )
        }
        return mapped
    }

    private func mapMessages(_ messages: [ProviderRequestMessage], embedImages: Bool) -> [MessageRequestMessage] {
        messages.map { message in
            ProviderAttachmentEncoder.logSkippedAttachmentsIfNeeded(
                message.attachments,
                providerLabel: "OpenCode Go messages",
                embedImages: embedImages
            )
            return MessageRequestMessage(
                role: normalizeMessagesRole(message.role),
                content: ProviderAttachmentEncoder.buildAnthropicContentBlocks(
                    text: message.content,
                    attachments: message.attachments,
                    embedImages: embedImages
                )
            )
        }
    }

    private func normalizeChatRole(_ raw: String) -> String {
        let role = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["system", "assistant", "user"].contains(role) ? role : "user"
    }

    private func normalizeMessagesRole(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "assistant" ? "assistant" : "user"
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
            usage: parseUsage(root["usage"] as? [String: Any])
        )
    }

    private func parseMessagesResponse(data: Data) throws -> ProviderResponse {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderClientError.parseFailure("OpenCode Go messages response root is not dictionary")
        }
        let text = extractText(from: root["content"]).joined()
        if text.isEmpty {
            throw ProviderClientError.parseFailure("OpenCode Go messages response does not contain text content")
        }
        return ProviderResponse(
            text: text,
            reasoningSummary: nil,
            raw: String(data: data, encoding: .utf8),
            usage: parseUsage(root["usage"] as? [String: Any])
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

    private func parseUsage(_ object: [String: Any]?) -> ProviderUsage? {
        guard let object else { return nil }
        let promptDetails = object["prompt_tokens_details"] as? [String: Any]
        let inputDetails = object["input_tokens_details"] as? [String: Any]
        return ProviderUsage(
            inputTokens: intValue(in: object, keys: ["prompt_tokens", "input_tokens", "inputTokens"]),
            outputTokens: intValue(in: object, keys: ["completion_tokens", "output_tokens", "outputTokens"]),
            totalTokens: intValue(in: object, keys: ["total_tokens", "totalTokens"]),
            reasoningTokens: intValue(in: object, keys: ["reasoning_tokens", "reasoningTokens"]),
            cachedInputTokens: intValue(in: promptDetails, keys: ["cached_tokens", "cachedTokens", "cached_input_tokens"]) ??
                intValue(in: inputDetails, keys: ["cached_tokens", "cachedTokens", "cached_input_tokens"]) ??
                intValue(in: object, keys: ["cache_read_input_tokens", "cached_input_tokens", "cachedInputTokens"]),
            cacheCreationInputTokens: intValue(in: inputDetails, keys: ["cache_write_tokens", "cacheWriteTokens", "cache_creation_input_tokens", "cacheCreationInputTokens"]) ??
                intValue(in: object, keys: ["cache_write_tokens", "cacheWriteTokens", "cache_creation_input_tokens", "cacheCreationInputTokens"])
        )
        .normalizedNonEmpty()
    }

    private func intValue(in object: [String: Any]?, keys: [String]) -> Int? {
        guard let object else { return nil }
        for key in keys {
            if let value = intValue(object[key]) {
                return value
            }
        }
        return nil
    }

    private func intValue(_ raw: Any?) -> Int? {
        if let value = raw as? Int { return value }
        if let value = raw as? NSNumber { return value.intValue }
        if let value = raw as? String { return Int(value) }
        return nil
    }
}
