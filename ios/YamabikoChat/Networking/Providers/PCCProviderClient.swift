import Foundation
import FoundationModels
import ImageIO

struct PCCCapability: Codable, Sendable, Equatable {
    var version = 2
    var available: Bool
    var reason: String? = nil
    var contextSize: Int? = nil
}

struct PCCNativeRequest: Decodable, Sendable {
    struct Context: Decodable, Sendable {
        var systemPrompt: String?
        var messages: [Message]
        var tools: [ToolDefinition]? = nil
    }
    struct Message: Decodable, Sendable, Equatable {
        var role: String
        var content: JSONValue
        var pccTranscript: String? = nil
        var pccContextCompacted: Bool? = nil

        var canonical: Message {
            var copy = self
            if case .string(let text) = content {
                copy.content = .array([.object(["type": .string("text"), "text": .string(text)])])
            }
            // Only `true` changes transcript reconstruction. Treat an omitted
            // flag and an explicit false identically when matching warm history.
            if copy.pccContextCompacted == false {
                copy.pccContextCompacted = nil
            }
            return copy
        }
    }
    struct ToolDefinition: Decodable, Sendable, Equatable {
        var name: String
        var description: String
        var parameters: JSONValue
    }
    var context: Context
    var reasoningLevel: String
    var temperature: Double?
    var maximumResponseTokens: Int?
    var sessionID: String? = nil
    var contextSize: Int? = nil
}

struct PCCNativeEvent: Encodable, Sendable {
    var type: String
    var runId: String
    var requestId: String
    var text: String? = nil
    var usage: ProviderUsage? = nil
    var message: String? = nil
    var errorCode: String? = nil
    var transcript: String? = nil
    var toolCall: ToolCall? = nil
    var toolResult: ToolResult? = nil
    var sessionReused: Bool? = nil
    var contextCompacted: Bool? = nil
}

struct PCCFailure: Error, LocalizedError, Sendable {
    let code: String
    var errorDescription: String? { PCCProviderClient.message(for: code) }
}

enum PCCProviderClient {
    static func message(for reason: String) -> String {
        switch reason {
        case "pcc_os_unsupported": return L10n.text("Private Cloud Compute requires iOS 27 or later.")
        case "pcc_device_not_eligible": return L10n.text("This device is not eligible for Private Cloud Compute.")
        case "pcc_system_not_ready": return L10n.text("Private Cloud Compute is not ready. Check Apple Intelligence settings.")
        case "pcc_quota_limit_reached": return L10n.text("Private Cloud Compute daily usage limit reached.")
        case "pcc_network_failure": return L10n.text("Private Cloud Compute could not connect to the network.")
        case "pcc_service_unavailable": return L10n.text("Private Cloud Compute service is unavailable.")
        case "pcc_attachment_unsupported": return L10n.text("Private Cloud Compute accepts text and supported images only.")
        case "pcc_history_unsupported": return L10n.text("This conversation contains content that Private Cloud Compute cannot accept.")
        case "pcc_reasoning_unsupported": return L10n.text("Unsupported Private Cloud Compute reasoning level.")
        case "pcc_model_unsupported": return L10n.text("Unsupported Apple Intelligence model.")
        case "pcc_context_unavailable": return L10n.text("Private Cloud Compute context size could not be read.")
        default: return L10n.format("Private Cloud Compute is unavailable (%@).", reason)
        }
    }

    static func capability() async -> PCCCapability {
        guard #available(iOS 27.0, *) else { return PCCCapability(available: false, reason: "pcc_os_unsupported") }
        let model = PCCSDK.model
        switch model.availability {
        case .available: break
        case .unavailable(.deviceNotEligible): return PCCCapability(available: false, reason: "pcc_device_not_eligible")
        case .unavailable(.systemNotReady): return PCCCapability(available: false, reason: "pcc_system_not_ready")
        case .unavailable: return PCCCapability(available: false, reason: "pcc_unavailable")
        }
        if model.quotaUsage.isLimitReached { return PCCCapability(available: false, reason: "pcc_quota_limit_reached") }
        do { return PCCCapability(available: true, contextSize: try await model.contextSize) }
        catch {
            DiagnosticsLogger.log("PCC context size unavailable", category: .network, error: error)
            return PCCCapability(available: false, reason: "pcc_context_unavailable")
        }
    }

