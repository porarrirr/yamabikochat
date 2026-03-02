import Foundation
import UIKit

struct CodexProviderClient: ProviderClient {
    let provider: LLMProvider = .codexAuth
    private let codexAccessTokenBaseURL = "https://chatgpt.com/backend-api/codex"
    private let originatorHeader = "codex_cli_rs"

    func generate(
        request: ProviderRequest,
        settings: AppSettings,
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol
    ) async throws -> ProviderResponse {
        let auth = try resolvedAuthContext(credentialStore: credentialStore)

        let baseURL = auth.isAPIKey ? settings.resolvedOpenAIBaseURL() : codexAccessTokenBaseURL
        guard let endpoint = URL(string: baseURL)?.appendingPathComponent("responses") else {
            throw ProviderClientError.invalidBaseURL(baseURL)
        }

        let sessionID = request.metadata["codexSessionId"]?.trimmedNonEmpty
        let payload = try buildBody(request: request, stream: false, sessionID: sessionID)
        let userAgent = buildUserAgent(settings: settings, metadata: request.metadata)
        var headers: [String: String] = [
            "Authorization": "Bearer \(auth.token)",
            "Content-Type": "application/json",
            "originator": originatorHeader,
            "User-Agent": userAgent,
            "x-oai-web-search-eligible": "true"
        ]
        if !auth.isAPIKey, let accountID = auth.accountID, !accountID.isEmpty {
            headers["ChatGPT-Account-ID"] = accountID
        }
        if let sessionID {
            headers["session_id"] = sessionID
        }
        let httpRequest = HTTPRequest(
            url: endpoint,
            headers: headers,
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
                    let auth = try resolvedAuthContext(credentialStore: credentialStore)
                    let baseURL = auth.isAPIKey ? settings.resolvedOpenAIBaseURL() : codexAccessTokenBaseURL
                    guard let endpoint = URL(string: baseURL)?.appendingPathComponent("responses") else {
                        throw ProviderClientError.invalidBaseURL(baseURL)
                    }

                    let sessionID = request.metadata["codexSessionId"]?.trimmedNonEmpty
                    let payload = try buildBody(request: request, stream: true, sessionID: sessionID)
                    let userAgent = buildUserAgent(settings: settings, metadata: request.metadata)
                    var headers: [String: String] = [
                        "Authorization": "Bearer \(auth.token)",
                        "Content-Type": "application/json",
                        "originator": originatorHeader,
                        "User-Agent": userAgent,
                        "x-oai-web-search-eligible": "true",
                        "Accept": "text/event-stream"
                    ]
                    if !auth.isAPIKey, let accountID = auth.accountID, !accountID.isEmpty {
                        headers["ChatGPT-Account-ID"] = accountID
                    }
                    if let sessionID {
                        headers["session_id"] = sessionID
                    }
                    let httpRequest = HTTPRequest(
                        url: endpoint,
                        headers: headers,
                        body: payload
                    )

                    let (lineStream, response) = try await httpClient.stream(httpRequest)
                    guard (200 ... 299).contains(response.statusCode) else {
                        throw ProviderClientError.httpStatus(response.statusCode, "Codex stream failed: \(response.statusCode)")
                    }

                    var full = ""
                    var reasoning = ""
                    var latestUsage: ProviderUsage?

                    for try await line in lineStream {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmed.isEmpty || !trimmed.hasPrefix("data:") { continue }

                        let jsonChunk = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                        if let root = try? JSONSerialization.jsonObject(with: Data(jsonChunk.utf8)) as? [String: Any],
                           let usage = parseResponsesUsage(from: root)?.normalizedNonEmpty() {
                            latestUsage = usage
                        }
                        if jsonChunk == "[DONE]" {
                            let completed = ProviderResponse(
                                text: full,
                                reasoningSummary: reasoning.isEmpty ? nil : reasoning,
                                raw: nil,
                                usage: latestUsage
                            )
                            continuation.yield(.completed(completed))
                            continuation.finish()
                            return
                        }

                        if let event = parseStreamChunk(jsonChunk, fullText: &full, fullReasoning: &reasoning) {
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

                    let completed = ProviderResponse(
                        text: full,
                        reasoningSummary: reasoning.isEmpty ? nil : reasoning,
                        raw: nil,
                        usage: latestUsage
                    )
                    continuation.yield(.completed(completed))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func parseStreamChunk(
        _ chunk: String,
        fullText: inout String,
        fullReasoning: inout String
    ) -> ProviderStreamEvent? {
        guard let data = chunk.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let type = root["type"] as? String {
            switch type {
            case "response.output_text.delta":
                if let delta = root["delta"] as? String, !delta.isEmpty {
                    fullText += delta
                    return .textDelta(delta)
                }
            case "response.reasoning_summary_text.delta", "response.reasoning_text.delta", "response.reasoning.delta":
                if let delta = root["delta"] as? String, !delta.isEmpty {
                    fullReasoning += delta
                    return .reasoningDelta(delta)
                }
            case "response.output_item.done":
                if let item = root["item"] as? [String: Any] {
                    let fullItemText = extractOutputTextFromOutputItem(item)
                    let delta = incrementalDelta(current: fullText, incoming: fullItemText)
                    if !delta.isEmpty {
                        fullText += delta
                        return .textDelta(delta)
                    }
                }
            case "response.output_tool_call.delta":
                if let delta = root["delta"] as? String, !delta.isEmpty {
                    return .toolCallDelta(delta)
                }
            case "response.completed":
                return .completed(
                    ProviderResponse(
                        text: fullText,
                        reasoningSummary: fullReasoning.isEmpty ? nil : fullReasoning,
                        raw: nil,
                        usage: parseResponsesUsage(from: root)
                    )
                )
            default:
                break
            }
        }

        if let outputText = root["output_text"] as? String, !outputText.isEmpty {
            fullText += outputText
            return .textDelta(outputText)
        }

        return nil
    }

    private func incrementalDelta(current: String, incoming: String) -> String {
        guard !incoming.isEmpty else { return "" }
        if incoming.count > current.count, incoming.hasPrefix(current) {
            return String(incoming.dropFirst(current.count))
        }
        return incoming
    }

    private func extractOutputTextFromOutputItem(_ item: [String: Any]) -> String {
        guard
            let type = item["type"] as? String, type == "message",
            let role = item["role"] as? String, role == "assistant",
            let content = item["content"] as? [[String: Any]]
        else {
            return ""
        }

        return content
            .compactMap { block -> String? in
                guard let blockType = block["type"] as? String, blockType == "output_text" else {
                    return nil
                }
                return block["text"] as? String
            }
            .joined()
    }

    private struct AuthContext {
        var token: String
        var isAPIKey: Bool
        var accountID: String?
    }

    private func resolvedAuthContext(credentialStore: SecureCredentialStore) throws -> AuthContext {
        let accessToken = try credentialStore.codexAccessToken()
        let apiKey = try credentialStore.credential(for: .codexAuth)
        let accountID = try credentialStore.readSecret(key: "codex_account_id")
        if let apiKey, !apiKey.isEmpty {
            return AuthContext(token: apiKey, isAPIKey: true, accountID: accountID)
        }
        if let accessToken, !accessToken.isEmpty {
            return AuthContext(token: accessToken, isAPIKey: false, accountID: accountID)
        }
        guard let token = accessToken ?? apiKey, !token.isEmpty else {
            throw ProviderClientError.missingCredential(LLMProvider.codexAuth.rawValue)
        }
        return AuthContext(token: token, isAPIKey: false, accountID: accountID)
    }

    private func buildUserAgent(settings: AppSettings, metadata: [String: String]) -> String {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let appID = Bundle.main.bundleIdentifier
        let osVersion = UIDevice.current.systemVersion
        let preset = metadata["codexUserAgentPreset"]?.trimmedNonEmpty ?? settings.codexUserAgentPreset
        return CodexUserAgentPresetCatalog.buildUserAgent(
            originator: originatorHeader,
            cliVersion: CodexUserAgentPresetCatalog.defaultCodexCLIVersion,
            preset: preset,
            mobileOSVersion: osVersion,
            mobileArch: CodexUserAgentPresetCatalog.currentArchitecture(),
            appID: appID,
            appVersion: appVersion
        )
    }

    private func buildBody(request: ProviderRequest, stream: Bool, sessionID: String?) throws -> Data {
        let input = request.messages.map { message -> [String: Any] in
            var text = message.content
            if !message.attachments.isEmpty {
                let attachmentText = message.attachments.map { "- \($0)" }.joined(separator: "\n")
                text += "\n\nAttachments:\n\(attachmentText)"
            }
            let role = message.role == "assistant" ? "assistant" : "user"
            let contentType = role == "assistant" ? "output_text" : "input_text"
            return [
                "type": "message",
                "role": role,
                "content": [[
                    "type": contentType,
                    "text": text
                ]]
            ]
        }

        let effort = request.thinking?.effort?.trimmedNonEmpty
        let summary = request.metadata["codexReasoningSummary"]?.trimmedNonEmpty
        let reasoning: [String: Any]? = {
            var value: [String: Any] = [:]
            if let effort {
                value["effort"] = effort
            }
            if let summary {
                value["summary"] = summary
            }
            return value.isEmpty ? nil : value
        }()

        let include: [String] = reasoning == nil ? [] : ["reasoning.encrypted_content"]
        let tools: [[String: Any]] = {
            guard request.metadata["codexWebSearchEnabled"] == "true" else { return [] }
            var webSearch: [String: Any] = ["type": "web_search"]
            if let size = request.metadata["codexWebSearchContextSize"]?.trimmedNonEmpty {
                webSearch["search_context_size"] = size
            }
            return [webSearch]
        }()

        var root: [String: Any] = [
            "model": normalizedResponsesModel(request.model),
            "input": input,
            "instructions": request.systemPrompt ?? "",
            "tools": tools,
            "tool_choice": "auto",
            "parallel_tool_calls": false,
            "stream": stream,
            "store": false,
            "include": include
        ]
        if let verbosity = request.metadata["codexVerbosity"]?.trimmedNonEmpty {
            root["text"] = ["verbosity": verbosity]
        }
        if let reasoning {
            root["reasoning"] = reasoning
        }
        if let sessionID, !sessionID.isEmpty {
            root["prompt_cache_key"] = sessionID
        }

        return try JSONSerialization.data(withJSONObject: root)
    }

    private func normalizedResponsesModel(_ model: String) -> String {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutLeadingSlash = trimmed.hasPrefix("/") ? String(trimmed.dropFirst()) : trimmed
        let lower = withoutLeadingSlash.lowercased()
        if lower.hasPrefix("openai/") {
            return String(withoutLeadingSlash.dropFirst("openai/".count))
        }
        return withoutLeadingSlash
    }

    private func parseResponse(data: Data) throws -> ProviderResponse {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderClientError.parseFailure("Codex response root is not dictionary")
        }

        if let text = root["output_text"] as? String, !text.isEmpty {
            let summary = extractReasoningSummary(from: root, output: root["output"] as? [[String: Any]])
            return ProviderResponse(
                text: text,
                reasoningSummary: summary,
                raw: String(data: data, encoding: .utf8),
                usage: parseResponsesUsage(from: root)
            )
        }

        if let output = root["output"] as? [[String: Any]] {
            var visibleText = ""
            var reasoningText = ""

            output.forEach { item in
                let type = item["type"] as? String
                if type == "message",
                   let role = item["role"] as? String, role == "assistant",
                   let content = item["content"] as? [[String: Any]] {
                    for block in content {
                        guard let blockType = block["type"] as? String else { continue }
                        let text = (block["text"] as? String) ?? ""
                        if blockType == "output_text" {
                            visibleText += text
                        } else if blockType == "reasoning_text" {
                            reasoningText += text
                        }
                    }
                } else if type == "reasoning",
                          let summary = item["summary"] as? String {
                    reasoningText += summary
                }
            }

            if !visibleText.isEmpty {
                let summary = extractReasoningSummary(from: root, output: output) ?? reasoningText.trimmedNonEmpty
                return ProviderResponse(
                    text: visibleText,
                    reasoningSummary: summary,
                    raw: String(data: data, encoding: .utf8),
                    usage: parseResponsesUsage(from: root)
                )
            }
        }

        throw ProviderClientError.parseFailure("Codex response does not contain output text")
    }

    private func extractReasoningSummary(from root: [String: Any], output: [[String: Any]]?) -> String? {
        if let reasoning = root["reasoning"] as? [String: Any],
           let summary = reasoning["summary"] as? String,
           !summary.isEmpty {
            return summary
        }
        if let summary = root["reasoning_summary"] as? String, !summary.isEmpty {
            return summary
        }
        if let output {
            let combined = output.compactMap { item -> String? in
                let type = item["type"] as? String
                if type == "reasoning" {
                    return item["summary"] as? String
                }
                return nil
            }
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            return combined.isEmpty ? nil : combined
        }
        return nil
    }

    private func parseResponsesUsage(from root: [String: Any]) -> ProviderUsage? {
        let usageObject: [String: Any]?
        if let usage = root["usage"] as? [String: Any] {
            usageObject = usage
        } else if let response = root["response"] as? [String: Any] {
            usageObject = response["usage"] as? [String: Any]
        } else {
            usageObject = nil
        }
        guard let usageObject else { return nil }

        let outputDetails = usageObject["output_tokens_details"] as? [String: Any]
        let completionDetails = usageObject["completion_tokens_details"] as? [String: Any]
        let inputDetails = usageObject["input_tokens_details"] as? [String: Any]
        let promptDetails = usageObject["prompt_tokens_details"] as? [String: Any]
        let inputTokens = intValue(usageObject["input_tokens"]) ?? intValue(usageObject["prompt_tokens"])
        let outputTokens = intValue(usageObject["output_tokens"]) ?? intValue(usageObject["completion_tokens"])
        let totalTokens = intValue(usageObject["total_tokens"])
        let reasoningTokens =
            intValue(usageObject["reasoning_tokens"]) ??
            intValue(usageObject["reasoningTokens"]) ??
            intValue(outputDetails?["reasoning_tokens"]) ??
            intValue(outputDetails?["reasoningTokens"]) ??
            intValue(completionDetails?["reasoning_tokens"]) ??
            intValue(completionDetails?["reasoningTokens"])
        let cachedInputTokens =
            intValue(inputDetails?["cached_tokens"]) ??
            intValue(inputDetails?["cachedTokens"]) ??
            intValue(promptDetails?["cached_tokens"]) ??
            intValue(promptDetails?["cachedTokens"]) ??
            intValue(usageObject["cache_read_input_tokens"]) ??
            intValue(usageObject["cacheReadInputTokens"]) ??
            intValue(usageObject["cached_input_tokens"]) ??
            intValue(usageObject["cachedInputTokens"])
        let cacheCreationInputTokens =
            intValue(inputDetails?["cache_creation_tokens"]) ??
            intValue(inputDetails?["cacheCreationTokens"]) ??
            intValue(promptDetails?["cache_creation_tokens"]) ??
            intValue(promptDetails?["cacheCreationTokens"]) ??
            intValue(usageObject["cache_creation_input_tokens"]) ??
            intValue(usageObject["cacheCreationInputTokens"])
        return ProviderUsage(
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            reasoningTokens: reasoningTokens,
            cachedInputTokens: cachedInputTokens,
            cacheCreationInputTokens: cacheCreationInputTokens
        )
        .normalizedNonEmpty()
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
