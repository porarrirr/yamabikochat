import Foundation

struct OpenAICompatibleProviderClient: ProviderClient {
    let provider: LLMProvider = .openAI

    private struct OpenAIMessage: Encodable {
        var role: String
        var content: String
    }

    private struct OpenAIRequestBody: Encodable {
        var model: String
        var messages: [OpenAIMessage]
        var stream: Bool
        var tools: [[String: AnyEncodable]]?
        var provider: [String: AnyEncodable]?
        var reasoning: [String: AnyEncodable]?

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case stream
            case tools
            case provider
            case reasoning
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(model, forKey: .model)
            try container.encode(messages, forKey: .messages)
            try container.encode(stream, forKey: .stream)
            try container.encodeIfPresent(tools, forKey: .tools)
            try container.encodeIfPresent(provider, forKey: .provider)
            try container.encodeIfPresent(reasoning, forKey: .reasoning)
        }
    }

    func generate(
        request: ProviderRequest,
        settings: AppSettings,
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol
    ) async throws -> ProviderResponse {
        let resolvedProvider = LLMProvider(rawOrDefault: request.metadata["provider"] ?? settings.apiProvider)
        let apiKey = try resolvedCredential(
            for: resolvedProvider,
            settings: settings,
            credentialStore: credentialStore
        )
        let endpoint = try endpointURL(for: resolvedProvider, settings: settings, credentialStore: credentialStore)
        let payload = try buildPayload(for: request, stream: false, provider: resolvedProvider)

        let httpRequest = HTTPRequest(
            url: endpoint,
            headers: headers(for: resolvedProvider, token: apiKey),
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
                    let resolvedProvider = LLMProvider(rawOrDefault: request.metadata["provider"] ?? settings.apiProvider)
                    let apiKey = try resolvedCredential(
                        for: resolvedProvider,
                        settings: settings,
                        credentialStore: credentialStore
                    )
                    let endpoint = try endpointURL(for: resolvedProvider, settings: settings, credentialStore: credentialStore)
                    let payload = try buildPayload(for: request, stream: true, provider: resolvedProvider)

                    let httpRequest = HTTPRequest(
                        url: endpoint,
                        headers: headers(for: resolvedProvider, token: apiKey),
                        body: payload
                    )

                    let (lineStream, response) = try await httpClient.stream(httpRequest)
                    guard (200 ... 299).contains(response.statusCode) else {
                        throw ProviderClientError.httpStatus(response.statusCode, "Streaming endpoint returned \(response.statusCode)")
                    }

                    var fullText = ""
                    var latestUsage: ProviderUsage?
                    for try await line in lineStream {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty || !trimmed.hasPrefix("data:") { continue }

                        let dataChunk = String(trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces))
                        if dataChunk == "[DONE]" {
                            let final = ProviderResponse(text: fullText, reasoningSummary: nil, raw: nil, usage: latestUsage)
                            continuation.yield(.completed(final))
                            continuation.finish()
                            return
                        }

                        if let root = try? JSONSerialization.jsonObject(with: Data(dataChunk.utf8)) as? [String: Any] {
                            if let usage = parseUsage(root["usage"] as? [String: Any])?.normalizedNonEmpty() {
                                latestUsage = usage
                            } else if let usage = parseUsage(root)?.normalizedNonEmpty() {
                                latestUsage = usage
                            }
                        }

                        if let event = parseStreamChunk(dataChunk, fullText: &fullText) {
                            if case let .completed(response) = event {
                                let merged = ProviderResponse(
                                    text: response.text,
                                    reasoningSummary: response.reasoningSummary,
                                    raw: response.raw,
                                    usage: response.usage ?? latestUsage
                                )
                                continuation.yield(.completed(merged))
                                continuation.finish()
                                return
                            }
                            continuation.yield(event)
                        }
                    }

                    let final = ProviderResponse(text: fullText, reasoningSummary: nil, raw: nil, usage: latestUsage)
                    continuation.yield(.completed(final))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func buildPayload(for request: ProviderRequest, stream: Bool, provider: LLMProvider) throws -> Data {
        let toolsPayload = request.tools.isEmpty ? nil : request.tools.map { tool in
            [
                "type": AnyEncodable(tool.type),
                "payload": AnyEncodable(tool.payload)
            ]
        }

        let providerPayload: [String: AnyEncodable]? = {
            guard provider == .openRouter, let config = request.provider else { return nil }
            var map: [String: AnyEncodable] = [:]
            if let order = config.order, !order.isEmpty { map["order"] = AnyEncodable(order) }
            if let allowFallbacks = config.allowFallbacks { map["allow_fallbacks"] = AnyEncodable(allowFallbacks) }
            if let requireParameters = config.requireParameters { map["require_parameters"] = AnyEncodable(requireParameters) }
            if let dataCollection = config.dataCollection, !dataCollection.isEmpty { map["data_collection"] = AnyEncodable(dataCollection) }
            if let quantizations = config.quantizations, !quantizations.isEmpty { map["quantizations"] = AnyEncodable(quantizations) }
            if let only = config.only, !only.isEmpty { map["only"] = AnyEncodable(only) }
            if let ignore = config.ignore, !ignore.isEmpty { map["ignore"] = AnyEncodable(ignore) }
            if let sort = config.sort, !sort.isEmpty { map["sort"] = AnyEncodable(sort) }
            if let price = config.maxPrice {
                var maxPrice: [String: AnyEncodable] = [:]
                if let prompt = price.prompt { maxPrice["prompt"] = AnyEncodable(prompt) }
                if let completion = price.completion { maxPrice["completion"] = AnyEncodable(completion) }
                if let requestPrice = price.request { maxPrice["request"] = AnyEncodable(requestPrice) }
                if let image = price.image { maxPrice["image"] = AnyEncodable(image) }
                if let audio = price.audio { maxPrice["audio"] = AnyEncodable(audio) }
                if !maxPrice.isEmpty {
                    map["max_price"] = AnyEncodable(maxPrice)
                }
            }
            return map.isEmpty ? nil : map
        }()

        let reasoningPayload = request.thinking.map { thinking in
            var map: [String: AnyEncodable] = [:]
            if let enabled = thinking.enabled { map["enabled"] = AnyEncodable(enabled) }
            if let budget = thinking.budget { map["max_tokens"] = AnyEncodable(budget) }
            if let effort = thinking.effort { map["effort"] = AnyEncodable(effort) }
            if let exclude = thinking.exclude { map["exclude"] = AnyEncodable(exclude) }
            return map
        }

        let body = OpenAIRequestBody(
            model: request.model,
            messages: mapMessages(request.messages, systemPrompt: request.systemPrompt),
            stream: stream,
            tools: toolsPayload,
            provider: providerPayload,
            reasoning: reasoningPayload
        )
        return try JSONEncoder().encode(body)
    }

    private func parseStreamChunk(_ chunk: String, fullText: inout String) -> ProviderStreamEvent? {
        guard let root = try? JSONSerialization.jsonObject(with: Data(chunk.utf8)) as? [String: Any] else {
            return nil
        }

        // OpenAI / OpenRouter ChatCompletions streaming format
        if let choices = root["choices"] as? [[String: Any]], let first = choices.first {
            if let delta = first["delta"] as? [String: Any] {
                if let text = delta["content"] as? String, !text.isEmpty {
                    fullText += text
                    return .textDelta(text)
                }

                if let reasoning = delta["reasoning"] as? String, !reasoning.isEmpty {
                    return .reasoningDelta(reasoning)
                }

                if let reasoningContent = delta["reasoning_content"] as? String, !reasoningContent.isEmpty {
                    return .reasoningDelta(reasoningContent)
                }

                if let toolCalls = delta["tool_calls"] as? [[String: Any]],
                   let data = try? JSONSerialization.data(withJSONObject: toolCalls),
                   let raw = String(data: data, encoding: .utf8),
                   !raw.isEmpty {
                    return .toolCallDelta(raw)
                }
            }

            if let finish = first["finish_reason"] as? String, !finish.isEmpty, finish != "null" {
                return nil
            }
        }

        return nil
    }

    private func resolvedCredential(
        for provider: LLMProvider,
        settings: AppSettings,
        credentialStore: SecureCredentialStore
    ) throws -> String {
        if provider == .openAICompat,
           let preset = settings.selectedOpenAICompatPreset,
           let presetKey = try credentialStore.openAICompatAPIKey(name: preset),
           !presetKey.isEmpty {
            return presetKey
        }

        let credentialProvider = credentialProvider(for: provider)
        guard let apiKey = try credentialStore.credential(for: credentialProvider), !apiKey.isEmpty else {
            throw ProviderClientError.missingCredential(provider.rawValue)
        }
        return apiKey
    }

    private func credentialProvider(for provider: LLMProvider) -> CredentialProvider {
        switch provider {
        case .openRouter:
            return .openRouter
        case .qwenCode:
            return .qwenCode
        case .openAI:
            return .openAI
        case .alibabaCodingPlan:
            return .alibabaCodingPlan
        case .openAICompat:
            return .openAICompat
        case .miniMax:
            return .miniMax
        case .zai:
            return .zai
        case .codexAuth:
            return .codexAuth
        case .gemini, .geminiAuth:
            return .gemini
        }
    }

    private func endpointURL(
        for provider: LLMProvider,
        settings: AppSettings,
        credentialStore: SecureCredentialStore
    ) throws -> URL {
        switch provider {
        case .openRouter:
            guard let url = URL(string: "https://openrouter.ai/api/v1/chat/completions") else {
                throw ProviderClientError.invalidBaseURL("https://openrouter.ai/api/v1/chat/completions")
            }
            return url
        case .qwenCode:
            let baseURL = QwenAuthRepository.normalizedBaseURL(resourceURL: try credentialStore.qwenResourceURL())
            guard let url = URL(string: baseURL)?.appendingPathComponent("chat/completions") else {
                throw ProviderClientError.invalidBaseURL(baseURL)
            }
            return url
        case .alibabaCodingPlan:
            throw ProviderClientError.invalidBaseURL("Provider not supported by OpenAI compatible client")
        case .openAI:
            let baseURL = settings.resolvedOpenAIBaseURL()
            guard let url = URL(string: baseURL)?.appendingPathComponent("chat/completions") else {
                throw ProviderClientError.invalidBaseURL(baseURL)
            }
            return url
        case .openAICompat:
            let base = settings.selectedCompatBaseURL() ?? URL(string: settings.resolvedOpenAIBaseURL())
            guard let url = base?.appendingPathComponent("chat/completions") else {
                throw ProviderClientError.invalidBaseURL(base?.absoluteString ?? settings.resolvedOpenAIBaseURL())
            }
            return url
        case .miniMax:
            let baseURL = settings.resolvedMiniMaxBaseURL()
            guard let url = URL(string: baseURL)?.appendingPathComponent("chat/completions") else {
                throw ProviderClientError.invalidBaseURL(baseURL)
            }
            return url
        case .zai:
            guard let url = URL(string: "https://api.z.ai/v1/chat/completions") else {
                throw ProviderClientError.invalidBaseURL("https://api.z.ai/v1/chat/completions")
            }
            return url
        case .codexAuth, .gemini, .geminiAuth:
            throw ProviderClientError.invalidBaseURL("Provider not supported by OpenAI compatible client")
        }
    }

    private func headers(for provider: LLMProvider, token: String) -> [String: String] {
        var headers = [
            "Authorization": "Bearer \(token)",
            "Content-Type": "application/json"
        ]

        if provider == .openRouter {
            headers["HTTP-Referer"] = "https://yamabikochat.app"
            headers["X-Title"] = "YamabikoChat iOS"
        }

        return headers
    }

    private func mapMessages(_ messages: [ProviderRequestMessage], systemPrompt: String?) -> [OpenAIMessage] {
        var mapped: [OpenAIMessage] = []
        if let systemPrompt, !systemPrompt.isEmpty {
            mapped.append(OpenAIMessage(role: "system", content: systemPrompt))
        }

        for message in messages {
            var content = message.content
            if !message.attachments.isEmpty {
                let attachmentText = message.attachments.map { "- \($0)" }.joined(separator: "\n")
                content += "\n\nAttachments:\n\(attachmentText)"
            }
            mapped.append(OpenAIMessage(role: message.role, content: content))
        }
        return mapped
    }

    private func parseResponse(data: Data) throws -> ProviderResponse {
        if
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any]
        {
            let content = (message["content"] as? String) ?? ""
            let reasoningSummary = (message["reasoning_content"] as? String)?.trimmedNonEmpty
            let usage = parseUsage(root["usage"] as? [String: Any])
            return ProviderResponse(
                text: content,
                reasoningSummary: reasoningSummary,
                raw: String(data: data, encoding: .utf8),
                usage: usage
            )
        }

        throw ProviderClientError.parseFailure("OpenAI-style response does not contain choices[0].message.content")
    }

    private func parseUsage(_ object: [String: Any]?) -> ProviderUsage? {
        guard let object else { return nil }
        let completionDetails = object["completion_tokens_details"] as? [String: Any]
        let outputDetails = object["output_tokens_details"] as? [String: Any]
        let promptDetails = object["prompt_tokens_details"] as? [String: Any]
        let inputDetails = object["input_tokens_details"] as? [String: Any]
        let inputTokens = intValue(in: object, keys: ["prompt_tokens", "input_tokens", "promptTokens", "inputTokens"])
        let outputTokens = intValue(in: object, keys: ["completion_tokens", "output_tokens", "completionTokens", "outputTokens"])
        let totalTokens = intValue(in: object, keys: ["total_tokens", "totalTokens"])
        let reasoningTokens =
            intValue(in: object, keys: ["reasoning_tokens", "reasoningTokens", "reasoning_token_count", "reasoningTokenCount"]) ??
            intValue(in: completionDetails, keys: ["reasoning_tokens", "reasoningTokens", "reasoning", "reasoning_token_count"]) ??
            intValue(in: outputDetails, keys: ["reasoning_tokens", "reasoningTokens", "reasoning", "reasoning_token_count"])
        let cachedTokens =
            intValue(in: promptDetails, keys: ["cached_tokens", "cachedTokens", "cached_input_tokens", "cachedInputTokens"]) ??
            intValue(in: inputDetails, keys: ["cached_tokens", "cachedTokens", "cached_input_tokens", "cachedInputTokens"]) ??
            intValue(
                in: object,
                keys: [
                    "cache_read_input_tokens",
                    "cacheReadInputTokens",
                    "cached_input_tokens",
                    "cachedInputTokens"
                ]
            )
        let cacheCreationTokens =
            intValue(in: promptDetails, keys: ["cache_creation_tokens", "cacheCreationTokens", "cache_creation_input_tokens"]) ??
            intValue(in: inputDetails, keys: ["cache_creation_tokens", "cacheCreationTokens", "cache_creation_input_tokens"]) ??
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
}

private extension String {
    var trimmedNonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
