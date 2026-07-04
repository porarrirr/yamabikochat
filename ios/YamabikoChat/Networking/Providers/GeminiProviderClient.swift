import Foundation

struct GeminiProviderClient: ProviderClient {
    let provider: LLMProvider = .gemini
    private let geminiApiBase = "https://generativelanguage.googleapis.com/v1beta"
    static let noUsableStreamDataReason = "Gemini stream produced no usable data"

    func generate(
        request: ProviderRequest,
        settings: AppSettings,
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol
    ) async throws -> ProviderResponse {
        _ = settings
        return try await generateWithAPIKey(request: request, credentialStore: credentialStore, httpClient: httpClient)
    }

    func stream(
        request: ProviderRequest,
        settings: AppSettings,
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol
    ) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        _ = settings
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard let apiKey = try credentialStore.credential(for: .gemini)?.trimmedNonEmpty else {
                        throw ProviderClientError.missingCredential(LLMProvider.gemini.rawValue)
                    }
                    let endpoint = try streamEndpoint(model: request.model, token: apiKey)
                    let body = try buildGeminiBody(
                        request: request,
                        credentialStore: credentialStore
                    )
                    let httpRequest = HTTPRequest(
                        url: endpoint,
                        headers: ["Content-Type": "application/json"],
                        body: body.data
                    )
                    DiagnosticsLogger.log(
                        "Gemini stream start",
                        category: .network,
                        metadata: [
                            "provider": LLMProvider.gemini.rawValue,
                            "model": request.model,
                            "url": endpoint.absoluteString
                        ]
                    )
                    let (lineStream, response) = try await httpClient.stream(httpRequest)
                    guard (200 ... 299).contains(response.statusCode) else {
                        let bodyText = await collectStreamErrorBody(lineStream: lineStream)
                        throw ProviderClientError.httpStatus(response.statusCode, bodyText)
                    }
                    try await consumeStreamEvents(
                        lineStream: lineStream,
                        response: response,
                        model: request.model,
                        continuation: continuation
                    )
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private struct ParsedGeminiParts {
        var text: String
        var reasoning: String
        var toolCalls: [ToolCall]
    }

    private struct ParsedGeminiChunk {
        var text: String
        var reasoning: String
        var usage: ProviderUsage?
        var toolCalls: [ToolCall]
    }

    private struct ParsedGeminiError {
        var rawBody: String?
        var message: String?
        var details: [[String: Any]]
    }