    static func execute(_ request: PCCNativeRequest, runID: String, requestID: String,
                        executeTool: @escaping @Sendable (ToolCall) async throws -> ToolResult = { _ in throw PCCFailure(code: "pcc_tool_executor_unavailable") },
                        send: @escaping @Sendable (PCCNativeEvent) async throws -> Void) async throws {
        DiagnosticsLogger.log("PCC native request started", category: .network, requestID: requestID)
        defer { DiagnosticsLogger.log("PCC native request finished", category: .network, requestID: requestID) }
        do {
            guard #available(iOS 27.0, *) else { throw PCCFailure(code: "pcc_os_unsupported") }
            let capability = await capability()
            guard capability.available else { throw PCCFailure(code: capability.reason ?? "pcc_unavailable") }
            guard let contextSize = capability.contextSize else { throw PCCFailure(code: "pcc_context_unavailable") }
            var resolvedRequest = request
            resolvedRequest.contextSize = contextSize
            try await PCCSDK.execute(resolvedRequest, runID: runID, requestID: requestID, executeTool: executeTool, send: send)
        } catch is CancellationError {
            DiagnosticsLogger.log("PCC native request cancelled", category: .network, requestID: requestID)
            throw CancellationError()
        } catch {
            if Task.isCancelled { throw CancellationError() }
            let code: String
            if let failure = error as? PCCFailure { code = failure.code }
            else if #available(iOS 27.0, *), let failure = error as? PrivateCloudComputeLanguageModel.Error {
                switch failure {
                case .networkFailure: code = "pcc_network_failure"
                case .quotaLimitReached: code = "pcc_quota_limit_reached"
                case .serviceUnavailable: code = "pcc_service_unavailable"
                @unknown default: code = "pcc_generation_failed"
                }
            } else { code = "pcc_generation_failed" }
            DiagnosticsLogger.log("PCC request failed", category: .network, requestID: requestID,
                                  metadata: ["code": code], error: error)
            try await send(PCCNativeEvent(type: "error", runId: runID, requestId: requestID,
                                         message: (error as? PCCFailure)?.localizedDescription ?? error.localizedDescription,
                                         errorCode: code))
        }
    }
}

@available(iOS 27.0, *)
enum PCCSDK {
    static let model = PrivateCloudComputeLanguageModel()

