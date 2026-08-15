import Foundation
import UniformTypeIdentifiers

private final class PiRuntimeBundleToken: NSObject {}

struct PiAgentConfiguration: Codable, Sendable {
    var provider: String
    var model: String
    var api: String
    var baseURL: String
    var apiKey: String
    var headers: [String: String]
    var reasoning: Bool
    var thinkingLevel: String?
    var supportsImages: Bool
    var contextWindow: Int
    var maxTokens: Int
    var mcpAuthorizationToken: String? = nil
}

private struct PiAttachment: Codable, Sendable {
    var data: String
    var mimeType: String
}

private struct PiMessage: Codable, Sendable {
    var role: String
    var content: String
    var attachments: [PiAttachment]
    var reasoningContent: String?
    var toolCalls: [ToolCall]?
    var toolCallId: String?
    var toolName: String?
    var toolResultIsError: Bool?
}

private struct PiRequest: Codable, Sendable {
    var messages: [PiMessage]
    var systemPrompt: String?
    var tools: [ProviderTool]
    var thinking: ProviderThinkingConfig?
    var provider: ProviderRoutingConfig?
    var metadata: [String: String]
    var timeoutInterval: TimeInterval?
}

private struct PiRunEnvelope: Codable, Sendable {
    var runId: String
    var request: PiRequest
    var config: PiAgentConfiguration
}

private struct PiRuntimeEvent: Decodable {
    var type: String
    var delta: String?
    var message: String?
    var requestId: String?
    var toolCallId: String?
    var name: String?
    var arguments: JSONValue?
    var response: ProviderResponse?
}

private struct PiToolResultEnvelope: Encodable {
    var requestId: String
    var content: String
    var isError: Bool
    var sources: [ToolSource]
}

actor PiAgentRuntime {
    static let shared = PiAgentRuntime()

    private var endpoint: URL?
    private var token: String?
    private var startupTask: Task<(URL, String), Error>?

    func verifyReady() async throws {
        _ = try await startIfNeeded()
    }

    func stream(
        request: ProviderRequest,
        configuration: PiAgentConfiguration,
        tools: LocalToolRegistry
    ) async throws -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        let (endpoint, token) = try await startIfNeeded()
        let runID = UUID().uuidString
        let piRequest = try Self.makeRequest(request, supportsImages: configuration.supportsImages)
        let envelope = PiRunEnvelope(runId: runID, request: piRequest, config: configuration)
        let body = try JSONEncoder().encode(envelope)
        var urlRequest = URLRequest(url: endpoint.appendingPathComponent("v1/run"))
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = body
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let session = URLSession(configuration: .ephemeral)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let (bytes, response) = try await session.bytes(for: urlRequest)
                    guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                        throw ProviderClientError.invalidResponse
                    }
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard !line.isEmpty else { continue }
                        let event = try JSONDecoder().decode(PiRuntimeEvent.self, from: Data(line.utf8))
                        switch event.type {
                        case "text_delta":
                            continuation.yield(.textDelta(event.delta ?? ""))
                        case "reasoning_delta":
                            continuation.yield(.reasoningDelta(event.delta ?? ""))
                        case "tool_request":
                            guard let requestID = event.requestId,
                                  let callID = event.toolCallId,
                                  let name = event.name else {
                                throw ProviderClientError.parseFailure("Pi emitted an invalid tool request")
                            }
                            let arguments = Self.jsonString(event.arguments ?? .object([:]))
                            let result = await tools.execute(call: ToolCall(id: callID, name: name, argumentsJSON: arguments))
                            try await Self.submitToolResult(result, requestID: requestID, endpoint: endpoint, token: token)
                        case "completed":
                            guard let response = event.response else {
                                throw ProviderClientError.parseFailure("Pi completed without a response")
                            }
                            continuation.yield(.completed(response))
                        case "error":
                            throw ProviderClientError.parseFailure(event.message ?? "Pi agent failed")
                        default:
                            continue
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    await Self.abort(runID: runID, endpoint: endpoint, token: token)
                    continuation.finish(throwing: CancellationError())
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func startIfNeeded() async throws -> (URL, String) {
        if let endpoint, let token { return (endpoint, token) }
        if let startupTask { return try await startupTask.value }

        let task = Task<(URL, String), Error> {
            let resources = Bundle(for: PiRuntimeBundleToken.self)
            guard let script = resources.url(forResource: "main", withExtension: "js") else {
                throw ProviderClientError.parseFailure("Bundled Pi runtime was not found")
            }
            let port = Int.random(in: 49_152 ... 59_999)
            let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            let endpoint = URL(string: "http://127.0.0.1:\(port)/")!
            PiNodeRunner.startEngine(withArguments: ["node", script.path, String(port), token])

            var health = URLRequest(url: endpoint.appendingPathComponent("health"))
            health.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            for _ in 0 ..< 100 {
                try Task.checkCancellation()
                if let (_, response) = try? await URLSession.shared.data(for: health),
                   (response as? HTTPURLResponse)?.statusCode == 200 {
                    return (endpoint, token)
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            throw ProviderClientError.parseFailure("Pi agent runtime did not start")
        }
        startupTask = task
        do {
            let result = try await task.value
            endpoint = result.0
            token = result.1
            startupTask = nil
            return result
        } catch {
            startupTask = nil
            throw error
        }
    }

    private static func makeRequest(_ request: ProviderRequest, supportsImages: Bool) throws -> PiRequest {
        PiRequest(
            messages: try request.messages.map { message in
                PiMessage(
                    role: message.role,
                    content: message.content,
                    attachments: supportsImages
                        ? try message.attachments.compactMap(loadImageAttachment)
                        : [],
                    reasoningContent: message.reasoningContent,
                    toolCalls: message.toolCalls,
                    toolCallId: message.toolCallId,
                    toolName: message.toolName,
                    toolResultIsError: message.toolResultIsError
                )
            },
            systemPrompt: request.systemPrompt,
            tools: request.tools,
            thinking: request.thinking,
            provider: request.provider,
            metadata: request.metadata,
            timeoutInterval: request.timeoutInterval
        )
    }

    private static func loadImageAttachment(_ path: String) throws -> PiAttachment? {
        let url = URL(fileURLWithPath: path)
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        guard (values.fileSize ?? 0) <= AppConstants.maxAttachmentSizeBytes else {
            throw ProviderClientError.parseFailure("Attachment exceeds the 10 MB limit")
        }
        guard values.contentType?.conforms(to: .image) == true else { return nil }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let type = values.contentType?.preferredMIMEType ?? "image/jpeg"
        return PiAttachment(data: data.base64EncodedString(), mimeType: type)
    }

    private static func submitToolResult(
        _ result: ToolResult,
        requestID: String,
        endpoint: URL,
        token: String
    ) async throws {
        let envelope = PiToolResultEnvelope(
            requestId: requestID,
            content: result.content,
            isError: result.isError,
            sources: result.sources
        )
        var request = URLRequest(url: endpoint.appendingPathComponent("v1/tool-result"))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(envelope)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (_, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw ProviderClientError.invalidResponse
        }
    }

    private static func abort(runID: String, endpoint: URL, token: String) async {
        var request = URLRequest(url: endpoint.appendingPathComponent("v1/abort"))
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["runId": runID])
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try? await URLSession.shared.data(for: request)
    }

    private static func jsonString(_ value: JSONValue) -> String {
        guard let data = try? JSONEncoder().encode(value),
              let string = String(data: data, encoding: .utf8) else { return "{}" }
        return string
    }
}
