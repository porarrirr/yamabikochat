import Foundation
import GRDB

struct ConversationExecutionMetric: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable, Sendable {
    static let databaseTableName = "conversation_execution_metrics"

    enum Kind: String, Codable, Sendable {
        case llm
        case tool
    }

    var id: Int64?
    var conversationId: Int64
    var turnId: String
    var kind: Kind
    var startedAtMs: Int64
    var firstTokenAtMs: Int64?
    var completedAtMs: Int64
    var succeeded: Bool
    var inputTokens: Int?
    var outputTokens: Int?
    var cachedInputTokens: Int?
    var cacheCreationInputTokens: Int?

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

struct ConversationStats: Equatable, Sendable {
    var turns: Int64 = 0
    var steps: Int64 = 0
    var llmDurationMs: Int64 = 0
    var toolDurationMs: Int64 = 0
    var ttftTotalMs: Int64 = 0
    var ttftSampleCount: Int64 = 0
    var decodeDurationMs: Int64 = 0
    var decodeOutputTokens: Int64 = 0
    var inputTokens: Int64 = 0
    var outputTokens: Int64 = 0
    var cachedInputTokens: Int64 = 0
    var cacheCreationInputTokens: Int64 = 0

    var averageTTFTMs: Double? {
        guard ttftSampleCount > 0 else { return nil }
        return Double(ttftTotalMs) / Double(ttftSampleCount)
    }

    var tokensPerSecond: Double? {
        guard decodeDurationMs > 0, decodeOutputTokens > 0 else { return nil }
        return Double(decodeOutputTokens) / (Double(decodeDurationMs) / 1_000)
    }

    var billedInputTokens: Int64 {
        inputTokens + cachedInputTokens + cacheCreationInputTokens
    }

    var cacheHitPercent: Int? {
        guard billedInputTokens > 0 else { return nil }
        return Int((Double(cachedInputTokens) / Double(billedInputTokens) * 100).rounded())
    }
}

enum ChatStatsField: String, Codable, CaseIterable, Identifiable {
    case turns
    case steps
    case llmDuration
    case toolDuration
    case averageTTFT
    case tokensPerSecond
    case cacheHit
    case tokens

    var id: String { rawValue }

    static let defaultVisible: Set<ChatStatsField> = [
        .tokensPerSecond,
        .cacheHit,
        .tokens
    ]
}

enum ChatStatsFormatter {
    static func tokens(_ value: Int64) -> String {
        if value < 1_000 { return String(value) }
        if value < 1_000_000 { return scaled(Double(value) / 1_000) + "K" }
        return scaled(Double(value) / 1_000_000) + "M"
    }

    static func duration(milliseconds: Double) -> String {
        let seconds = max(0, milliseconds) / 1_000
        if seconds < 60 {
            return "\((seconds * 10).rounded() / 10)s"
        }
        let rounded = Int(seconds.rounded())
        return "\(rounded / 60)m\(rounded % 60)s"
    }

    static func throughput(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if value >= 100 { return String(Int(value.rounded())) }
        return String((value * 10).rounded() / 10)
    }

    private static func scaled(_ value: Double) -> String {
        if value >= 100 { return String(Int(value.rounded())) }
        return String((value * 10).rounded() / 10)
    }
}

struct ProviderMetricsContext: Sendable {
    let conversationId: Int64
    let turnId: String
    let recorder: @Sendable (ConversationExecutionMetric) -> Void

    @TaskLocal static var current: ProviderMetricsContext?
}

extension ProviderUsage {
    /// Converts provider wire conventions into disjoint input buckets.
    func disjointInputUsage(providerID: String) -> ProviderUsage {
        let normalized = normalized()
        let cached = max(0, normalized.cachedInputTokens ?? 0)
        let created = max(0, normalized.cacheCreationInputTokens ?? 0)
        let provider = providerID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let inclusiveProviders: Set<String> = [
            "GEMINI", "GEMINI_AUTH", "OPENROUTER", "OPENAI", "OPENAI_COMPAT",
            "OPENCODE_GO", "MODELS_DEV:OPENCODE-GO", "CODEX_AUTH", "CLINEPASS", "MINIMAX", "ZAI"
        ]
        // Every currently supported dynamic models.dev adapter except the native
        // Anthropic Messages adapter reaches an OpenAI-compatible endpoint, whose
        // prompt/input token count includes cache-read and cache-write tokens.
        let modelsDevUsesInclusiveInput = provider.hasPrefix("MODELS_DEV:")
            && provider != "MODELS_DEV:ANTHROPIC"
        let rawInput = max(0, normalized.inputTokens ?? 0)
        let uncached = (inclusiveProviders.contains(provider) || modelsDevUsesInclusiveInput)
            ? max(0, rawInput - cached - created)
            : rawInput
        return ProviderUsage(
            inputTokens: uncached,
            outputTokens: normalized.outputTokens,
            totalTokens: uncached + cached + created + max(0, normalized.outputTokens ?? 0),
            reasoningTokens: normalized.reasoningTokens,
            cachedInputTokens: normalized.cachedInputTokens,
            cacheCreationInputTokens: normalized.cacheCreationInputTokens
        )
    }
}
