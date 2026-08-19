import Foundation
import UniformTypeIdentifiers
import UIKit

private final class PiRuntimeBundleToken: NSObject {}

struct PiAgentConfiguration: Codable, Sendable {
    var contractVersion: Int = 2
    var provider: String
    var model: String
    var apiKey: String?
    var headers: [String: String] = [:]
    var env: [String: String] = [:]
    var catalogContract: PiCatalogModelContract? = nil
    var thinkingLevel: String?
    var mcpAuthorizationToken: String? = nil
}

struct PiCatalogModelContract: Codable, Sendable {
    var npm: String?
    var api: String?
    var shape: String?
    var toolCall: Bool?
}

struct PiModelResolution: Codable, Equatable, Sendable {
    var supported: Bool
    var reason: String?
    var provider: String?
    var model: String?
    var api: String?
    var source: String?
    var reasoning: Bool?
    var input: [String]?
    var contextWindow: Int?
    var maxTokens: Int?
    var toolCall: Bool?
    var message: String?
}

private struct PiModelResolutionEnvelope: Codable {
    var models: [PiAgentConfiguration]
}

private struct PiModelResolutionResponse: Codable {
    var contractVersion: Int
    var models: [PiModelResolution]
}

private struct PiHealthResponse: Decodable {
    var ok: Bool
    var contractVersion: Int
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
    var runId: String?
    var stage: String?
    var delta: String?
    var message: String?
    var metadata: [String: String]?
    var requestId: String?
    var toolCallId: String?
    var stepId: Int?
    var timeMs: Int64?
    var succeeded: Bool?
    var usage: ProviderUsage?
    var name: String?
    var arguments: JSONValue?
    var response: ProviderResponse?
    var url: String?
    var userCode: String?
    var verificationUri: String?
    var credential: JSONValue?
    var profile: PiOAuthProfile?
}

struct PiConversationMetricsCollector {
    private struct OpenLLMStep {
        var startedAtMs: Int64
        var firstTokenAtMs: Int64?
    }

    private let context: ProviderMetricsContext?
    private var openLLMSteps: [Int: OpenLLMStep] = [:]
    private var activeStepID: Int?
    private var openTools: [String: Int64] = [:]

    init(context: ProviderMetricsContext?) {
        self.context = context
    }

    mutating func startLLM(stepID: Int, at timeMs: Int64) {
        openLLMSteps[stepID] = OpenLLMStep(startedAtMs: timeMs, firstTokenAtMs: nil)
        activeStepID = stepID
    }

    mutating func observeToken(at timeMs: Int64) {
        guard let stepID = activeStepID, openLLMSteps[stepID]?.firstTokenAtMs == nil else { return }
        openLLMSteps[stepID]?.firstTokenAtMs = timeMs
    }

    mutating func endLLM(stepID: Int, at timeMs: Int64, succeeded: Bool, usage: ProviderUsage?) {
        guard let open = openLLMSteps.removeValue(forKey: stepID) else { return }
        if activeStepID == stepID { activeStepID = nil }
        guard let context else { return }
        let normalized = usage?.normalized()
        context.recorder(
            ConversationExecutionMetric(
                conversationId: context.conversationId,
                turnId: context.turnId,
                kind: .llm,
                startedAtMs: open.startedAtMs,
                firstTokenAtMs: open.firstTokenAtMs,
                completedAtMs: timeMs,
                succeeded: succeeded,
                inputTokens: normalized?.inputTokens,
                outputTokens: normalized?.outputTokens,
                cachedInputTokens: normalized?.cachedInputTokens,
                cacheCreationInputTokens: normalized?.cacheCreationInputTokens
            )
        )
    }

    mutating func closeInterruptedLLMSteps(at timeMs: Int64) {
        for stepID in openLLMSteps.keys.sorted() {
            endLLM(stepID: stepID, at: timeMs, succeeded: false, usage: nil)
        }
    }

    mutating func startTool(callID: String, at timeMs: Int64) {
        openTools[callID] = timeMs
    }