    private func consumeStreamEvents(
        lineStream: AsyncThrowingStream<String, Error>,
        response: HTTPURLResponse,
        model: String,
        continuation: AsyncThrowingStream<ProviderStreamEvent, Error>.Continuation
    ) async throws {
        var fullText = ""
        var fullReasoning = ""
        var latestUsage: ProviderUsage?
        var hasUsableData = false
        var streamFinished = false
        var parseErrorCount = 0
        var payloadCount = 0
        var flushCount = 0
        var flushTrace: [String] = []
        var invalidPayloadSnippets: [String] = []
        var toolCallAccumulator = ToolCallAccumulator()
        let maxSnippets = 6
        let snippetLimit = 256

        func recordInvalidPayload(_ payload: String) {
            parseErrorCount += 1
            guard invalidPayloadSnippets.count < maxSnippets else { return }
            let compact = payload
                .replacingOccurrences(of: "\n", with: "\\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            invalidPayloadSnippets.append(String(compact.prefix(snippetLimit)))
        }

        func failNoUsableData(_ phase: String) throws {
            DiagnosticsLogger.log(
                "Gemini stream produced no usable data",
                category: .network,
                metadata: [
                    "provider": LLMProvider.gemini.rawValue,
                    "model": model,
                    "phase": phase,
                    "status": String(response.statusCode),
                    "payload_count": String(payloadCount),
                    "flush_count": String(flushCount),
                    "flush_trace": flushTrace.joined(separator: " | "),
                    "parse_error_count": String(parseErrorCount),
                    "invalid_payloads": invalidPayloadSnippets.joined(separator: " || ")
                ]
            )
            throw ProviderClientError.parseFailure(Self.noUsableStreamDataReason)
        }

        func parseChunk(_ chunk: String) -> ParsedGeminiChunk? {
            parseGeminiStreamChunk(chunk)
        }

        func processPayload(_ chunk: String, trigger: String) throws {
            guard !streamFinished else { return }
            guard !chunk.isEmpty else { return }
            flushCount += 1
            let shape = chunk == "[DONE]" ? "done" : (chunk.contains("\n") ? "multiline" : "singleline")
            if flushTrace.count < 10 {
                flushTrace.append("\(trigger):\(shape)")
            }

            if chunk == "[DONE]" {
                if !hasUsableData && fullText.isEmpty && fullReasoning.isEmpty {
                    try failNoUsableData("done")
                }
                let final = ProviderResponse(
                    text: fullText,
                    reasoningSummary: fullReasoning.trimmedNonEmpty,
                    raw: nil,
                    usage: latestUsage,
                    toolCalls: toolCallAccumulator.toolCalls
                )
                continuation.yield(.completed(final))
                continuation.finish()
                streamFinished = true
                return
            }

            let parsed = parseChunk(chunk)
            guard let parsed else {
                recordInvalidPayload(chunk)
                return
            }
            if let usage = parsed.usage?.normalizedNonEmpty() {
                latestUsage = usage
            }

            if !parsed.reasoning.isEmpty {
                let reasoningDelta = StreamDeltaAccumulator.incrementalDelta(
                    buffer: fullReasoning,
                    incoming: parsed.reasoning
                )
                if !reasoningDelta.isEmpty {
                    fullReasoning += reasoningDelta
                    hasUsableData = true
                    continuation.yield(.reasoningDelta(reasoningDelta))
                }
            }
            if !parsed.text.isEmpty {
                let textDelta = StreamDeltaAccumulator.incrementalDelta(buffer: fullText, incoming: parsed.text)
                if !textDelta.isEmpty {
                    fullText += textDelta
                    hasUsableData = true
                    continuation.yield(.textDelta(textDelta))
                }
            }
            for (index, call) in parsed.toolCalls.enumerated() {
                let delta = ToolCallDelta(
                    index: index,
                    id: call.id,
                    name: call.name,
                    argumentsFragment: call.argumentsJSON,
                    providerMetadata: call.providerMetadata
                )
                toolCallAccumulator.append(delta)
                hasUsableData = true
                continuation.yield(.toolCallDelta(delta))
            }
        }

        for try await chunk in SSEPayloadAssembly.payloads(from: lineStream) {
            if streamFinished { return }
            payloadCount += 1
            try processPayload(chunk, trigger: "payload")
        }

        if streamFinished { return }
        if streamFinished { return }
        if !hasUsableData && fullText.isEmpty && fullReasoning.isEmpty {
            try failNoUsableData("eof")
        }

        let final = ProviderResponse(
            text: fullText,
            reasoningSummary: fullReasoning.trimmedNonEmpty,
            raw: nil,
            usage: latestUsage,
            toolCalls: toolCallAccumulator.toolCalls
        )
        continuation.yield(.completed(final))
        continuation.finish()
    }

    private func collectStreamErrorBody(lineStream: AsyncThrowingStream<String, Error>) async -> String {
        let parsed = await parseGeminiStreamErrorBody(lineStream: lineStream)
        if let message = parsed.message?.trimmedNonEmpty {
            return message
        }
        return parsed.rawBody?.trimmedNonEmpty ?? ""
    }

    private func parseGeminiStreamErrorBody(lineStream: AsyncThrowingStream<String, Error>) async -> ParsedGeminiError {
        let maxCollectedCharacters = 64 * 1024
        var regularLines: [String] = []
        var dataLines: [String] = []
        var consumedCharacters = 0

        do {
            for try await line in lineStream {
                let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.hasPrefix("data:") {
                    let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                    if !payload.isEmpty {
                        dataLines.append(payload)
                        consumedCharacters += payload.count
                    }
                } else if !trimmed.isEmpty {
                    regularLines.append(trimmed)
                    consumedCharacters += trimmed.count
                }
                if consumedCharacters >= maxCollectedCharacters {
                    break
                }
            }
        } catch {
            // Best effort: parse what we already collected.
        }

        let candidates = [
            dataLines.joined(separator: "\n").trimmedNonEmpty,
            regularLines.joined(separator: "\n").trimmedNonEmpty
        ]
            .compactMap { $0 }

        for candidate in candidates {
            if let parsed = parseGeminiErrorBody(candidate) {
                return parsed
            }
        }

        return ParsedGeminiError(
            rawBody: candidates.first,
            message: nil,
            details: []
        )
    }

    private func parseGeminiErrorBody(_ rawBody: String) -> ParsedGeminiError? {
        guard let root = parseJSONObject(rawBody) else { return nil }
        let errorObject = (root["error"] as? [String: Any]) ?? root
        let details = (errorObject["details"] as? [Any] ?? [])
            .compactMap { $0 as? [String: Any] }
        return ParsedGeminiError(
            rawBody: rawBody,
            message: (errorObject["message"] as? String)?.trimmedNonEmpty,
            details: details
        )
    }

    private func generateWithAPIKey(
        request: ProviderRequest,
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol
    ) async throws -> ProviderResponse {
        guard let apiKey = try credentialStore.credential(for: .gemini)?.trimmedNonEmpty else {
            throw ProviderClientError.missingCredential(LLMProvider.gemini.rawValue)
        }

        guard let url = nonStreamingEndpoint(model: request.model, token: apiKey) else {
            throw ProviderClientError.invalidBaseURL("Gemini endpoint")
        }

        let payload = try buildGeminiBody(request: request, credentialStore: credentialStore)
        let httpRequest = HTTPRequest(
            url: url,
            headers: ["Content-Type": "application/json"],
            body: payload.data
        )

        let (data, response) = try await httpClient.send(httpRequest)
        guard (200 ... 299).contains(response.statusCode) else {
            throw ProviderClientError.httpStatus(response.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        return try parseResponse(data: data)
    }

    private func nonStreamingEndpoint(model: String, token: String) -> URL? {
        var components = URLComponents(string: "\(geminiApiBase)/models/\(model):generateContent")
        components?.queryItems = [URLQueryItem(name: "key", value: token)]
        return components?.url
    }

    private func streamEndpoint(model: String, token: String) throws -> URL {
        var components = URLComponents(string: "\(geminiApiBase)/models/\(model):streamGenerateContent")
        components?.queryItems = [
            URLQueryItem(name: "alt", value: "sse"),
            URLQueryItem(name: "key", value: token)
        ]
        guard let url = components?.url else {
            throw ProviderClientError.invalidBaseURL("Gemini streaming endpoint")
        }
        return url
    }

    private struct GeminiBodyBuildResult {
        var data: Data
        var requestIdentifier: String?
    }

    private func buildGeminiBody(
        request: ProviderRequest,
        credentialStore: SecureCredentialStore
    ) throws -> GeminiBodyBuildResult {
        _ = credentialStore
        let embedImages = ProviderAttachmentEncoder.shouldEmbedImages(metadata: request.metadata)
        let contents = request.messages.map { message -> [String: Any] in
            [
                "role": message.role == "assistant" ? "model" : "user",
                "parts": buildGeminiParts(for: message, embedImages: embedImages)
            ]
        }

        var generationConfig: [String: Any] = [:]
        if let maxTokens = Int(request.metadata["max_output_tokens"] ?? ""), maxTokens > 0 {
            generationConfig["maxOutputTokens"] = maxTokens
        }
        if let temperature = Double(request.metadata["temperature"] ?? "") {
            generationConfig["temperature"] = temperature
        }
        if let mime = request.metadata["geminiResponseMimeType"]?.trimmedNonEmpty {
            generationConfig["responseMimeType"] = mime
        }
        if let schemaText = request.metadata["geminiResponseJSONSchema"]?.trimmedNonEmpty,
           let data = schemaText.data(using: .utf8),
           let jsonObject = try? JSONSerialization.jsonObject(with: data) {
            generationConfig["responseJsonSchema"] = jsonObject
        }

        if let thinking = request.thinking {
            var thinkingConfig: [String: Any] = [:]
            if let budget = thinking.budget {
                thinkingConfig["thinkingBudget"] = budget
            }
            if let includeThoughts = thinking.includeThoughts {
                thinkingConfig["includeThoughts"] = includeThoughts
            }
            if let level = request.metadata["geminiThinkingLevel"]?.trimmedNonEmpty {
                thinkingConfig["thinkingLevel"] = level
            }
            if !thinkingConfig.isEmpty {
                generationConfig["thinkingConfig"] = thinkingConfig
            }
        }

        let tools = geminiToolObjects(from: request.tools)

        var root: [String: Any] = [
            "contents": contents
        ]
        if let systemPrompt = request.systemPrompt, !systemPrompt.isEmpty {
            root["system_instruction"] = ["parts": [["text": systemPrompt]]]
        }
        if !tools.isEmpty {
            root["tools"] = tools
        }
        if !generationConfig.isEmpty {
            root["generationConfig"] = generationConfig
        }
        return GeminiBodyBuildResult(
            data: try JSONSerialization.data(withJSONObject: root),
            requestIdentifier: nil
        )
    }

    private func buildGeminiParts(for message: ProviderRequestMessage, embedImages: Bool) -> [[String: Any]] {
        if message.role == "tool" {
            let responseValue: Any
            if let data = message.content.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) {
                responseValue = object
            } else {
                responseValue = ["result": message.content]
            }
            var functionResponse: [String: Any] = [
                "name": message.toolName ?? "",
                "response": responseValue
            ]
            if let id = message.toolCallId?.trimmedNonEmpty {
                functionResponse["id"] = id
            }
            return [["functionResponse": functionResponse]]
        }

        var parts: [[String: Any]] = []
        if !message.content.isEmpty || !message.attachments.isEmpty {
            parts = ProviderAttachmentEncoder.buildGeminiParts(
                text: message.content,
                attachments: message.attachments,
                embedImages: embedImages
            )
        }
        if message.role == "assistant" {
            for call in message.toolCalls ?? [] {
                let arguments: Any
                if let data = call.argumentsJSON.data(using: .utf8),
                   let object = try? JSONSerialization.jsonObject(with: data) {
                    arguments = object
                } else {
                    arguments = [:]
                }
                var functionCall: [String: Any] = [
                    "name": call.name,
                    "args": arguments
                ]
                functionCall["id"] = call.id
                var part: [String: Any] = ["functionCall": functionCall]
                if let signature = call.providerMetadata?["thoughtSignature"]?.trimmedNonEmpty {
                    part["thoughtSignature"] = signature
                }
                parts.append(part)
            }
        }
        if parts.isEmpty {
            parts.append(["text": ""])
        }
        return parts
    }

    private func parseGeminiParts(_ parts: [[String: Any]], payloadText: String? = nil) -> ParsedGeminiParts {
        var text = ""
        var reasoning = ""
        var toolCalls: [ToolCall] = []

        for (index, part) in parts.enumerated() {
            if let value = part["text"] as? String, !value.isEmpty {
                if (part["thought"] as? Bool) == true {
                    reasoning += value
                } else {
                    text += value
                }
            }
            if let functionCall = part["functionCall"] as? [String: Any],
               let name = (functionCall["name"] as? String)?.trimmedNonEmpty {
                let argumentsJSON: String
                if let args = functionCall["args"],
                   JSONSerialization.isValidJSONObject(args),
                   let data = try? JSONSerialization.data(withJSONObject: args, options: [.sortedKeys]) {
                    argumentsJSON = String(decoding: data, as: UTF8.self)
                } else {
                    argumentsJSON = "{}"
                }
                let signature = (part["thoughtSignature"] as? String)?.trimmedNonEmpty
                    ?? (part["thought_signature"] as? String)?.trimmedNonEmpty
                toolCalls.append(
                    ToolCall(
                        id: (functionCall["id"] as? String)?.trimmedNonEmpty ?? "gemini-tool-call-\(index)",
                        name: name,
                        argumentsJSON: argumentsJSON,
                        providerMetadata: signature.map { ["thoughtSignature": $0] }
                    )
                )
            }
        }

        if let payloadText, !payloadText.isEmpty {
            text += payloadText
        }

        return ParsedGeminiParts(text: text, reasoning: reasoning, toolCalls: toolCalls)
    }

    private func parseGeminiPartsFromPayload(_ payload: [String: Any]) -> ParsedGeminiParts? {
        var parts: [[String: Any]] = []
        if
            let candidates = payload["candidates"] as? [[String: Any]],
            let first = candidates.first,
            let content = first["content"] as? [String: Any],
            let candidateParts = content["parts"] as? [[String: Any]]
        {
            parts = candidateParts
        }

        let payloadText = payload["text"] as? String
        let parsed = parseGeminiParts(parts, payloadText: payloadText)
        guard !parsed.text.isEmpty || !parsed.reasoning.isEmpty || !parsed.toolCalls.isEmpty else {
            return nil
        }
        return parsed
    }

    private func parseGeminiStreamChunk(_ chunk: String) -> ParsedGeminiChunk? {
        guard let root = parseJSONObject(chunk) else { return nil }
        let parsedParts = parseGeminiPartsFromPayload(root)
        let usage = parseGeminiUsage(payload: root)
        if parsedParts == nil, usage == nil {
            return nil
        }
        return ParsedGeminiChunk(
            text: parsedParts?.text ?? "",
            reasoning: parsedParts?.reasoning ?? "",
            usage: usage,
            toolCalls: parsedParts?.toolCalls ?? []
        )
    }

    private func parseGeminiResponsePayload(payload: [String: Any], rawData: Data) throws -> ProviderResponse {
        guard let parsed = parseGeminiPartsFromPayload(payload) else {
            throw ProviderClientError.parseFailure("Gemini response missing candidates")
        }

        let text = parsed.text
        let reasoning = parsed.reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty && reasoning.isEmpty && parsed.toolCalls.isEmpty {
            throw ProviderClientError.parseFailure("Gemini response text and tool calls are empty")
        }

        return ProviderResponse(
            text: text,
            reasoningSummary: reasoning.isEmpty ? nil : reasoning,
            raw: String(data: rawData, encoding: .utf8),
            usage: parseGeminiUsage(payload: payload),
            toolCalls: parsed.toolCalls
        )
    }

    /// Keys that JSON Schema supports but Gemini's (OpenAPI subset) Schema does not.
    /// Stripping these at the Gemini boundary keeps the shared tool definitions valid for
    /// OpenAI/Anthropic while preventing HTTP 400 "Cannot find field" rejections.
    private static let geminiUnsupportedSchemaKeys: Set<String> = [
        "additionalProperties",
        "patternProperties",
        "$schema",
        "$ref",
        "$id",
        "$defs",
        "$comment",
        "definitions",
        "dependencies",
        "exclusiveMinimum",
        "exclusiveMaximum",
        "multipleOf",
        "oneOf",
        "anyOf",
        "allOf",
        "not",
        "const",
        "if",
        "then",
        "else",
        "examples"
    ]

    /// Recursively removes JSON Schema keys that Gemini's Schema does not accept, walking
    /// `properties` and `items` so nested fields are cleaned as well.
    private func sanitizeGeminiSchema(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            var cleaned: [String: Any] = [:]
            for (key, child) in dict {
                guard !Self.geminiUnsupportedSchemaKeys.contains(key) else { continue }
                cleaned[key] = sanitizeGeminiSchema(child)
            }
            return cleaned
        }
        if let array = value as? [Any] {
            return array.map(sanitizeGeminiSchema)
        }
        return value
    }

    /// Sanitizes a parsed function declaration's `parameters` schema in place.
    private func sanitizeFunctionDeclarations(_ declarations: [[String: Any]]) -> [[String: Any]] {
        declarations.map { declaration in
            var sanitized = declaration
            if let parameters = sanitized["parameters"] {
                sanitized["parameters"] = sanitizeGeminiSchema(parameters)
            }
            return sanitized
        }
    }

    private func geminiToolObjects(from tools: [ProviderTool]) -> [[String: Any]] {
        var mapped: [[String: Any]] = []
        var functionDeclarations: [[String: Any]] = []
        for tool in tools {
            switch tool.type {
            case "google_search":
                mapped.append(["google_search": [:]])
            case "code_execution":
                mapped.append(["code_execution": [:]])
            case "url_context":
                mapped.append(["url_context": [:]])
            case "google_maps":
                mapped.append(["google_maps": [:]])
            case "computer_use":
                mapped.append(["computer_use": [:]])
            case "function_declarations":
                if let json = tool.payload["json"]?.trimmedNonEmpty,
                   let data = json.data(using: .utf8),
                   let list = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                   !list.isEmpty {
                    functionDeclarations.append(contentsOf: sanitizeFunctionDeclarations(list))
                }
            case "function":
                guard let name = tool.payload["name"]?.trimmedNonEmpty,
                      let parametersJSON = tool.payload["parameters"]?.trimmedNonEmpty,
                      let data = parametersJSON.data(using: .utf8),
                      let parameters = try? JSONSerialization.jsonObject(with: data)
                else {
                    continue
                }
                var declaration: [String: Any] = [
                    "name": name,
                    "parameters": sanitizeGeminiSchema(parameters)
                ]
                if let description = tool.payload["description"]?.trimmedNonEmpty {
                    declaration["description"] = description
                }
                functionDeclarations.append(declaration)
            default:
                break
            }
        }
        if !functionDeclarations.isEmpty {
            // Gemini expects all function declarations consolidated under a single
            // `functionDeclarations` array (matching Android's Tool(function_declarations=[...])).
            mapped.append(["functionDeclarations": functionDeclarations])
        }
        return mapped
    }

    private func parseResponse(data: Data) throws -> ProviderResponse {
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ProviderClientError.parseFailure("Gemini response root is invalid")
        }

        return try parseGeminiResponsePayload(payload: root, rawData: data)
    }

