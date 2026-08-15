import Foundation
import FoundationModels

struct AppleIntelligenceProviderClient {
    func generate(request: ProviderRequest) async throws -> ProviderResponse {
        guard #available(iOS 26.0, *) else {
            throw ProviderClientError.parseFailure("Apple Intelligence requires iOS 26 or later.")
        }

        let response = try await AppleIntelligenceSession.generate(request: request)
        return ProviderResponse(text: response)
    }

    func stream(request: ProviderRequest) -> AsyncThrowingStream<ProviderStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard #available(iOS 26.0, *) else {
                        throw ProviderClientError.parseFailure("Apple Intelligence requires iOS 26 or later.")
                    }

                    var accumulated = ""
                    let stream = try AppleIntelligenceSession.stream(request: request)
                    for try await snapshot in stream {
                        let content = snapshot.content
                        guard content.count > accumulated.count else { continue }
                        let delta = String(content.dropFirst(accumulated.count))
                        accumulated = content
                        if !delta.isEmpty {
                            continuation.yield(.textDelta(delta))
                        }
                    }
                    continuation.yield(.completed(ProviderResponse(text: accumulated)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

@available(iOS 26.0, *)
private enum AppleIntelligenceSession {
    static func generate(request: ProviderRequest) async throws -> String {
        let session = try makeSession(request: request)
        let response = try await session.respond(
            to: prompt(from: request),
            options: generationOptions(from: request)
        )
        return response.content
    }

    static func stream(request: ProviderRequest) throws -> LanguageModelSession.ResponseStream<String> {
        let session = try makeSession(request: request)
        return session.streamResponse(
            to: prompt(from: request),
            options: generationOptions(from: request)
        )
    }

    private static func makeSession(request: ProviderRequest) throws -> LanguageModelSession {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            return LanguageModelSession(model: model, instructions: request.systemPrompt)
        case let .unavailable(reason):
            throw ProviderClientError.parseFailure(unavailableMessage(for: reason))
        }
    }

    private static func prompt(from request: ProviderRequest) -> String {
        request.messages
            .map { message in
                if !message.attachments.isEmpty {
                    DiagnosticsLogger.log(
                        "Apple Intelligence does not accept attachments",
                        category: .network,
                        metadata: ["attachment_count": String(message.attachments.count)]
                    )
                }
                let role = roleLabel(message.role)
                return "\(role):\n\(message.content)"
            }
            .joined(separator: "\n\n")
    }

    private static func roleLabel(_ role: String) -> String {
        switch role.lowercased() {
        case "assistant", "model":
            return "Assistant"
        case "system":
            return "System"
        default:
            return "User"
        }
    }

    private static func generationOptions(from request: ProviderRequest) -> GenerationOptions {
        let maxTokens = Int(request.metadata["max_output_tokens"] ?? "")
        return GenerationOptions(maximumResponseTokens: maxTokens)
    }

    private static func unavailableMessage(for reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence is not enabled on this device."
        case .deviceNotEligible:
            return "This device does not support Apple Intelligence."
        case .modelNotReady:
            return "Apple Intelligence model is not ready yet. It may still be downloading."
        @unknown default:
            return "Apple Intelligence is unavailable."
        }
    }
}
