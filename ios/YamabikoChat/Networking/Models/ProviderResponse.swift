import Foundation

struct ProviderUsage: Codable, Sendable, Equatable {
    var inputTokens: Int? = nil
    var outputTokens: Int? = nil
    var totalTokens: Int? = nil
    var reasoningTokens: Int? = nil
    var cachedInputTokens: Int? = nil
    var cacheCreationInputTokens: Int? = nil

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
            cacheCreationInputTokens: cacheCreationInputTokens.map { max(0, $0) }
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
    var toolCalls: [ToolCall] = []
    var generatedFiles: [ProviderGeneratedFile] = []
    var serverActivities: [ProviderServerActivity] = []
}

struct ProviderGeneratedFile: Codable, Sendable, Equatable, Identifiable {
    var containerID: String
    var fileID: String
    var filename: String
    var localPath: String? = nil
    var id: String { "\(containerID):\(fileID)" }
}

struct ProviderServerActivity: Codable, Sendable, Equatable, Identifiable {
    enum Kind: String, Codable, Sendable { case skill, shell, file }
    var id: String
    var kind: Kind
    var title: String
    var detail: String
    var exitCode: Int? = nil
    var timedOut: Bool? = nil
    var isError: Bool = false
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
            cacheCreationInputTokens: sum(cacheCreationInputTokens, other.cacheCreationInputTokens)
        )
    }
}

enum ProviderStreamEvent: Sendable, Equatable {
    case textDelta(String)
    case reasoningDelta(String)
    case toolCallDelta(ToolCallDelta)
    case serverActivity(ProviderServerActivity)
    case completed(ProviderResponse)
}

extension ProviderStreamEvent {
    /// True when the event carries non-whitespace assistant answer text (not reasoning).
    /// Used by `ProviderGateway` for non-streaming retry; reasoning-only streams still retry.
    var includesNonEmptyAnswerText: Bool {
        switch self {
        case let .textDelta(delta):
            return delta.trimmedNonEmpty != nil
        case let .completed(response):
            return response.text.trimmedNonEmpty != nil
        case .reasoningDelta, .toolCallDelta, .serverActivity:
            return false
        }
    }
}
