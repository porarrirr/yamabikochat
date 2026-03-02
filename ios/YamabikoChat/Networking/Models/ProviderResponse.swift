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
}

enum ProviderStreamEvent: Sendable, Equatable {
    case textDelta(String)
    case reasoningDelta(String)
    case toolCallDelta(String)
    case completed(ProviderResponse)
}
