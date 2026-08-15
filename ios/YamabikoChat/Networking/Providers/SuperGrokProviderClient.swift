import Foundation

struct SuperGrokProviderClient: ProviderClient {
    let provider: LLMProvider = .superGrok

    private struct RequestBody: Encodable {
        var model: String
        var messages: [OpenAICompatibleWireMessage]
        var stream: Bool
        var tools: [[String: AnyEncodable]]?
        var reasoning: [String: AnyEncodable]?
    }

    func generate(
        request: ProviderRequest,
        settings: AppSettings,
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol
    ) async throws -> ProviderResponse {
        let token = try resolvedAccessToken(credentialStore: credentialStore)
        let endpoint = try endpointURL()
        let route = try route(for: request)
        let payload = try buildBody(request: request, route: route, stream: false)

        let httpRequest = HTTPRequest(
            url: endpoint,
            headers: headers(token: token),
            body: payload,
            timeoutInterval: request.timeoutInterval
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
                    let token = try resolvedAccessToken(credentialStore: credentialStore)
                    let endpoint = try endpointURL()
                    let route = try route(for: request)
                    let payload = try buildBody(request: request, route: route, stream: true)

                    let httpRequest = HTTPRequest(
                        url: endpoint,
                        headers: headers(token: token, stream: true),
                        body: payload,
                        timeoutInterval: request.timeoutInterval
                    )

                    let (lineStream, response) = try await httpClient.stream(httpRequest)
                    guard (200 ... 299).contains(response.statusCode) else {
                        let errorBody = await Self.readStreamErrorBody(lineStream)
                        throw ProviderClientError.httpStatus(response.statusCode, errorBody)
                    }

                    try await ProviderSSEStreamRunner.pump(
                        lineStream: lineStream,
                        continuation: continuation,
                        options: ProviderSSEStreamRunner.Options(
                            usageFromRoot: { root in
                                parseUsage(root["usage"] as? [String: Any])?.normalizedNonEmpty()
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

    private func route(for request: ProviderRequest) throws -> SuperGrokModel {
        if let model = SuperGrokModelCatalog.model(for: request.model) {
            return model
        }
        // Custom model IDs are allowed; catalog is for presets/candidates only.
        let id = SuperGrokModelCatalog.normalizedModelID(request.model)
        guard !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ProviderClientError.invalidBaseURL("SuperGrok model is empty")
        }
        return SuperGrokModel(
            id: id,
            displayName: id,
            supportsVision: false,
            supportsReasoning: true,
            description: "Custom SuperGrok model"
        )
    }

    private func resolvedAccessToken(credentialStore: SecureCredentialStore) throws -> String {
        guard let token = try credentialStore.superGrokAccessToken()?.trimmedNonEmpty else {
            throw ProviderClientError.missingCredential(LLMProvider.superGrok.rawValue)
        }
        return token
    }

    private func endpointURL() throws -> URL {
        AppConstants.defaultSuperGrokBaseURL.appendingPathComponent("chat/completions")
    }

    private func headers(token: String, stream: Bool = false) -> [String: String] {
        var headers = [
            "Authorization": "Bearer \(token)",
            "Content-Type": "application/json",
            "User-Agent": buildUserAgent()
        ]
        if stream {
            headers["Accept"] = "text/event-stream"
        }
        return headers
    }

    private func buildUserAgent() -> String {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        return "YamabikoChat/iOS \(appVersion)"
    }

    private func buildBody(request: ProviderRequest, route: SuperGrokModel, stream: Bool) throws -> Data {
        let embedImages = ProviderAttachmentEncoder.shouldEmbedImages(metadata: request.metadata)
            && route.supportsVision
        let toolsPayload = request.tools.isEmpty ? nil : request.tools.compactMap(openAIToolPayload)
        let reasoningPayload = request.thinking.flatMap { thinking -> [String: AnyEncodable]? in
            guard route.supportsReasoning else { return nil }
            var map: [String: AnyEncodable] = [:]
            if let enabled = thinking.enabled { map["enabled"] = AnyEncodable(enabled) }
            if let budget = thinking.budget { map["max_tokens"] = AnyEncodable(budget) }
            if let effort = thinking.effort { map["effort"] = AnyEncodable(effort) }
            if let exclude = thinking.exclude { map["exclude"] = AnyEncodable(exclude) }
            return map.isEmpty ? nil : map
        }

        let body = RequestBody(
            model: route.id,
            messages: OpenAICompatibleWireMapper.messages(
                request.messages,
                systemPrompt: request.systemPrompt,
                embedImages: embedImages,
                providerLabel: "SuperGrok"
            ),
            stream: stream,
            tools: toolsPayload,
            reasoning: reasoningPayload
        )
        return try JSONEncoder().encode(body)
    }

    private func openAIToolPayload(_ tool: ProviderTool) -> [String: AnyEncodable]? {
        guard tool.type == "function" else { return nil }
        guard let name = tool.payload["name"]?.trimmedNonEmpty,
              let parametersJSON = tool.payload["parameters"]?.trimmedNonEmpty,
              let data = parametersJSON.data(using: .utf8),
              let parameters = try? JSONDecoder().decode(JSONValue.self, from: data)
        else {
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
        guard
            let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let first = choices.first,
            let message = first["message"] as? [String: Any]
        else {
            throw ProviderClientError.parseFailure("SuperGrok response does not contain choices[0].message")
        }

        let content = OpenAICompatibleStreamParser.openAICompatibleText(from: message["content"])
        let reasoningSummary = OpenAICompatibleStreamParser.reasoningText(from: message)
        return ProviderResponse(
            text: content,
            reasoningSummary: reasoningSummary,
            raw: String(data: data, encoding: .utf8),
            usage: parseUsage(root["usage"] as? [String: Any]),
            toolCalls: parseToolCalls(message["tool_calls"])
        )
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
        OpenAICompatibleUsageParser.parse(object)
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
                if total >= maxBytes { break }
            }
        } catch {
            return chunks.joined(separator: "\n")
        }
        return chunks.joined(separator: "\n")
    }
}
