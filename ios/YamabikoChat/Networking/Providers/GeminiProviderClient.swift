import Foundation
import UIKit
import UniformTypeIdentifiers

struct GeminiProviderClient: ProviderClient {
    let provider: LLMProvider = .gemini
    private let geminiApiBase = "https://generativelanguage.googleapis.com/v1beta"
    private let geminiCliBase = "https://cloudcode-pa.googleapis.com/v1internal"
    static let noUsableStreamDataReason = "Gemini stream produced no usable data"

    func generate(
        request: ProviderRequest,
        settings: AppSettings,
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol
    ) async throws -> ProviderResponse {
        let resolvedProvider = LLMProvider(rawOrDefault: request.metadata["provider"] ?? settings.apiProvider)
        switch resolvedProvider {
        case .gemini:
            return try await generateWithAPIKey(request: request, credentialStore: credentialStore, httpClient: httpClient)
        case .geminiAuth:
            return try await generateWithBearerToken(request: request, credentialStore: credentialStore, httpClient: httpClient)
        default:
            throw ProviderClientError.invalidBaseURL("Provider not supported by Gemini client")
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
                    let resolvedProvider = LLMProvider(rawOrDefault: request.metadata["provider"] ?? settings.apiProvider)
                    let credential = try await resolveCredential(provider: resolvedProvider, store: credentialStore)
                    let projectID = try credentialStore.readSecret(key: "gemini_project_id")
                    let endpoint = try streamEndpoint(
                        model: request.model,
                        provider: resolvedProvider,
                        token: credential.token
                    )
                    let body = try buildGeminiBody(
                        request: request,
                        provider: resolvedProvider,
                        projectID: projectID
                    )

                    var headers = ["Content-Type": "application/json"]
                    if credential.isBearer {
                        headers["Authorization"] = "Bearer \(credential.token)"
                    }
                    if resolvedProvider == .geminiAuth {
                        headers["Accept"] = "text/event-stream"
                        headers["User-Agent"] = buildGeminiCliUserAgent(model: request.model)
                    }

                    let httpRequest = HTTPRequest(url: endpoint, headers: headers, body: body)
                    DiagnosticsLogger.log(
                        "Gemini stream start",
                        category: .network,
                        metadata: [
                            "provider": resolvedProvider.rawValue,
                            "model": request.model,
                            "url": endpoint.absoluteString
                        ]
                    )
                    let (lineStream, response) = try await httpClient.stream(httpRequest)
                    guard (200 ... 299).contains(response.statusCode) else {
                        throw ProviderClientError.httpStatus(response.statusCode, "Gemini stream failed: \(response.statusCode)")
                    }

                    var fullText = ""
                    var fullReasoning = ""
                    var latestUsage: ProviderUsage?
                    var hasUsableData = false
                    var eventLines: [String] = []
                    var streamFinished = false
                    var parseErrorCount = 0
                    var totalLineCount = 0
                    var flushCount = 0
                    var singleLineFlushCount = 0
                    var boundaryFlushCount = 0
                    var blankLineFlushCount = 0
                    var eofFlushCount = 0
                    var flushTrace: [String] = []
                    var invalidPayloadSnippets: [String] = []
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
                                "provider": resolvedProvider.rawValue,
                                "model": request.model,
                                "phase": phase,
                                "status": String(response.statusCode),
                                "line_count": String(totalLineCount),
                                "flush_count": String(flushCount),
                                "flush_singleline_count": String(singleLineFlushCount),
                                "flush_boundary_count": String(boundaryFlushCount),
                                "flush_blankline_count": String(blankLineFlushCount),
                                "flush_eof_count": String(eofFlushCount),
                                "flush_trace": flushTrace.joined(separator: " | "),
                                "parse_error_count": String(parseErrorCount),
                                "invalid_payloads": invalidPayloadSnippets.joined(separator: " || ")
                            ]
                        )
                        throw ProviderClientError.parseFailure(Self.noUsableStreamDataReason)
                    }

                    func parseChunk(_ chunk: String) -> ParsedGeminiChunk? {
                        if resolvedProvider == .geminiAuth {
                            return parseGeminiCliStreamChunk(chunk)
                        }
                        return parseGeminiStreamChunk(chunk)
                    }

                    func bufferedChunk() -> String {
                        eventLines
                            .joined(separator: "\n")
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                    }

                    func canFlushBufferedEvent() -> Bool {
                        let chunk = bufferedChunk()
                        guard !chunk.isEmpty else { return false }
                        if chunk == "[DONE]" { return true }
                        return parseChunk(chunk) != nil
                    }

                    func flushEventLines(trigger: String) throws {
                        guard !eventLines.isEmpty, !streamFinished else { return }
                        let chunk = bufferedChunk()
                        eventLines.removeAll(keepingCapacity: true)
                        guard !chunk.isEmpty else { return }
                        flushCount += 1
                        let shape = chunk == "[DONE]" ? "done" : (chunk.contains("\n") ? "multiline" : "singleline")
                        if flushTrace.count < 10 {
                            flushTrace.append("\(trigger):\(shape)")
                        }
                        switch trigger {
                        case "singleline":
                            singleLineFlushCount += 1
                        case "next_data":
                            boundaryFlushCount += 1
                        case "blank_line":
                            blankLineFlushCount += 1
                        case "eof":
                            eofFlushCount += 1
                        default:
                            break
                        }

                        if chunk == "[DONE]" {
                            if !hasUsableData && fullText.isEmpty && fullReasoning.isEmpty {
                                try failNoUsableData("done")
                            }
                            let final = ProviderResponse(
                                text: fullText,
                                reasoningSummary: fullReasoning.trimmedNonEmpty,
                                raw: nil,
                                usage: latestUsage
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
                            fullReasoning += parsed.reasoning
                            hasUsableData = true
                            continuation.yield(.reasoningDelta(parsed.reasoning))
                        }
                        if !parsed.text.isEmpty {
                            fullText += parsed.text
                            hasUsableData = true
                            continuation.yield(.textDelta(parsed.text))
                        }
                    }

                    for try await line in lineStream {
                        if streamFinished { return }
                        totalLineCount += 1
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.hasPrefix(":") {
                            continue
                        }
                        if trimmed.isEmpty {
                            try flushEventLines(trigger: "blank_line")
                            continue
                        }
                        guard trimmed.hasPrefix("data:") else {
                            continue
                        }

                        if canFlushBufferedEvent() {
                            try flushEventLines(trigger: "next_data")
                        }

                        let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        eventLines.append(payload)

                        if eventLines.count == 1, canFlushBufferedEvent() {
                            try flushEventLines(trigger: "singleline")
                        }
                    }

                    if streamFinished { return }
                    try flushEventLines(trigger: "eof")
                    if streamFinished { return }
                    if !hasUsableData && fullText.isEmpty && fullReasoning.isEmpty {
                        try failNoUsableData("eof")
                    }

                    let final = ProviderResponse(
                        text: fullText,
                        reasoningSummary: fullReasoning.trimmedNonEmpty,
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

    private struct ResolvedCredential {
        var token: String
        var isBearer: Bool
    }

    private struct ParsedGeminiParts {
        var text: String
        var reasoning: String
    }

    private struct ParsedGeminiChunk {
        var text: String
        var reasoning: String
        var usage: ProviderUsage?
    }

    private func resolveCredential(provider: LLMProvider, store: SecureCredentialStore) async throws -> ResolvedCredential {
        switch provider {
        case .gemini:
            guard let key = try store.credential(for: .gemini)?.trimmedNonEmpty else {
                throw ProviderClientError.missingCredential(LLMProvider.gemini.rawValue)
            }
            return ResolvedCredential(token: key, isBearer: false)
        case .geminiAuth:
            let token = try (store.geminiAccessToken() ?? store.credential(for: .geminiAuth))?.trimmedNonEmpty
            guard let token else {
                throw ProviderClientError.missingCredential(LLMProvider.geminiAuth.rawValue)
            }
            return ResolvedCredential(token: token, isBearer: true)
        default:
            throw ProviderClientError.invalidBaseURL("Unsupported provider for Gemini")
        }
    }

    private func generateWithAPIKey(
        request: ProviderRequest,
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol
    ) async throws -> ProviderResponse {
        guard let apiKey = try credentialStore.credential(for: .gemini)?.trimmedNonEmpty else {
            throw ProviderClientError.missingCredential(LLMProvider.gemini.rawValue)
        }

        guard let url = nonStreamingEndpoint(model: request.model, provider: .gemini, token: apiKey) else {
            throw ProviderClientError.invalidBaseURL("Gemini endpoint")
        }

        let payload = try buildGeminiBody(request: request, provider: .gemini, projectID: nil)
        let httpRequest = HTTPRequest(
            url: url,
            headers: ["Content-Type": "application/json"],
            body: payload
        )

        let (data, response) = try await httpClient.send(httpRequest)
        guard (200 ... 299).contains(response.statusCode) else {
            throw ProviderClientError.httpStatus(response.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        return try parseResponse(data: data)
    }

    private func generateWithBearerToken(
        request: ProviderRequest,
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol
    ) async throws -> ProviderResponse {
        let accessToken = try (credentialStore.geminiAccessToken() ?? credentialStore.credential(for: .geminiAuth))?.trimmedNonEmpty
        guard let accessToken else {
            throw ProviderClientError.missingCredential(LLMProvider.geminiAuth.rawValue)
        }

        let projectID = try credentialStore.readSecret(key: "gemini_project_id")
        guard let endpoint = nonStreamingEndpoint(model: request.model, provider: .geminiAuth, token: accessToken) else {
            throw ProviderClientError.invalidBaseURL("Gemini endpoint")
        }

        let payload = try buildGeminiBody(request: request, provider: .geminiAuth, projectID: projectID)
        let httpRequest = HTTPRequest(
            url: endpoint,
            headers: [
                "Authorization": "Bearer \(accessToken)",
                "Content-Type": "application/json",
                "User-Agent": buildGeminiCliUserAgent(model: request.model)
            ],
            body: payload
        )

        let (data, response) = try await httpClient.send(httpRequest)
        guard (200 ... 299).contains(response.statusCode) else {
            throw ProviderClientError.httpStatus(response.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        return try parseGeminiCliResponse(data: data)
    }

    private func nonStreamingEndpoint(model: String, provider: LLMProvider, token: String) -> URL? {
        switch provider {
        case .gemini:
            var components = URLComponents(string: "\(geminiApiBase)/models/\(model):generateContent")
            components?.queryItems = [URLQueryItem(name: "key", value: token)]
            return components?.url
        case .geminiAuth:
            return URL(string: "\(geminiCliBase):generateContent")
        default:
            return nil
        }
    }

    private func streamEndpoint(model: String, provider: LLMProvider, token: String) throws -> URL {
        switch provider {
        case .gemini:
            var components = URLComponents(string: "\(geminiApiBase)/models/\(model):streamGenerateContent")
            components?.queryItems = [
                URLQueryItem(name: "alt", value: "sse"),
                URLQueryItem(name: "key", value: token)
            ]
            guard let url = components?.url else { throw ProviderClientError.invalidBaseURL("Gemini streaming endpoint") }
            return url
        case .geminiAuth:
            var components = URLComponents(string: "\(geminiCliBase):streamGenerateContent")
            components?.queryItems = [URLQueryItem(name: "alt", value: "sse")]
            guard let url = components?.url else { throw ProviderClientError.invalidBaseURL("Gemini streaming endpoint") }
            return url
        default:
            throw ProviderClientError.invalidBaseURL("Unsupported provider for Gemini stream")
        }
    }

    private func buildGeminiBody(
        request: ProviderRequest,
        provider: LLMProvider,
        projectID: String?
    ) throws -> Data {
        let contents = request.messages.map { message -> [String: Any] in
            [
                "role": message.role == "assistant" ? "model" : "user",
                "parts": buildGeminiParts(for: message)
            ]
        }

        var generationConfig: [String: Any] = [:]
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

        switch provider {
        case .geminiAuth:
            var inner: [String: Any] = [
                "contents": contents
            ]
            if let systemPrompt = request.systemPrompt, !systemPrompt.isEmpty {
                inner["systemInstruction"] = [
                    "role": "system",
                    "parts": [["text": systemPrompt]]
                ]
            }
            if !tools.isEmpty {
                inner["tools"] = tools
            }
            if let sessionID = request.metadata["geminiSessionId"]?.trimmedNonEmpty {
                inner["session_id"] = sessionID
            }
            if !generationConfig.isEmpty {
                inner["generationConfig"] = generationConfig
            }

            var root: [String: Any] = [
                "model": request.model,
                "user_prompt_id": UUID().uuidString,
                "request": inner
            ]
            if let projectID = projectID?.trimmedNonEmpty {
                root["project"] = projectID
            }
            return try JSONSerialization.data(withJSONObject: root)
        default:
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
            return try JSONSerialization.data(withJSONObject: root)
        }
    }

    private func resolveAttachmentFileURL(_ rawAttachment: String) -> URL? {
        if let parsed = URL(string: rawAttachment), parsed.isFileURL {
            return parsed
        }

        let directPath = URL(fileURLWithPath: rawAttachment)
        if FileManager.default.fileExists(atPath: directPath.path) {
            return directPath
        }

        if let decoded = rawAttachment.removingPercentEncoding {
            let decodedPath = URL(fileURLWithPath: decoded)
            if FileManager.default.fileExists(atPath: decodedPath.path) {
                return decodedPath
            }
        }

        return nil
    }

    private func resolveAttachmentMimeType(fileURL: URL) -> String {
        if let values = try? fileURL.resourceValues(forKeys: [.contentTypeKey]),
           let contentType = values.contentType,
           let mime = contentType.preferredMIMEType,
           !mime.isEmpty {
            return mime
        }

        let ext = fileURL.pathExtension
        if let type = UTType(filenameExtension: ext),
           let mime = type.preferredMIMEType,
           !mime.isEmpty {
            return mime
        }

        return "application/octet-stream"
    }

    private func inlineDataPart(from rawAttachment: String) -> [String: Any]? {
        guard let fileURL = resolveAttachmentFileURL(rawAttachment) else {
            DiagnosticsLogger.log(
                "Gemini attachment skipped: unreadable file URL",
                category: .network,
                metadata: ["attachment": rawAttachment]
            )
            return nil
        }

        do {
            let data = try Data(contentsOf: fileURL)
            let mime = resolveAttachmentMimeType(fileURL: fileURL)
            return [
                "inlineData": [
                    "mimeType": mime,
                    "data": data.base64EncodedString()
                ]
            ]
        } catch {
            DiagnosticsLogger.log(
                "Gemini attachment skipped: file read failed",
                category: .network,
                metadata: [
                    "attachment": rawAttachment,
                    "path": fileURL.path
                ],
                error: error
            )
            return nil
        }
    }

    private func buildGeminiParts(for message: ProviderRequestMessage) -> [[String: Any]] {
        var parts: [[String: Any]] = [["text": message.content]]

        for attachment in message.attachments {
            if let inline = inlineDataPart(from: attachment) {
                parts.append(inline)
            }
        }

        return parts
    }

    private func parseGeminiParts(_ parts: [[String: Any]], payloadText: String? = nil) -> ParsedGeminiParts {
        var text = ""
        var reasoning = ""

        for part in parts {
            guard let value = part["text"] as? String, !value.isEmpty else { continue }
            if (part["thought"] as? Bool) == true {
                reasoning += value
            } else {
                text += value
            }
        }

        if let payloadText, !payloadText.isEmpty {
            text += payloadText
        }

        return ParsedGeminiParts(text: text, reasoning: reasoning)
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
        guard !parsed.text.isEmpty || !parsed.reasoning.isEmpty else {
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
            usage: usage
        )
    }

    private func parseGeminiCliStreamChunk(_ chunk: String) -> ParsedGeminiChunk? {
        guard let root = parseJSONObject(chunk) else { return nil }
        let payload = extractGeminiCliPayload(from: root)
        let parsedParts = parseGeminiPartsFromPayload(payload)
        let usage = parseGeminiUsage(payload: payload)
        if parsedParts == nil, usage == nil {
            return nil
        }
        return ParsedGeminiChunk(
            text: parsedParts?.text ?? "",
            reasoning: parsedParts?.reasoning ?? "",
            usage: usage
        )
    }

    private func parseGeminiCliResponse(data: Data) throws -> ProviderResponse {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderClientError.parseFailure("Gemini Auth response root is invalid")
        }
        let payload = (root["response"] as? [String: Any]) ?? root
        return try parseGeminiResponsePayload(payload: payload, rawData: data)
    }

    private func parseGeminiResponsePayload(payload: [String: Any], rawData: Data) throws -> ProviderResponse {
        guard let parsed = parseGeminiPartsFromPayload(payload) else {
            throw ProviderClientError.parseFailure("Gemini response missing candidates")
        }

        let text = parsed.text
        let reasoning = parsed.reasoning.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty && reasoning.isEmpty {
            throw ProviderClientError.parseFailure("Gemini response text is empty")
        }

        return ProviderResponse(
            text: text,
            reasoningSummary: reasoning.isEmpty ? nil : reasoning,
            raw: String(data: rawData, encoding: .utf8),
            usage: parseGeminiUsage(payload: payload)
        )
    }

    private func geminiToolObjects(from tools: [ProviderTool]) -> [[String: Any]] {
        var mapped: [[String: Any]] = []
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
                    mapped.append(["function_declarations": list])
                }
            default:
                break
            }
        }
        return mapped
    }

    private func buildGeminiCliUserAgent(model: String) -> String {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
        let osVersion = UIDevice.current.systemVersion
        let arch = CodexUserAgentPresetCatalog.currentArchitecture()
        return "GeminiCLI/\(appVersion)/\(model) (Android \(osVersion); \(arch))"
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
        guard let usage = payload["usageMetadata"] as? [String: Any] else {
            return nil
        }
        let promptTokenCount = intValue(usage["promptTokenCount"]) ?? 0
        let candidatesTokenCount = intValue(usage["candidatesTokenCount"]) ?? 0
        let cachedContentTokenCount = intValue(usage["cachedContentTokenCount"])
        let thoughtsTokenCount = intValue(usage["thoughtsTokenCount"])
        let toolUsePromptTokenCount = intValue(usage["toolUsePromptTokenCount"]) ?? 0
        let totalFallback = promptTokenCount + candidatesTokenCount + toolUsePromptTokenCount + max(0, thoughtsTokenCount ?? 0)
        let totalTokenCount = intValue(usage["totalTokenCount"]) ?? totalFallback
        return ProviderUsage(
            inputTokens: promptTokenCount,
            outputTokens: candidatesTokenCount,
            totalTokens: totalTokenCount,
            reasoningTokens: thoughtsTokenCount,
            cachedInputTokens: cachedContentTokenCount
        )
        .normalizedNonEmpty()
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

    private func extractGeminiCliPayload(from root: [String: Any]) -> [String: Any] {
        if let response = root["response"] as? [String: Any] {
            return response
        }
        if let nested = root["result"] as? [String: Any],
           let response = nested["response"] as? [String: Any] {
            return response
        }
        return root
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
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
