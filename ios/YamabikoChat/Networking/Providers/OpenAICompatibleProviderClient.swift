import Foundation

struct OpenAICompatibleProviderClient: ProviderClient {
    let provider: LLMProvider = .openAI

    private struct OpenAIFunctionCall: Encodable {
        var name: String
        var arguments: String
    }

    private struct OpenAIToolCall: Encodable {
        var id: String
        var type: String = "function"
        var function: OpenAIFunctionCall
    }

    private struct OpenAIMessage: Encodable {
        var role: String
        var content: ProviderAttachmentEncoder.OpenAIMessageContent?
        var toolCalls: [OpenAIToolCall]?
        var toolCallId: String?
        var name: String?

        enum CodingKeys: String, CodingKey {
            case role
            case content
            case toolCalls = "tool_calls"
            case toolCallId = "tool_call_id"
            case name
        }
    }

    private struct PromptCacheControl: Encodable {
        var type: String = "ephemeral"
    }

    private struct OpenAIRequestBody: Encodable {
        var model: String
        var messages: [OpenAIMessage]
        var stream: Bool
        var tools: [[String: AnyEncodable]]?
        var provider: [String: AnyEncodable]?
        var reasoning: [String: AnyEncodable]?
        var reasoningEffort: String?
        var cacheControl: PromptCacheControl?
        var promptCacheKey: String?
        var maxTokens: Int?
        var temperature: Double?

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case stream
            case tools
            case provider
            case reasoning
            case reasoningEffort = "reasoning_effort"
            case cacheControl = "cache_control"
            case promptCacheKey = "prompt_cache_key"
            case maxTokens = "max_tokens"
            case temperature
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(model, forKey: .model)
            try container.encode(messages, forKey: .messages)
            try container.encode(stream, forKey: .stream)
            try container.encodeIfPresent(tools, forKey: .tools)
            try container.encodeIfPresent(provider, forKey: .provider)
            try container.encodeIfPresent(reasoning, forKey: .reasoning)
            try container.encodeIfPresent(reasoningEffort, forKey: .reasoningEffort)
            try container.encodeIfPresent(cacheControl, forKey: .cacheControl)
            try container.encodeIfPresent(promptCacheKey, forKey: .promptCacheKey)
            try container.encodeIfPresent(maxTokens, forKey: .maxTokens)
            try container.encodeIfPresent(temperature, forKey: .temperature)
        }
    }

    func generate(
        request: ProviderRequest,
        settings: AppSettings,
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol
    ) async throws -> ProviderResponse {
        if request.metadata["modelsDevProviderID"] != nil {
            return try await generateModelsDev(
                request: request,
                credentialStore: credentialStore,
                httpClient: httpClient
            )
        }
        let resolvedProvider = LLMProvider(rawOrDefault: request.metadata["provider"] ?? settings.apiProvider)
        try validateModel(request.model, for: resolvedProvider)
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
                    if request.metadata["modelsDevProviderID"] != nil {
                        try await streamModelsDev(
                            request: request,
                            credentialStore: credentialStore,
                            httpClient: httpClient,
                            continuation: continuation
                        )
                        return
                    }
                    let resolvedProvider = LLMProvider(rawOrDefault: request.metadata["provider"] ?? settings.apiProvider)
                    try validateModel(request.model, for: resolvedProvider)
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
                        let errorBody = await Self.readStreamErrorBody(lineStream)
                        let message = errorBody.isEmpty
                            ? "Streaming endpoint returned \(response.statusCode)"
                            : errorBody
                        throw ProviderClientError.httpStatus(response.statusCode, message)
                    }

                    try await ProviderSSEStreamRunner.pump(
                        lineStream: lineStream,
                        continuation: continuation,
                        options: ProviderSSEStreamRunner.Options(
                            usageFromRoot: { [self] root in
                                if let usage = parseUsage(root["usage"] as? [String: Any])?.normalizedNonEmpty() {
                                    return usage
                                }
                                return parseUsage(root)?.normalizedNonEmpty()
                            },
                            eventsFromRoot: { root, fullText, fullReasoning in
                                OpenAICompatibleStreamParser.events(
                                    fromRoot: root,
                                    fullText: &fullText,
                                    fullReasoning: &fullReasoning
                                )
                            }
                        )
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func modelsDevContext(
        request: ProviderRequest,
        credentialStore: SecureCredentialStore
    ) throws -> (token: String, endpoint: URL, headers: [String: String]) {
        guard let providerID = request.metadata["modelsDevProviderID"]?.trimmedNonEmpty,
              let credentialKey = request.metadata["modelsDevCredentialKey"]?.trimmedNonEmpty,
              let token = try credentialStore.readSecret(key: credentialKey)?.trimmedNonEmpty,
              let baseURL = request.metadata["modelsDevBaseURL"]?.trimmedNonEmpty,
              let base = URL(string: baseURL)
        else { throw ProviderClientError.missingCredential(request.metadata["modelsDevProviderID"] ?? "models.dev") }
        let endpoint = base.path.hasSuffix("/chat/completions")
            ? base
            : base.appendingPathComponent("chat/completions")
        var headers = ["Content-Type": "application/json"]
        if request.metadata["modelsDevAuthHeader"] == "api-key" {
            headers["api-key"] = token
        } else if request.metadata["modelsDevAuthHeader"] == "cf-aig-authorization" {
            headers["cf-aig-authorization"] = "Bearer \(token)"
        } else {
            headers["Authorization"] = "Bearer \(token)"
        }
        DiagnosticsLogger.log("models.dev OpenAI-compatible request", category: .network, metadata: ["provider": providerID, "model": request.model])
        return (token, endpoint, headers)
    }

    private func generateModelsDev(
        request: ProviderRequest,
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol
    ) async throws -> ProviderResponse {
        let context = try modelsDevContext(request: request, credentialStore: credentialStore)
        let payload = try buildPayload(for: request, stream: false, provider: .openAICompat)
        let httpRequest = HTTPRequest(
            url: context.endpoint,
            headers: context.headers,
            body: payload
        )
        let (data, response) = try await httpClient.send(httpRequest)
        guard (200 ... 299).contains(response.statusCode) else {
            throw ProviderClientError.httpStatus(response.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try parseResponse(data: data)
    }

    private func streamModelsDev(
        request: ProviderRequest,
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol,
        continuation: AsyncThrowingStream<ProviderStreamEvent, Error>.Continuation
    ) async throws {
        let context = try modelsDevContext(request: request, credentialStore: credentialStore)
        let payload = try buildPayload(for: request, stream: true, provider: .openAICompat)
        var headers = context.headers
        headers["Accept"] = "text/event-stream"
        let httpRequest = HTTPRequest(
            url: context.endpoint,
            headers: headers,
            body: payload
        )
        let (lineStream, response) = try await httpClient.stream(httpRequest)
        guard (200 ... 299).contains(response.statusCode) else {
            throw ProviderClientError.httpStatus(response.statusCode, "Streaming endpoint returned \(response.statusCode)")
        }
        try await ProviderSSEStreamRunner.pump(
            lineStream: lineStream,
            continuation: continuation,
            options: ProviderSSEStreamRunner.Options(
                usageFromRoot: { [self] root in
                    if let usage = parseUsage(root["usage"] as? [String: Any])?.normalizedNonEmpty() { return usage }
                    return parseUsage(root)?.normalizedNonEmpty()
                },
                eventsFromRoot: { root, fullText, fullReasoning in
                    OpenAICompatibleStreamParser.events(fromRoot: root, fullText: &fullText, fullReasoning: &fullReasoning)
                }
            )
        )
    }

    private func buildPayload(for request: ProviderRequest, stream: Bool, provider: LLMProvider) throws -> Data {
        let toolsPayload = request.tools.isEmpty ? nil : request.tools.compactMap(openAIToolPayload)

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
            messages: mapMessages(
                request.messages,
                systemPrompt: request.systemPrompt,
                embedImages: ProviderAttachmentEncoder.shouldEmbedImages(metadata: request.metadata)
            ),
            stream: stream,
            tools: toolsPayload,
            provider: providerPayload,
            reasoning: reasoningPayload,
            reasoningEffort: request.metadata["modelsDevReasoningEffort"]?.trimmedNonEmpty,
            cacheControl: cacheControl(for: request, provider: provider),
            promptCacheKey: promptCacheKey(for: request, provider: provider),
            maxTokens: Int(request.metadata["max_output_tokens"] ?? ""),
            temperature: Double(request.metadata["temperature"] ?? "")
        )
        return try JSONEncoder().encode(body)
    }

    private func cacheControl(for request: ProviderRequest, provider: LLMProvider) -> PromptCacheControl? {
        guard provider == .openRouter else { return nil }
        let normalizedModel = request.model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedModel.hasPrefix("anthropic/claude") || normalizedModel.hasPrefix("claude") else {
            return nil
        }
        return PromptCacheControl()
    }

    private func promptCacheKey(for request: ProviderRequest, provider: LLMProvider) -> String? {
        guard provider == .openAI else { return nil }
        return request.metadata["promptCacheKey"]?.trimmedNonEmpty
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
        case .openCodeGo:
            return .openCodeGo
        case .clinePass:
            return .clinePass
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
        case .superGrok:
            return .superGrok
        case .gemini, .appleIntelligence:
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
        case .openCodeGo:
            throw ProviderClientError.invalidBaseURL("Provider not supported by generic OpenAI compatible client")
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
            return AppConstants.defaultZAICodingPlanBaseURL.appendingPathComponent("chat/completions")
        case .clinePass:
            guard let url = URL(string: "https://api.cline.bot/api/v1/chat/completions") else {
                throw ProviderClientError.invalidBaseURL("https://api.cline.bot/api/v1/chat/completions")
            }
            return url
        case .codexAuth, .superGrok, .gemini, .appleIntelligence:
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

    private func validateModel(_ model: String, for provider: LLMProvider) throws {
        if provider == .zai, !ZAICodingPlanModelCatalog.isSupported(model) {
            throw ProviderClientError.unsupportedModel(provider: "Z.ai Coding Plan", model: model)
        }
    }

    private func mapMessages(
        _ messages: [ProviderRequestMessage],
        systemPrompt: String?,
        embedImages: Bool
    ) -> [OpenAIMessage] {
        var mapped: [OpenAIMessage] = []
        if let systemPrompt, !systemPrompt.isEmpty {
            mapped.append(
                OpenAIMessage(
                    role: "system",
                    content: .plain(systemPrompt),
                    toolCalls: nil,
                    toolCallId: nil,
                    name: nil
                )
            )
        }

        for message in messages {
            if message.role == "tool" {
                mapped.append(
                    OpenAIMessage(
                        role: "tool",
                        content: .plain(message.content),
                        toolCalls: nil,
                        toolCallId: message.toolCallId,
                        name: message.toolName
                    )
                )
                continue
            }
            ProviderAttachmentEncoder.logSkippedAttachmentsIfNeeded(
                message.attachments,
                providerLabel: "OpenAI compatible",
                embedImages: embedImages
            )
            let toolCalls = message.toolCalls?.map {
                OpenAIToolCall(
                    id: $0.id,
                    function: OpenAIFunctionCall(name: $0.name, arguments: $0.argumentsJSON)
                )
            }
            mapped.append(
                OpenAIMessage(
                    role: message.role,
                    content: ProviderAttachmentEncoder.buildOpenAIMessageContent(
                        text: message.content,
                        attachments: message.attachments,
                        embedImages: embedImages
                    ),
                    toolCalls: toolCalls?.isEmpty == true ? nil : toolCalls,
                    toolCallId: nil,
                    name: nil
                )
            )
        }
        return mapped
    }

    private func openAIToolPayload(_ tool: ProviderTool) -> [String: AnyEncodable]? {
        guard tool.type == "function" else {
            return [
                "type": AnyEncodable(tool.type),
                "payload": AnyEncodable(tool.payload)
            ]
        }
        guard let name = tool.payload["name"]?.trimmedNonEmpty,
              let parametersJSON = tool.payload["parameters"]?.trimmedNonEmpty,
              let data = parametersJSON.data(using: .utf8),
              let parameters = try? JSONDecoder().decode(JSONValue.self, from: data)
        else {
            DiagnosticsLogger.log(
                "Invalid local function definition skipped",
                level: .warning,
                category: .network,
                metadata: ["name": tool.payload["name"] ?? ""]
            )
            return nil
        }
        var function: [String: AnyEncodable] = [
            "name": AnyEncodable(name),
            "parameters": AnyEncodable(parameters)
        ]
        if let description = tool.payload["description"]?.trimmedNonEmpty {
            function["description"] = AnyEncodable(description)
        }
        return [
            "type": AnyEncodable("function"),
            "function": AnyEncodable(function)
        ]
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
            let toolCalls = parseToolCalls(message["tool_calls"])
            return ProviderResponse(
                text: content,
                reasoningSummary: reasoningSummary,
                raw: String(data: data, encoding: .utf8),
                usage: usage,
                toolCalls: toolCalls
            )
        }

        throw ProviderClientError.parseFailure("OpenAI-style response does not contain choices[0].message")
    }

    private func parseToolCalls(_ rawValue: Any?) -> [ToolCall] {
        guard let values = rawValue as? [[String: Any]] else { return [] }
        return values.enumerated().compactMap { index, value in
            guard let function = value["function"] as? [String: Any],
                  let name = (function["name"] as? String)?.trimmedNonEmpty
            else {
                return nil
            }
            return ToolCall(
                id: (value["id"] as? String)?.trimmedNonEmpty ?? "tool-call-\(index)",
                name: name,
                argumentsJSON: (function["arguments"] as? String)?.trimmedNonEmpty ?? "{}",
                providerMetadata: nil
            )
        }
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

    private static func readStreamErrorBody(
        _ stream: AsyncThrowingStream<String, Error>,
        maxBytes: Int = 16_384
    ) async -> String {
        var chunks: [String] = []
        var total = 0
        do {
            for try await line in stream {
                chunks.append(line)
                total += line.utf8.count + 1
                if total >= maxBytes {
                    break
                }
            }
        } catch {
            return chunks.joined(separator: "\n")
        }
        return chunks.joined(separator: "\n")
    }
}
