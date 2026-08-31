import Foundation

struct ProviderUsage: Codable, Sendable, Equatable {
    var inputTokens: Int? = nil
    var outputTokens: Int? = nil
    var totalTokens: Int? = nil
    var reasoningTokens: Int? = nil
    var cachedInputTokens: Int? = nil
    var cacheCreationInputTokens: Int? = nil
    var contextTokens: Int? = nil
    var contextWindow: Int? = nil

    var isEmpty: Bool {
        let input = max(0, inputTokens ?? 0)
        let output = max(0, outputTokens ?? 0)
        let total = max(0, totalTokens ?? 0)
        return input <= 0 && output <= 0 && total <= 0
    }

    func normalized() -> ProviderUsage {
        let input = max(0, inputTokens ?? 0)
        let output = max(0, outputTokens ?? 0)
        let totalBase = totalTokens ?? (input + output)
        let total = max(max(0, totalBase), input + output)
        return ProviderUsage(
            inputTokens: input,
            outputTokens: output,
            totalTokens: total,
            reasoningTokens: reasoningTokens.map { max(0, $0) },
            cachedInputTokens: cachedInputTokens.map { max(0, $0) },
            cacheCreationInputTokens: cacheCreationInputTokens.map { max(0, $0) },
            contextTokens: contextTokens.map { max(0, $0) },
            contextWindow: contextWindow.flatMap { $0 > 0 ? $0 : nil }
        )
    }

    func normalizedNonEmpty() -> ProviderUsage? {
        let normalized = normalized()
        return normalized.isEmpty ? nil : normalized
    }
}

struct ProviderResponse: Codable, Sendable, Equatable {
    var text: String
    var reasoningSummary: String?
    var raw: String?
    var usage: ProviderUsage?
    var usageSamples: [ProviderUsage]? = nil
    var toolCalls: [ToolCall] = []
    /// Exact replayable assistant/tool messages emitted by Pi during this run.
    var providerTranscript: [ProviderRequestMessage]? = nil
    var toolActivity: ToolActivityPayload? = nil
    /// Exact Pi Agent execution snapshot returned by the bundled runtime.
    /// Authentication material is excluded by the runtime before serialization.
    var piExecution: JSONValue? = nil
}

struct ProviderRotationNotice: Codable, Sendable, Equatable, Identifiable {
    enum Reason: String, Codable, Sendable {
        case rateLimited
        case authenticationFailed
    }

    var id: String
    var provider: String
    var fromModel: String
    var toModel: String
    /// Stable credential slot identifiers only. API key values must never enter this payload.
    var fromKeyID: String
    var toKeyID: String
    var reason: Reason
    var createdAtMs: Int64

    var changedModel: Bool { fromModel != toModel }
    var changedKey: Bool { fromKeyID != toKeyID }
}

extension ProviderUsage {
    func adding(_ other: ProviderUsage?) -> ProviderUsage {
        guard let other else { return self }

        func sum(_ lhs: Int?, _ rhs: Int?) -> Int? {
            guard lhs != nil || rhs != nil else { return nil }
            return max(0, lhs ?? 0) + max(0, rhs ?? 0)
        }

        return ProviderUsage(
            inputTokens: sum(inputTokens, other.inputTokens),
            outputTokens: sum(outputTokens, other.outputTokens),
            totalTokens: sum(totalTokens, other.totalTokens),
            reasoningTokens: sum(reasoningTokens, other.reasoningTokens),
            cachedInputTokens: sum(cachedInputTokens, other.cachedInputTokens),
            cacheCreationInputTokens: sum(cacheCreationInputTokens, other.cacheCreationInputTokens),
            contextTokens: other.contextTokens ?? contextTokens,
            contextWindow: other.contextWindow ?? contextWindow
        )
    }
}

enum ProviderStreamEvent: Sendable, Equatable {
    /// A new Pi assistant turn is starting. Text emitted by an earlier turn may
    /// have accompanied a tool call and must not be carried into the final answer.
    case answerStart
    case textDelta(String)
    case reasoningDelta(String)
    case toolActivity(ToolActivityEvent)
    case rotation(ProviderRotationNotice)
    case executionSnapshot(JSONValue)
    case completed(ProviderResponse)
}

extension ProviderStreamEvent {
    /// True when the event carries non-whitespace assistant answer text (not reasoning).
    /// Used by `ProviderGateway` for non-streaming retry; reasoning-only streams still retry.
    var includesNonEmptyAnswerText: Bool {
        switch self {
        case .answerStart:
            return false
        case let .textDelta(delta):
            return delta.trimmedNonEmpty != nil
        case let .completed(response):
            return response.text.trimmedNonEmpty != nil
        case .reasoningDelta, .toolActivity, .rotation, .executionSnapshot:
            return false
        }
    }
}
