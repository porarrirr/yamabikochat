import CryptoKit
import Foundation

struct OpenCodeGoProviderClient: ProviderClient {
    let provider: LLMProvider = .openCodeGo

    private static let anthropicVersion = "2023-06-01"
    private static let defaultMaxTokens = 4096

    private struct ChatMessage: Encodable {
        var role: String
        var content: String
    }

    private struct ChatRequestBody: Encodable {
        var model: String
        var messages: [ChatMessage]
        var stream: Bool
        var promptCacheKey: String?

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case stream
            case promptCacheKey = "prompt_cache_key"
        }
    }

    private struct MessageTextContentBlock: Encodable {
        var type: String = "text"
        var text: String
    }

    private struct MessageRequestMessage: Encodable {
        var role: String
        var content: [MessageTextContentBlock]
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
            messages: mapChatMessages(request.messages, systemPrompt: request.systemPrompt),
            stream: stream,
            promptCacheKey: promptCacheKey(for: request, route: route)
        )
        return HTTPRequest(
            url: endpoint,
            headers: [
                "Authorization": "Bearer \(apiKey)",
                "Content-Type": "application/json"
            ],
            body: try JSONEncoder().encode(body)
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
            messages: mapMessages(request.messages),
            system: request.systemPrompt?.trimmedNonEmpty,
            maxTokens: Self.defaultMaxTokens,
            stream: stream
        )
        return HTTPRequest(
            url: endpoint,
            headers: [
                "Content-Type": "application/json",
                "x-api-key": apiKey,
                "anthropic-version": Self.anthropicVersion
            ],
            body: try JSONEncoder().encode(body)
        )
    }

    private func mapChatMessages(_ messages: [ProviderRequestMessage], systemPrompt: String?) -> [ChatMessage] {
        var mapped: [ChatMessage] = []
        if let systemPrompt = systemPrompt?.trimmedNonEmpty {
            mapped.append(ChatMessage(role: "system", content: systemPrompt))
        }
        for message in messages {
            mapped.append(ChatMessage(role: normalizeChatRole(message.role), content: textWithAttachments(message)))
        }
        return mapped
    }

    private func mapMessages(_ messages: [ProviderRequestMessage]) -> [MessageRequestMessage] {
        messages.map {
            MessageRequestMessage(
                role: normalizeMessagesRole($0.role),
                content: [MessageTextContentBlock(text: textWithAttachments($0))]
            )
        }
    }

    private func textWithAttachments(_ message: ProviderRequestMessage) -> String {
        var content = message.content
        if !message.attachments.isEmpty {
            content += "\n\nAttachments:\n" + message.attachments.map { "- \($0)" }.joined(separator: "\n")
        }
        return content
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

    private func parseChatResponse(data: Data) throws -> ProviderResponse {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any] else {
            throw ProviderClientError.parseFailure("OpenCode Go chat response is missing choices[0].message")
        }
        let content = openAICompatibleText(from: message["content"])
        let reasoning = reasoningText(from: message)
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
        var fullText = ""
        var fullReasoning = ""
        var latestUsage: ProviderUsage?
        for try await dataChunk in SSEPayloadAssembly.payloads(from: lineStream) {
            if dataChunk == "[DONE]" {
                continuation.yield(
                    .completed(
                        ProviderResponse(
                            text: fullText,
                            reasoningSummary: fullReasoning.trimmedNonEmpty,
                            raw: nil,
                            usage: latestUsage
                        )
                    )
                )
                continuation.finish()
                return
            }
            guard let root = try? JSONSerialization.jsonObject(with: Data(dataChunk.utf8)) as? [String: Any] else { continue }
            if let usage = parseUsage(root["usage"] as? [String: Any]) {
                latestUsage = usage
            }
            guard let choices = root["choices"] as? [[String: Any]], let choice = choices.first else { continue }

            if let delta = choice["delta"] as? [String: Any] {
                if let incoming = reasoningText(from: delta) {
                    let reasoningDelta = StreamDeltaAccumulator.incrementalDelta(buffer: fullReasoning, incoming: incoming)
                    if !reasoningDelta.isEmpty {
                        fullReasoning += reasoningDelta
                        continuation.yield(.reasoningDelta(reasoningDelta))
                    }
                }

                let incomingContent = openAICompatibleText(from: delta["content"])
                if !incomingContent.isEmpty {
                    let textDelta = StreamDeltaAccumulator.incrementalDelta(buffer: fullText, incoming: incomingContent)
                    if !textDelta.isEmpty {
                        fullText += textDelta
                        continuation.yield(.textDelta(textDelta))
                    }
                }
            }

            if let message = choice["message"] as? [String: Any] {
                if let incoming = reasoningText(from: message) {
                    let reasoningDelta = StreamDeltaAccumulator.incrementalDelta(buffer: fullReasoning, incoming: incoming)
                    if !reasoningDelta.isEmpty {
                        fullReasoning += reasoningDelta
                        continuation.yield(.reasoningDelta(reasoningDelta))
                    }
                }

                let incomingContent = openAICompatibleText(from: message["content"])
                if !incomingContent.isEmpty {
                    let textDelta = StreamDeltaAccumulator.incrementalDelta(buffer: fullText, incoming: incomingContent)
                    if !textDelta.isEmpty {
                        fullText += textDelta
                        continuation.yield(.textDelta(textDelta))
                    }
                }
            }
        }
        continuation.yield(
            .completed(
                ProviderResponse(
                    text: fullText,
                    reasoningSummary: fullReasoning.trimmedNonEmpty,
                    raw: nil,
                    usage: latestUsage
                )
            )
        )
        continuation.finish()
    }

    private func streamMessages(
        _ lineStream: AsyncThrowingStream<String, Error>,
        continuation: AsyncThrowingStream<ProviderStreamEvent, Error>.Continuation
    ) async throws {
        var fullText = ""
        var latestUsage: ProviderUsage?
        for try await dataChunk in SSEPayloadAssembly.payloads(from: lineStream) {
            if dataChunk == "[DONE]" {
                continuation.yield(.completed(ProviderResponse(text: fullText, reasoningSummary: nil, raw: nil, usage: latestUsage)))
                continuation.finish()
                return
            }
            guard let root = try? JSONSerialization.jsonObject(with: Data(dataChunk.utf8)) as? [String: Any] else { continue }
            if let usage = parseUsage(root["usage"] as? [String: Any]) {
                latestUsage = usage
            }
            if let message = root["message"] as? [String: Any],
               let usage = parseUsage(message["usage"] as? [String: Any]) {
                latestUsage = usage
            }
            if let delta = root["delta"] as? [String: Any],
               (delta["type"] as? String)?.lowercased() == "text_delta",
               let incoming = delta["text"] as? String,
               !incoming.isEmpty {
                let textDelta = StreamDeltaAccumulator.incrementalDelta(buffer: fullText, incoming: incoming)
                if !textDelta.isEmpty {
                    fullText += textDelta
                    continuation.yield(.textDelta(textDelta))
                }
            }
            if (root["type"] as? String)?.lowercased() == "message_stop" {
                continuation.yield(.completed(ProviderResponse(text: fullText, reasoningSummary: nil, raw: nil, usage: latestUsage)))
                continuation.finish()
                return
            }
        }
        continuation.yield(.completed(ProviderResponse(text: fullText, reasoningSummary: nil, raw: nil, usage: latestUsage)))
        continuation.finish()
    }

    private func extractText(from rawContent: Any?) -> [String] {
        guard let blocks = rawContent as? [[String: Any]] else { return [] }
        return blocks.compactMap { block in
            guard (block["type"] as? String)?.lowercased() == "text" else { return nil }
            return (block["text"] as? String)?.trimmedNonEmpty
        }
    }

    private func openAICompatibleText(from value: Any?) -> String {
        guard let value else { return "" }
        if let text = value as? String {
            return text
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        guard let parts = value as? [Any] else { return "" }
        return parts.compactMap { part -> String? in
            if let text = part as? String {
                return text
            }
            guard let block = part as? [String: Any] else { return nil }
            let type = (block["type"] as? String)?.lowercased()
            if let type, !["input_text", "output_text", "text"].contains(type) {
                return nil
            }
            return block["text"] as? String
        }
        .joined()
    }

    private func reasoningText(from object: [String: Any]) -> String? {
        for key in ["reasoning_content", "reasoning", "thinking"] {
            let incoming = openAICompatibleText(from: object[key])
            if let trimmed = incoming.trimmedNonEmpty {
                return trimmed
            }
        }
        return nil
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
            cacheCreationInputTokens: intValue(in: inputDetails, keys: ["cache_creation_input_tokens", "cacheCreationInputTokens"]) ??
                intValue(in: object, keys: ["cache_creation_input_tokens", "cacheCreationInputTokens"])
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

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
