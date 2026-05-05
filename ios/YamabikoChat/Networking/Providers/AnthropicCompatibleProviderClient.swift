import Foundation

struct AnthropicCompatibleProviderClient: ProviderClient {
    let provider: LLMProvider = .alibabaCodingPlan

    private static let anthropicVersion = "2023-06-01"
    private static let mcpBetaHeader = "mcp-client-2025-11-20"
    private static let defaultMaxTokens = 4096
    private static let minimumThinkingBudgetTokens = 1024

    private struct AnthropicTextContentBlock: Encodable {
        var type: String = "text"
        var text: String
    }

    private struct AnthropicMessage: Encodable {
        var role: String
        var content: [AnthropicTextContentBlock]
    }

    private struct AnthropicThinking: Encodable {
        var type: String = "enabled"
        var budgetTokens: Int

        enum CodingKeys: String, CodingKey {
            case type
            case budgetTokens = "budget_tokens"
        }
    }

    private struct AnthropicMCPServer: Encodable {
        var type: String = "url"
        var url: String
        var name: String
        var authorizationToken: String?

        enum CodingKeys: String, CodingKey {
            case type
            case url
            case name
            case authorizationToken = "authorization_token"
        }
    }

    private struct AnthropicMCPToolConfiguration: Encodable {
        var enabled: Bool?

        enum CodingKeys: String, CodingKey {
            case enabled
        }
    }

    private struct AnthropicMCPToolset: Encodable {
        var type: String = "mcp_toolset"
        var mcpServerName: String
        var defaultConfig: AnthropicMCPToolConfiguration?
        var configs: [String: AnthropicMCPToolConfiguration]?

        enum CodingKeys: String, CodingKey {
            case type
            case mcpServerName = "mcp_server_name"
            case defaultConfig = "default_config"
            case configs
        }
    }

    private struct AnthropicMCPConfiguration {
        var servers: [AnthropicMCPServer]
        var toolsets: [AnthropicMCPToolset]
    }