    mutating func endTool(callID: String, at timeMs: Int64, succeeded: Bool) {
        guard let startedAtMs = openTools.removeValue(forKey: callID), let context else { return }
        context.recorder(
            ConversationExecutionMetric(
                conversationId: context.conversationId,
                turnId: context.turnId,
                kind: .tool,
                startedAtMs: startedAtMs,
                firstTokenAtMs: nil,
                completedAtMs: timeMs,
                succeeded: succeeded,
                inputTokens: nil,
                outputTokens: nil,
                cachedInputTokens: nil,
                cacheCreationInputTokens: nil
            )
        )
    }
}

enum PiOAuthProvider: String, Codable, Sendable {
    case codex
    case supergrok
}

enum PiOAuthLoginMethod: String, Codable, Sendable {
    case browser
    case device
}

struct PiOAuthProfile: Codable, Equatable, Sendable {
    var email: String?
    var planType: String?
    var accountId: String?
}

struct PiOAuthResolution: Codable, Equatable, Sendable {
    var credential: JSONValue
    var accessToken: String
    var accountId: String?
    var profile: PiOAuthProfile
}

private struct PiOAuthLoginRequest: Encodable {
    var provider: PiOAuthProvider
    var method: PiOAuthLoginMethod
}

private struct PiOAuthResolveRequest: Encodable {
    var provider: PiOAuthProvider
    var credential: JSONValue
    var force: Bool
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

