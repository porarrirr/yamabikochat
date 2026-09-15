import Foundation
import FoundationModels
import ImageIO

struct PCCCapability: Codable, Sendable, Equatable {
    var version = 1
    var available: Bool
    var reason: String? = nil
    var contextSize: Int? = nil
}

struct PCCNativeRequest: Decodable, Sendable {
    struct Context: Decodable, Sendable {
        var systemPrompt: String?
        var messages: [Message]
    }
    struct Message: Decodable, Sendable {
        var role: String
        var content: JSONValue
    }
    var context: Context
    var reasoningLevel: String
    var temperature: Double?
    var maximumResponseTokens: Int?
}

struct PCCNativeEvent: Encodable, Sendable {
    var type: String
    var runId: String
    var requestId: String
    var text: String? = nil
    var usage: ProviderUsage? = nil
    var message: String? = nil
    var errorCode: String? = nil
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
                        send: @escaping @Sendable (PCCNativeEvent) async throws -> Void) async throws {
        DiagnosticsLogger.log("PCC native request started", category: .network, requestID: requestID)
        defer { DiagnosticsLogger.log("PCC native request finished", category: .network, requestID: requestID) }
        do {
            guard #available(iOS 27.0, *) else { throw PCCFailure(code: "pcc_os_unsupported") }
            let capability = await capability()
            guard capability.available else { throw PCCFailure(code: capability.reason ?? "pcc_unavailable") }
            try await PCCSDK.execute(request, runID: runID, requestID: requestID, send: send)
        } catch is CancellationError {
            DiagnosticsLogger.log("PCC native request cancelled", category: .network, requestID: requestID)
            throw CancellationError()
        } catch {
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
            switch message.role {
            case "user": entries.append(.prompt(.init(segments: try segments(message.content, allowImages: true))))
            case "assistant": entries.append(.response(.init(assetIDs: [], segments: try segments(message.content, allowImages: false))))
            default: throw PCCFailure(code: "pcc_history_unsupported")
            }
        }
        guard context.messages.last?.role == "user" else { throw PCCFailure(code: "pcc_history_unsupported") }
        return Transcript(entries: entries)
    }

    static func execute(_ request: PCCNativeRequest, runID: String, requestID: String,
                        send: @escaping @Sendable (PCCNativeEvent) async throws -> Void) async throws {
        let reasoning: ContextOptions.ReasoningLevel
        switch request.reasoningLevel {
        case "light": reasoning = .light
        case "moderate": reasoning = .moderate
        case "deep": reasoning = .deep
        default: throw PCCFailure(code: "pcc_reasoning_unsupported")
        }
        if let max = request.maximumResponseTokens, max <= 0 { throw PCCFailure(code: "pcc_invalid_output_limit") }
        // Pi supplies the complete history. Remove the last prompt and submit it once.
        let all = try transcript(request.context)
        var entries = Array(all)
        guard case .prompt(var prompt) = entries.removeLast() else { throw PCCFailure(code: "pcc_history_unsupported") }
        prompt.contextOptions = ContextOptions(reasoningLevel: reasoning)
        prompt.options = GenerationOptions(temperature: request.temperature, maximumResponseTokens: request.maximumResponseTokens)
        let session = LanguageModelSession(model: model, transcript: Transcript(entries: entries))
        let prompts: [Prompt] = try prompt.segments.map { segment in
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
        let responseStream = session.streamResponse(to: Prompt(prompts), options: prompt.options,
                                                     contextOptions: prompt.contextOptions)
        var finalText = ""
        var finalUsage: ProviderUsage?
        for try await snapshot in responseStream {
            try Task.checkCancellation()
            finalText = snapshot.content
            finalUsage = usage(snapshot.usage)
            try await send(PCCNativeEvent(type: "snapshot", runId: runID, requestId: requestID,
                                         text: finalText, usage: finalUsage))
        }
        try Task.checkCancellation()
        guard finalUsage != nil else { throw PCCFailure(code: "pcc_empty_stream") }
        try await send(PCCNativeEvent(type: "completed", runId: runID, requestId: requestID,
                                     text: finalText, usage: finalUsage))
    }

    static func usage(_ value: LanguageModelSession.Usage) -> ProviderUsage {
        ProviderUsage(inputTokens: value.input.totalTokenCount, outputTokens: value.output.totalTokenCount,
                      totalTokens: value.totalTokenCount, reasoningTokens: value.output.reasoningTokenCount,
                      cachedInputTokens: value.input.cachedTokenCount)
    }
}