    private struct AnthropicRequestBody: Encodable {
        var model: String
        var messages: [AnthropicMessage]
        var system: String?
        var maxTokens: Int
        var stream: Bool
        var thinking: AnthropicThinking?
        var mcpServers: [AnthropicMCPServer]?
        var tools: [AnthropicMCPToolset]?

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case system
            case maxTokens = "max_tokens"
            case stream
            case thinking
            case mcpServers = "mcp_servers"
            case tools
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(model, forKey: .model)
            try container.encode(messages, forKey: .messages)
            try container.encodeIfPresent(system, forKey: .system)
            try container.encode(maxTokens, forKey: .maxTokens)
            try container.encode(stream, forKey: .stream)
            try container.encodeIfPresent(thinking, forKey: .thinking)
            try container.encodeIfPresent(mcpServers, forKey: .mcpServers)
            try container.encodeIfPresent(tools, forKey: .tools)
        }
    }

    func generate(
        request: ProviderRequest,
        settings: AppSettings,
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol
    ) async throws -> ProviderResponse {
        try ensureAlibabaCodingPlan(request: request, settings: settings)
        let apiKey = try resolvedCredential(credentialStore: credentialStore)
        let endpoint = try endpointURL()
        let mcpConfiguration = try buildMCPConfiguration(for: request, credentialStore: credentialStore)
        let payload = try buildPayload(for: request, stream: false, mcpConfiguration: mcpConfiguration)

        let httpRequest = HTTPRequest(
            url: endpoint,
            headers: headers(token: apiKey, streaming: false, includesMCP: mcpConfiguration != nil),
            body: payload
        )

        let (data, response) = try await httpClient.send(httpRequest)
        guard (200 ... 299).contains(response.statusCode) else {
            throw ProviderClientError.httpStatus(response.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        return try parseResponse(data: data)
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
                    try ensureAlibabaCodingPlan(request: request, settings: settings)
                    let apiKey = try resolvedCredential(credentialStore: credentialStore)
                    let endpoint = try endpointURL()
                    let mcpConfiguration = try buildMCPConfiguration(for: request, credentialStore: credentialStore)
                    let payload = try buildPayload(for: request, stream: true, mcpConfiguration: mcpConfiguration)

                    let httpRequest = HTTPRequest(
                        url: endpoint,
                        headers: headers(token: apiKey, streaming: true, includesMCP: mcpConfiguration != nil),
                        body: payload
                    )

                    let (lineStream, response) = try await httpClient.stream(httpRequest)
                    guard (200 ... 299).contains(response.statusCode) else {
                        throw ProviderClientError.httpStatus(response.statusCode, "Streaming endpoint returned \(response.statusCode)")
                    }

                    var fullText = ""
                    var fullReasoning = ""
                    var latestUsage: ProviderUsage?

                    for try await line in lineStream {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty || !trimmed.hasPrefix("data:") {
                            continue
                        }

                        let dataChunk = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if dataChunk == "[DONE]" {
                            let final = ProviderResponse(
                                text: fullText,
                                reasoningSummary: optionalNonEmpty(fullReasoning),
                                raw: nil,
                                usage: latestUsage
                            )
                            continuation.yield(.completed(final))
                            continuation.finish()
                            return
                        }

                        guard let root = try? JSONSerialization.jsonObject(with: Data(dataChunk.utf8)) as? [String: Any] else {
                            continue
                        }

                        if let usage = parseStreamUsage(root)?.normalizedNonEmpty() {
                            latestUsage = mergeUsage(current: latestUsage, incoming: usage)
                        }

                        if let event = parseStreamChunk(
                            root,
                            fullText: &fullText,
                            fullReasoning: &fullReasoning,
                            latestUsage: latestUsage
                        ) {
                            if case let .completed(response) = event {
                                continuation.yield(.completed(response))
                                continuation.finish()
                                return
                            }
                            continuation.yield(event)
                        }
                    }

                    let final = ProviderResponse(
                        text: fullText,
                        reasoningSummary: optionalNonEmpty(fullReasoning),
                        raw: nil,
                        usage: latestUsage
                    )
                    continuation.yield(.completed(final))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func ensureAlibabaCodingPlan(request: ProviderRequest, settings: AppSettings) throws {
        let resolvedProvider = LLMProvider(rawOrDefault: request.metadata["provider"] ?? settings.apiProvider)
        guard resolvedProvider == .alibabaCodingPlan else {
            throw ProviderClientError.invalidBaseURL("Provider not supported by Anthropic compatible client")
        }
    }

    private func resolvedCredential(credentialStore: SecureCredentialStore) throws -> String {
        guard let apiKey = try credentialStore.credential(for: .alibabaCodingPlan), !apiKey.isEmpty else {
            throw ProviderClientError.missingCredential(LLMProvider.alibabaCodingPlan.rawValue)
        }
        return apiKey
    }

    private func endpointURL() throws -> URL {
        let baseURL = AppConstants.defaultAlibabaCodingPlanBaseURL.absoluteString
        guard let url = URL(string: baseURL)?.appendingPathComponent("v1/messages") else {
            throw ProviderClientError.invalidBaseURL(baseURL)
        }
        return url
    }

    private func headers(token: String, streaming: Bool, includesMCP: Bool) -> [String: String] {
        var headers = [
            "Content-Type": "application/json",
            "x-api-key": token,
            "anthropic-version": Self.anthropicVersion
        ]
        if includesMCP {
            headers["anthropic-beta"] = Self.mcpBetaHeader
        }
        if streaming {
            headers["Accept"] = "text/event-stream"
        }
        return headers
    }

    private func buildPayload(
        for request: ProviderRequest,
        stream: Bool,
        mcpConfiguration: AnthropicMCPConfiguration?
    ) throws -> Data {
        let thinking = buildThinking(request.thinking)
        let maxTokens = max(Self.defaultMaxTokens, (thinking?.budgetTokens ?? 0) + 1024)
        let body = AnthropicRequestBody(
            model: request.model.trimmingCharacters(in: .whitespacesAndNewlines),
            messages: mapMessages(request.messages),
            system: optionalNonEmpty(request.systemPrompt),
            maxTokens: maxTokens,
            stream: stream,
            thinking: thinking,
            mcpServers: mcpConfiguration?.servers,
            tools: mcpConfiguration?.toolsets
        )
        return try JSONEncoder().encode(body)
    }

    private func buildMCPConfiguration(
        for request: ProviderRequest,
        credentialStore: SecureCredentialStore
    ) throws -> AnthropicMCPConfiguration? {
        guard let tool = request.tools.first(where: { $0.type == "mcp_toolset" }) else {
            return nil
        }

        let rawURL = tool.payload["server_url"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !rawURL.isEmpty,
              let components = URLComponents(string: rawURL),
              let scheme = components.scheme?.lowercased(),
              scheme == "https",
              let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              let normalizedURL = components.url?.absoluteString
        else {
            throw ProviderClientError.invalidBaseURL(rawURL)
        }

        let serverName = tool.payload["server_name"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .ifBlank(AppConstants.alibabaMCPDefaultServerName) ?? AppConstants.alibabaMCPDefaultServerName
        let authorizationToken = try credentialStore.readSecret(key: AppConstants.alibabaMCPAuthorizationTokenKey)?.trimmedNonEmpty
        let allowedTools = parseAllowedTools(tool.payload["allowed_tools"])
        let server = AnthropicMCPServer(
            url: normalizedURL,
            name: serverName,
            authorizationToken: authorizationToken
        )

        let toolset: AnthropicMCPToolset
        if allowedTools.isEmpty {
            toolset = AnthropicMCPToolset(
                mcpServerName: serverName,
                defaultConfig: nil,
                configs: nil
            )
        } else {
            let configs = allowedTools.reduce(into: [String: AnthropicMCPToolConfiguration]()) { result, toolName in
                result[toolName] = AnthropicMCPToolConfiguration(enabled: true)
            }
            toolset = AnthropicMCPToolset(
                mcpServerName: serverName,
                defaultConfig: AnthropicMCPToolConfiguration(enabled: false),
                configs: configs
            )
        }

        return AnthropicMCPConfiguration(
            servers: [server],
            toolsets: [toolset]
        )
    }

    private func buildThinking(_ thinking: ProviderThinkingConfig?) -> AnthropicThinking? {
        guard thinking?.enabled == true else { return nil }
        guard let budget = thinking?.budget, budget >= Self.minimumThinkingBudgetTokens else {
            return nil
        }
        return AnthropicThinking(budgetTokens: budget)
    }

    private func mapMessages(_ messages: [ProviderRequestMessage]) -> [AnthropicMessage] {
        messages.map { message in
            var content = message.content
            if !message.attachments.isEmpty {
                let attachmentText = message.attachments.map { "- \($0)" }.joined(separator: "\n")
                content += "\n\nAttachments:\n\(attachmentText)"
            }
            let normalizedRole = normalizeRole(message.role)
            return AnthropicMessage(
                role: normalizedRole,
                content: [AnthropicTextContentBlock(text: content)]
            )
        }
    }

    private func normalizeRole(_ value: String) -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "assistant":
            return "assistant"
        default:
            return "user"
        }
    }

    private func parseResponse(data: Data) throws -> ProviderResponse {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderClientError.parseFailure("Anthropic response root is not dictionary")
        }

        let text = extractText(from: root["content"]).joined()
        let reasoning = extractReasoning(from: root["content"]).joined()
        let usage = parseUsage(root["usage"] as? [String: Any])
        if text.isEmpty && reasoning.isEmpty {
            throw ProviderClientError.parseFailure("Anthropic response does not contain text content")
        }

        return ProviderResponse(
            text: text,
            reasoningSummary: optionalNonEmpty(reasoning),
            raw: String(data: data, encoding: .utf8),
            usage: usage
        )
    }

    private func parseStreamChunk(
        _ root: [String: Any],
        fullText: inout String,
        fullReasoning: inout String,
        latestUsage: ProviderUsage?
    ) -> ProviderStreamEvent? {
        let type = (root["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch type {
        case "content_block_start":
            guard let block = root["content_block"] as? [String: Any],
                  (block["type"] as? String)?.lowercased() == "mcp_tool_use" else {
                return nil
            }
            let name = (block["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .toolCallDelta(name?.ifBlank("mcp_tool_use") ?? "mcp_tool_use")
        case "content_block_delta":
            guard let delta = root["delta"] as? [String: Any] else { return nil }
            let deltaType = (delta["type"] as? String)?.lowercased()
            switch deltaType {
            case "text_delta":
                guard let text = delta["text"] as? String, !text.isEmpty else { return nil }
                fullText += text
                return .textDelta(text)
            case "thinking_delta":
                guard let thinking = delta["thinking"] as? String, !thinking.isEmpty else { return nil }
                fullReasoning += thinking
                return .reasoningDelta(thinking)
            default:
                return nil
            }
        case "message_stop":
            return .completed(
                ProviderResponse(
                    text: fullText,
                    reasoningSummary: optionalNonEmpty(fullReasoning),
                    raw: nil,
                    usage: latestUsage
                )
            )
        default:
            return nil
        }
    }

    private func parseStreamUsage(_ root: [String: Any]) -> ProviderUsage? {
        if let usage = parseUsage(root["usage"] as? [String: Any]) {
            return usage
        }
        if let message = root["message"] as? [String: Any], let usage = parseUsage(message["usage"] as? [String: Any]) {
            return usage
        }
        return nil
    }

    private func parseUsage(_ object: [String: Any]?) -> ProviderUsage? {
        guard let object else { return nil }
        let inputTokens = intValue(in: object, keys: ["input_tokens", "prompt_tokens", "inputTokens", "promptTokens"])
        let outputTokens = intValue(in: object, keys: ["output_tokens", "completion_tokens", "outputTokens", "completionTokens"])
        let totalTokens = intValue(in: object, keys: ["total_tokens", "totalTokens"])
        let reasoningTokens =
            intValue(in: object, keys: ["reasoning_tokens", "reasoningTokens", "reasoning_token_count", "reasoningTokenCount"])
        let cachedTokens =
            intValue(in: object, keys: ["cache_read_input_tokens", "cached_input_tokens", "cacheReadInputTokens", "cachedInputTokens"])
        let cacheCreationTokens =
            intValue(in: object, keys: ["cache_creation_input_tokens", "cacheCreationInputTokens", "cache_creation_input_token_count"])

        return ProviderUsage(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            reasoningTokens: reasoningTokens,
            cachedInputTokens: cachedTokens,
            cacheCreationInputTokens: cacheCreationTokens
        )
        .normalizedNonEmpty()
    }

    private func mergeUsage(current: ProviderUsage?, incoming: ProviderUsage) -> ProviderUsage {
        ProviderUsage(
            inputTokens: incoming.inputTokens ?? current?.inputTokens,
            outputTokens: incoming.outputTokens ?? current?.outputTokens,
            totalTokens: incoming.totalTokens ?? current?.totalTokens,
            reasoningTokens: incoming.reasoningTokens ?? current?.reasoningTokens,
            cachedInputTokens: incoming.cachedInputTokens ?? current?.cachedInputTokens,
            cacheCreationInputTokens: incoming.cacheCreationInputTokens ?? current?.cacheCreationInputTokens
        )
        .normalized()
    }

    private func extractText(from rawContent: Any?) -> [String] {
        guard let blocks = rawContent as? [[String: Any]] else { return [] }
        return blocks.compactMap { block in
            guard (block["type"] as? String)?.lowercased() == "text" else { return nil }
            let text = (block["text"] as? String)?.trimmingCharacters(in: .newlines)
            return text?.isEmpty == false ? text : nil
        }
    }

    private func extractReasoning(from rawContent: Any?) -> [String] {
        guard let blocks = rawContent as? [[String: Any]] else { return [] }
        return blocks.compactMap { block in
            guard (block["type"] as? String)?.lowercased() == "thinking" else { return nil }
            let text = (block["thinking"] as? String)?.trimmingCharacters(in: .newlines)
            return text?.isEmpty == false ? text : nil
        }
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
        if let value = raw as? Int {
            return value
        }
        if let value = raw as? NSNumber {
            return value.intValue
        }
        if let value = raw as? String {
            return Int(value)
        }
        return nil
    }

    private func optionalNonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return value
    }

    private func parseAllowedTools(_ raw: String?) -> [String] {
        guard let raw else { return [] }
        var result: [String] = []
        for value in raw.split(whereSeparator: \.isNewline).flatMap({ $0.split(separator: ",") }) {
            let normalized = String(value).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { continue }
            if !result.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) {
                result.append(normalized)
            }
        }
        return result
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func ifBlank(_ fallback: String) -> String {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? fallback : value
    }
}