    func resolveModels(_ configurations: [PiAgentConfiguration]) async throws -> [PiModelResolution] {
        let (endpoint, token) = try await startIfNeeded()
        var request = URLRequest(url: endpoint.appendingPathComponent("v1/models/resolve"))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(PiModelResolutionEnvelope(models: configurations))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ProviderClientError.invalidResponse }
        let resolved = try JSONDecoder().decode(PiModelResolutionResponse.self, from: data)
        guard resolved.contractVersion == 2 else {
            throw ProviderClientError.parseFailure("Pi runtime contract mismatch")
        }
        for model in resolved.models {
            DiagnosticsLogger.log(
                "Pi model contract resolved",
                category: .network,
                metadata: [
                    "contractVersion": String(resolved.contractVersion),
                    "supported": String(model.supported),
                    "provider": model.provider ?? "unknown",
                    "model": model.model ?? "unknown",
                    "api": model.api ?? "none",
                    "source": model.source ?? "none",
                    "reason": model.reason ?? "none"
                ]
            )
        }
        return resolved.models
    }

    func loginOAuth(
        provider: PiOAuthProvider,
        method: PiOAuthLoginMethod,
        onDeviceCode: (@Sendable (SuperGrokDeviceCodeChallenge) async -> Void)? = nil
    ) async throws -> PiOAuthResolution {
        let (endpoint, token) = try await startIfNeeded()
        var request = URLRequest(url: endpoint.appendingPathComponent("v1/auth/login"))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(PiOAuthLoginRequest(provider: provider, method: method))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let backgroundTask = await MainActor.run {
            UIApplication.shared.beginBackgroundTask(withName: "PiOAuthLogin")
        }
        defer {
            Task { @MainActor in
                if backgroundTask != .invalid {
                    UIApplication.shared.endBackgroundTask(backgroundTask)
                }
            }
        }

        let (bytes, response) = try await URLSession(configuration: .ephemeral).bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ProviderClientError.invalidResponse
        }
        for try await line in bytes.lines where !line.isEmpty {
            let event = try JSONDecoder().decode(PiRuntimeEvent.self, from: Data(line.utf8))
            switch event.type {
            case "auth_url":
                guard let value = event.url, let url = URL(string: value) else {
                    throw ProviderClientError.parseFailure("Pi OAuth returned an invalid authorization URL")
                }
                try await Self.openBrowser(url)
            case "device_code":
                guard let value = event.verificationUri,
                      let url = URL(string: value),
                      let userCode = event.userCode else {
                    throw ProviderClientError.parseFailure("Pi OAuth returned an invalid device code")
                }
                await onDeviceCode?(
                    SuperGrokDeviceCodeChallenge(
                        verificationURI: value,
                        userCode: userCode,
                        browserURL: value
                    )
                )
                try await Self.openBrowser(url)
            case "auth_completed":
                guard let credential = event.credential, let profile = event.profile else {
                    throw ProviderClientError.parseFailure("Pi OAuth completed without credentials")
                }
                let object = credential.objectValue
                guard let accessToken = object?["access"]?.stringValue else {
                    throw ProviderClientError.parseFailure("Pi OAuth credential has no access token")
                }
                return PiOAuthResolution(
                    credential: credential,
                    accessToken: accessToken,
                    accountId: object?["accountId"]?.stringValue ?? profile.accountId,
                    profile: profile
                )
            case "error":
                throw ProviderClientError.parseFailure(event.message ?? "Pi OAuth login failed")
            default:
                continue
            }
        }
        throw ProviderClientError.parseFailure("Pi OAuth login ended without credentials")
    }

    func resolveOAuth(
        provider: PiOAuthProvider,
        credentialJSON: String,
        force: Bool
    ) async throws -> PiOAuthResolution {
        let (endpoint, token) = try await startIfNeeded()
        let credential = try JSONDecoder().decode(JSONValue.self, from: Data(credentialJSON.utf8))
        let envelope = PiOAuthResolveRequest(provider: provider, credential: credential, force: force)
        var request = URLRequest(url: endpoint.appendingPathComponent("v1/auth/resolve"))
        request.httpMethod = "POST"
        request.httpBody = try JSONEncoder().encode(envelope)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let message = (try? JSONDecoder().decode([String: String].self, from: data)["error"])
                ?? "Pi OAuth refresh failed"
            throw ProviderClientError.parseFailure(message)
        }
        return try JSONDecoder().decode(PiOAuthResolution.self, from: data)
    }

    func stream(
        request: ProviderRequest,
        configuration: PiAgentConfiguration,
        tools: LocalToolRegistry
    ) async throws -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        DiagnosticsLogger.log(
            "Pi runtime stream requested",
            category: .network,
            metadata: [
                "provider": configuration.provider,
                "model": configuration.model,
                "contractVersion": String(configuration.contractVersion)
            ]
        )
        let (endpoint, token) = try await startIfNeeded()
        let runID = UUID().uuidString
        let piRequest = try Self.makeRequest(request)
        let envelope = PiRunEnvelope(runId: runID, request: piRequest, config: configuration)
        let body = try JSONEncoder().encode(envelope)
        let metricsContext = ProviderMetricsContext.current
        var urlRequest = URLRequest(url: endpoint.appendingPathComponent("v1/run"))
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = body
        urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let session = URLSession(configuration: .ephemeral)
        DiagnosticsLogger.log(
            "Pi runtime bridge request starting",
            category: .network,
            requestID: runID,
            metadata: [
                "provider": configuration.provider,
                "model": configuration.model,
                "contractVersion": String(configuration.contractVersion),
                "messages": String(request.messages.count),
                "tools": request.tools.map(\.type).joined(separator: ",")
            ]
        )

        return AsyncThrowingStream { continuation in
            let task = Task {
                var metrics = PiConversationMetricsCollector(context: metricsContext)

                func nowMs() -> Int64 {
                    Int64(Date().timeIntervalSince1970 * 1_000)
                }

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
                        case "diagnostic":
                            DiagnosticsLogger.log(
                                event.message ?? "Pi runtime diagnostic",
                                category: .network,
                                requestID: event.runId ?? runID,
                                metadata: (event.metadata ?? [:]).merging(
                                    ["stage": event.stage ?? "unknown"],
                                    uniquingKeysWith: { current, _ in current }
                                )
                            )
                        case "text_delta":
                            if event.delta?.trimmedNonEmpty != nil { metrics.observeToken(at: event.timeMs ?? nowMs()) }
                            continuation.yield(.textDelta(event.delta ?? ""))
                        case "reasoning_delta":
                            if event.delta?.trimmedNonEmpty != nil { metrics.observeToken(at: event.timeMs ?? nowMs()) }
                            continuation.yield(.reasoningDelta(event.delta ?? ""))
                        case "llm_start":
                            guard let id = event.stepId else {
                                throw ProviderClientError.parseFailure("Pi emitted an invalid LLM start event")
                            }
                            metrics.startLLM(stepID: id, at: event.timeMs ?? nowMs())
                        case "llm_end":
                            guard let id = event.stepId else {
                                throw ProviderClientError.parseFailure("Pi emitted an invalid LLM end event")
                            }
                            metrics.endLLM(
                                stepID: id,
                                at: event.timeMs ?? nowMs(),
                                succeeded: event.succeeded ?? false,
                                usage: event.usage
                            )
                        case "tool_start":
                            guard let callID = event.toolCallId else {
                                throw ProviderClientError.parseFailure("Pi emitted an invalid tool start event")
                            }
                            metrics.startTool(callID: callID, at: event.timeMs ?? nowMs())
                        case "tool_end":
                            guard let callID = event.toolCallId else { break }
                            metrics.endTool(
                                callID: callID,
                                at: event.timeMs ?? nowMs(),
                                succeeded: event.succeeded ?? false
                            )
                        case "tool_request":
                            guard let requestID = event.requestId,
                                  let callID = event.toolCallId,
                                  let name = event.name else {
                                throw ProviderClientError.parseFailure("Pi emitted an invalid tool request")
                            }
                            let arguments = Self.jsonString(event.arguments ?? .object([:]))
                            let call = ToolCall(id: callID, name: name, argumentsJSON: arguments)
                            let createdAtMs = event.timeMs ?? nowMs()
                            let reportsActivity = name == WebSearchTool.name || name == FetchUrlTool.name
                            if reportsActivity {
                                continuation.yield(.toolActivity(ToolActivityEvent(
                                    phase: .started,
                                    call: call,
                                    result: nil,
                                    createdAtMs: createdAtMs
                                )))
                            }
                            let result = await tools.execute(call: call)
                            if reportsActivity {
                                continuation.yield(.toolActivity(ToolActivityEvent(
                                    phase: .finished,
                                    call: call,
                                    result: result,
                                    createdAtMs: createdAtMs
                                )))
                            }
                            try await Self.submitToolResult(result, requestID: requestID, endpoint: endpoint, token: token)
                        case "completed":
                            guard let response = event.response else {
                                throw ProviderClientError.parseFailure("Pi completed without a response")
                            }
                            DiagnosticsLogger.log(
                                "Pi runtime request completed",
                                category: .network,
                                requestID: runID,
                                metadata: [
                                    "provider": configuration.provider,
                                    "model": configuration.model,
                                    "hasText": String(!response.text.isEmpty)
                                ]
                            )
                            continuation.yield(.completed(response))
                        case "error":
                            let error = ProviderClientError.parseFailure(event.message ?? "Pi agent failed")
                            DiagnosticsLogger.log(
                                "Pi runtime reported an error",
                                category: .network,
                                requestID: event.runId ?? runID,
                                metadata: [
                                    "provider": configuration.provider,
                                    "model": configuration.model,
                                    "stage": event.stage ?? "unknown"
                                ],
                                error: error
                            )
                            throw error
                        default:
                            continue
                        }
                    }
                    metrics.closeInterruptedLLMSteps(at: nowMs())
                    continuation.finish()
                } catch is CancellationError {
                    metrics.closeInterruptedLLMSteps(at: nowMs())
                    DiagnosticsLogger.log(
                        "Pi runtime request cancelled",
                        level: .warning,
                        category: .network,
                        requestID: runID,
                        metadata: ["provider": configuration.provider, "model": configuration.model]
                    )
                    await Self.abort(runID: runID, endpoint: endpoint, token: token)
                    continuation.finish(throwing: CancellationError())
                } catch {
                    metrics.closeInterruptedLLMSteps(at: nowMs())
                    DiagnosticsLogger.log(
                        "Pi runtime bridge failed",
                        category: .network,
                        requestID: runID,
                        metadata: ["provider": configuration.provider, "model": configuration.model],
                        error: error
                    )
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    private func startIfNeeded() async throws -> (URL, String) {
        if let endpoint, let token {
            DiagnosticsLogger.log("Pi runtime already ready", category: .network)
            return (endpoint, token)
        }
        if let startupTask {
            DiagnosticsLogger.log("Pi runtime startup already in progress", category: .network)
            return try await startupTask.value
        }

        let task = Task<(URL, String), Error> {
            let resources = Bundle(for: PiRuntimeBundleToken.self)
            guard let script = resources.url(forResource: "main", withExtension: "js") else {
                let error = ProviderClientError.parseFailure("Bundled Pi runtime was not found")
                DiagnosticsLogger.log("Pi runtime bundle lookup failed", category: .network, error: error)
                throw error
            }
            let port = Int.random(in: 49_152 ... 59_999)
            let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
            let endpoint = URL(string: "http://127.0.0.1:\(port)/")!
            DiagnosticsLogger.log(
                "Pi runtime engine starting",
                category: .network,
                metadata: ["script": script.lastPathComponent, "port": String(port)]
            )
            PiNodeRunner.startEngine(withArguments: ["node", script.path, String(port), token])

            var health = URLRequest(url: endpoint.appendingPathComponent("health"))
            health.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            for attempt in 0 ..< 100 {
                try Task.checkCancellation()
                if let (data, response) = try? await URLSession.shared.data(for: health),
                   (response as? HTTPURLResponse)?.statusCode == 200,
                   let status = try? JSONDecoder().decode(PiHealthResponse.self, from: data),
                   status.ok, status.contractVersion == 2 {
                    DiagnosticsLogger.log(
                        "Pi runtime health check succeeded",
                        category: .network,
                        metadata: ["attempt": String(attempt + 1), "port": String(port)]
                    )
                    return (endpoint, token)
                }
                try await Task.sleep(for: .milliseconds(100))
            }
            let error = ProviderClientError.parseFailure("Pi agent runtime did not start")
            DiagnosticsLogger.log(
                "Pi runtime health check timed out",
                category: .network,
                metadata: ["attempts": "100", "port": String(port)],
                error: error
            )
            throw error
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
            DiagnosticsLogger.log("Pi runtime startup failed", category: .network, error: error)
            throw error
        }
    }

    private static func makeRequest(_ request: ProviderRequest) throws -> PiRequest {
        PiRequest(
            messages: try request.messages.map { message in
                PiMessage(
                    role: message.role,
                    content: message.content,
                    attachments: try message.attachments.compactMap(loadImageAttachment),
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
        let url = attachmentFileURL(from: path)
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentTypeKey])
        guard (values.fileSize ?? 0) <= AppConstants.maxAttachmentSizeBytes else {
            throw ProviderClientError.parseFailure("Attachment exceeds the 10 MB limit")
        }
        guard values.contentType?.conforms(to: .image) == true else { return nil }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let type = values.contentType?.preferredMIMEType ?? "image/jpeg"
        return PiAttachment(data: data.base64EncodedString(), mimeType: type)
    }

    /// Resolves the attachment representation persisted in conversation history.
    /// New messages contain filesystem paths, while messages created before the
    /// path-serialization fix contain file URLs.
    static func attachmentFileURL(from value: String) -> URL {
        if let url = URL(string: value), url.isFileURL {
            return url.standardizedFileURL
        }
        return URL(fileURLWithPath: value).standardizedFileURL
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

    static func credentialJSONString(_ value: JSONValue) throws -> String {
        String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
    }

    private static func openBrowser(_ url: URL) async throws {
        let canOpen = await MainActor.run { UIApplication.shared.canOpenURL(url) }
        guard canOpen else { throw ProviderClientError.invalidBaseURL(url.absoluteString) }
        try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                UIApplication.shared.open(url, options: [:]) { opened in
                    if opened {
                        continuation.resume(returning: ())
                    } else {
                        continuation.resume(throwing: ProviderClientError.invalidBaseURL(url.absoluteString))
                    }
                }
            }
        }
    }
}

private extension JSONValue {
    var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }
}