    private func parseGeminiUsage(payload: [String: Any]) -> ProviderUsage? {
        guard
            let usage = (payload["usageMetadata"] as? [String: Any]) ??
                (payload["usage_metadata"] as? [String: Any])
        else {
            return nil
        }
        let promptTokenCount = intValue(in: usage, keys: ["promptTokenCount", "prompt_token_count"]) ?? 0
        let candidatesTokenCount = intValue(in: usage, keys: ["candidatesTokenCount", "candidates_token_count"]) ?? 0
        let cachedContentTokenCount = intValue(in: usage, keys: ["cachedContentTokenCount", "cached_content_token_count"])
        let thoughtsTokenCount = intValue(
            in: usage,
            keys: ["thoughtsTokenCount", "thoughts_token_count", "reasoningTokenCount", "reasoning_token_count"]
        )
        let cacheCreationTokenCount = intValue(
            in: usage,
            keys: ["cacheCreationInputTokenCount", "cache_creation_input_token_count"]
        )
        let toolUsePromptTokenCount = intValue(in: usage, keys: ["toolUsePromptTokenCount", "tool_use_prompt_token_count"]) ?? 0
        let totalFallback = promptTokenCount + candidatesTokenCount + toolUsePromptTokenCount + max(0, thoughtsTokenCount ?? 0)
        let totalTokenCount = intValue(in: usage, keys: ["totalTokenCount", "total_token_count"]) ?? totalFallback
        return ProviderUsage(
            inputTokens: promptTokenCount,
            outputTokens: candidatesTokenCount,
            totalTokens: totalTokenCount,
            reasoningTokens: thoughtsTokenCount,
            cachedInputTokens: cachedContentTokenCount,
            cacheCreationInputTokens: cacheCreationTokenCount
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

    private func parseJSONObject(_ text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8) else { return nil }
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        if let object = root as? [String: Any] {
            return object
        }
        if let array = root as? [[String: Any]] {
            return array.first
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

private extension DateFormatter {
    static let rfc1123: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter
    }()
}