    static func segments(_ content: JSONValue, allowImages: Bool) throws -> [Transcript.Segment] {
        if case .string(let text) = content { return [.text(.init(content: text))] }
        guard case .array(let blocks) = content else { throw PCCFailure(code: "pcc_history_unsupported") }
        return try blocks.map { block in
            guard case .object(let fields) = block, case .string(let type) = fields["type"] else {
                throw PCCFailure(code: "pcc_history_unsupported")
            }
            if type == "text", case .string(let text) = fields["text"] { return .text(.init(content: text)) }
            guard allowImages, type == "image", case .string(let encoded) = fields["data"],
                  case .string(let mime) = fields["mimeType"], mime.hasPrefix("image/"),
                  let data = Data(base64Encoded: encoded), data.count <= AppConstants.maxAttachmentSizeBytes,
                  let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw PCCFailure(code: "pcc_attachment_unsupported")
            }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let orientation = (properties?[kCGImagePropertyOrientation] as? UInt32).flatMap(CGImagePropertyOrientation.init(rawValue:))
            return .attachment(.init(content: .image(.init(cgImage, orientation: orientation))))
        }
    }

    static func transcript(_ context: PCCNativeRequest.Context) throws -> Transcript {
        var entries: [Transcript.Entry] = []
        if let system = context.systemPrompt, !system.isEmpty {
            entries.append(.instructions(.init(segments: [.text(.init(content: system))], toolDefinitions: [])))
        }
        for message in context.messages {
            if message.role == "assistant", let encoded = message.pccTranscript {
                let native = try JSONDecoder().decode(Transcript.self, from: Data(encoded.utf8))
                guard native.allSatisfy({ entry in
                    switch entry {
                    case .response, .reasoning, .toolCalls, .toolOutput: return true
                    default: return false
                    }
                }) else { throw PCCFailure(code: "pcc_history_unsupported") }
                if message.pccContextCompacted == true {
                    entries.removeAll { entry in
                        if case .instructions = entry { return false }
                        return true
                    }
                }
                entries.append(contentsOf: native)
                continue
            }
            switch message.role {
            case "user": entries.append(.prompt(.init(segments: try segments(message.content, allowImages: true))))
            case "assistant": entries.append(.response(.init(assetIDs: [], segments: try segments(message.content, allowImages: false))))
            default: throw PCCFailure(code: "pcc_history_unsupported")
            }
        }
        guard context.messages.last?.role == "user" else { throw PCCFailure(code: "pcc_history_unsupported") }
        return Transcript(entries: entries)
    }

    @MainActor
    static func execute(_ request: PCCNativeRequest, runID: String, requestID: String,
                        executeTool: @escaping @Sendable (ToolCall) async throws -> ToolResult = { _ in throw PCCFailure(code: "pcc_tool_executor_unavailable") },
                        send: @escaping @Sendable (PCCNativeEvent) async throws -> Void) async throws {
        try await execute(request, runID: runID, requestID: requestID, using: model, executeTool: executeTool, send: send)
    }

    @MainActor
    static func execute(_ request: PCCNativeRequest, runID: String, requestID: String,
                        using model: some LanguageModel,
                        store: PCCSessionStore = .shared,
                        executeTool: @escaping @Sendable (ToolCall) async throws -> ToolResult,
                        send: @escaping @Sendable (PCCNativeEvent) async throws -> Void) async throws {
        let reasoning: ContextOptions.ReasoningLevel
        switch request.reasoningLevel {
        case "light": reasoning = .light
        case "moderate": reasoning = .moderate
        case "deep": reasoning = .deep
        default: throw PCCFailure(code: "pcc_reasoning_unsupported")
        }
        if let max = request.maximumResponseTokens, max <= 0 { throw PCCFailure(code: "pcc_invalid_output_limit") }
        guard let last = request.context.messages.last, last.role == "user" else { throw PCCFailure(code: "pcc_history_unsupported") }
        let definitions = (request.context.tools ?? []).sorted { $0.name < $1.name }
        guard let contextSize = request.contextSize, contextSize > 0 else {
            throw PCCFailure(code: "pcc_context_unavailable")
        }
        let signature = PCCSessionStore.Signature(modelType: String(reflecting: type(of: model)),
            modelConfiguration: AnyHashable(model.executorConfiguration), instructions: request.context.systemPrompt ?? "",
            tools: definitions, reasoning: request.reasoningLevel, temperature: request.temperature,
            maximumResponseTokens: request.maximumResponseTokens)
        let lease = try store.acquire(key: request.sessionID, signature: signature,
                                      history: Array(request.context.messages.dropLast())) {
            // Only a cold/reset session reconstructs history. A warm session is
            // left untouched, retaining the SDK's native prefix and KV cache.
            let entries = try transcript(request.context).dropLast().filter { entry in
                if case .instructions = entry { return false }
                return true
            }
            let router = PCCToolRouter()
            let nativeTools = try definitions.map { definition in
                try PCCNativeTool(definition: definition) { call in try await router.call(call) }
            }
            let recorder = PCCContextCompactionRecorder()
            let profile = LanguageModelSession.Profile {
                if let instructions = request.context.systemPrompt, !instructions.isEmpty {
                    Instructions(instructions)
                }
                nativeTools
            }
            .model(model)
            .temperature(request.temperature)
            .maximumResponseTokens(request.maximumResponseTokens)
            .reasoningLevel(reasoning)
            .modifier(PCCContextCompactionModifier(model: model, contextSize: contextSize, recorder: recorder))
            return PCCSessionStore.Entry(session: LanguageModelSession(profile: profile, history: entries),
                                         compactionRecorder: recorder,
                                         router: router, signature: signature)
        }
        var completedHistory: [PCCNativeRequest.Message]?
        defer { store.release(lease, completedHistory: completedHistory) }
        lease.entry.router.configure { call in
            try await send(PCCNativeEvent(type: "tool_start", runId: runID, requestId: requestID, toolCall: call))
            let result = try await executeTool(call)
            try Task.checkCancellation()
            try await send(PCCNativeEvent(type: "tool_end", runId: runID, requestId: requestID, toolCall: call, toolResult: result))
            return result
        }
        let session = lease.entry.session
        let startCount = session.transcript.count
        let initialUsage = session.usage
        let responseStream = session.streamResponse(to: Prompt(try prompts(segments(last.content, allowImages: true))),
            options: GenerationOptions(temperature: request.temperature, maximumResponseTokens: request.maximumResponseTokens),
            contextOptions: ContextOptions(reasoningLevel: reasoning))
        var receivedSnapshot = false
        for try await snapshot in responseStream {
            try Task.checkCancellation()
            receivedSnapshot = true
            try await send(PCCNativeEvent(type: "snapshot", runId: runID, requestId: requestID,
                text: responseText(snapshot.transcriptEntries), usage: try usageDelta(session.usage, since: initialUsage)))
        }
        try Task.checkCancellation()
        guard receivedSnapshot else { throw PCCFailure(code: "pcc_empty_stream") }
        let compactionCount = await lease.entry.compactionRecorder.count
        let generatedEntries: [Transcript.Entry]
        if compactionCount > 0 {
            generatedEntries = session.transcript.filter { entry in
                if case .instructions = entry { return false }
                if case .prompt = entry { return false }
                return true
            }
        } else {
            generatedEntries = Array(session.transcript.dropFirst(startCount + 1))
        }
        let generated = Transcript(entries: generatedEntries)
        let encoded = String(decoding: try JSONEncoder().encode(generated), as: UTF8.self)
        let finalText = visibleResponseText(generatedEntries)
        let finalUsage = addUsage(try usageDelta(session.usage, since: initialUsage),
                                  await lease.entry.compactionRecorder.usage)
        completedHistory = request.context.messages + [.init(role: "assistant", content: .string(finalText),
                                                               pccTranscript: encoded,
                                                               pccContextCompacted: compactionCount > 0)]
        DiagnosticsLogger.log("PCC session cache usage", category: .network, requestID: requestID,
            metadata: ["sessionReused": String(lease.reused), "inputTokens": String(finalUsage.inputTokens ?? 0),
                       "cachedInputTokens": String(finalUsage.cachedInputTokens ?? 0)])
        try await send(PCCNativeEvent(type: "completed", runId: runID, requestId: requestID,
            text: finalText, usage: finalUsage, transcript: encoded, sessionReused: lease.reused,
            contextCompacted: compactionCount > 0))
    }

    static func usageDelta(_ value: LanguageModelSession.Usage, since baseline: LanguageModelSession.Usage) throws -> ProviderUsage {
        let input = value.input.totalTokenCount - baseline.input.totalTokenCount
        let cached = value.input.cachedTokenCount - baseline.input.cachedTokenCount
        let output = value.output.totalTokenCount - baseline.output.totalTokenCount
        let reasoning = value.output.reasoningTokenCount - baseline.output.reasoningTokenCount
        guard input >= 0, cached >= 0, cached <= input, output >= 0, reasoning >= 0, reasoning <= output else {
            throw PCCFailure(code: "pcc_invalid_usage")
        }
        return ProviderUsage(inputTokens: input, outputTokens: output, totalTokens: input + output,
                             reasoningTokens: reasoning, cachedInputTokens: cached)
    }

    static func prompts(_ segments: [Transcript.Segment]) throws -> [Prompt] {
        try segments.map { segment in
            switch segment {
            case .text(let text): return Prompt(text.content)
            case .attachment(let attachment):
                switch attachment.content {
                case .image(let image): return Prompt(Attachment(image.cgImage, orientation: image.orientation))
                @unknown default: throw PCCFailure(code: "pcc_attachment_unsupported")
                }
            default: throw PCCFailure(code: "pcc_history_unsupported")
            }
        }
    }

    static func responseText(_ entries: some Sequence<Transcript.Entry>) -> String {
        entries.compactMap { entry -> String? in
            guard case .response(let response) = entry else { return nil }
            return response.segments.compactMap { if case .text(let text) = $0 { return text.content }; return nil }.joined()
        }.joined()
    }

    /// A compacted transcript contains an internal memory response before the
    /// retained tool exchange. Only responses after the last tool output are
    /// user-visible output for the current turn.
    static func visibleResponseText(_ entries: [Transcript.Entry]) -> String {
        guard let boundary = entries.lastIndex(where: { if case .toolOutput = $0 { return true }; return false }) else {
            return responseText(entries)
        }
        return responseText(entries[entries.index(after: boundary)...])
    }

    static func usage(_ value: LanguageModelSession.Usage) -> ProviderUsage {
        ProviderUsage(inputTokens: value.input.totalTokenCount, outputTokens: value.output.totalTokenCount,
                      totalTokens: value.totalTokenCount, reasoningTokens: value.output.reasoningTokenCount,
                      cachedInputTokens: value.input.cachedTokenCount)
    }

    static func addUsage(_ lhs: ProviderUsage, _ rhs: ProviderUsage) -> ProviderUsage {
        func add(_ first: Int?, _ second: Int?) -> Int? {
            guard let first, let second else { return nil }
            return first + second
        }
        return ProviderUsage(inputTokens: add(lhs.inputTokens, rhs.inputTokens),
                             outputTokens: add(lhs.outputTokens, rhs.outputTokens),
                             totalTokens: add(lhs.totalTokens, rhs.totalTokens),
                             reasoningTokens: add(lhs.reasoningTokens, rhs.reasoningTokens),
                             cachedInputTokens: add(lhs.cachedInputTokens, rhs.cachedInputTokens),
                             cacheCreationInputTokens: add(lhs.cacheCreationInputTokens, rhs.cacheCreationInputTokens))
    }
}
