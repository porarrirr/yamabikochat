import Foundation

struct TokenUsageTotals: Equatable {
    var requestCount: Int64 = 0
    var inputTokens: Int64 = 0
    var outputTokens: Int64 = 0
    var cachedInputTokens: Int64 = 0
    var reasoningTokens: Int64 = 0
    var totalTokens: Int64 = 0
    var totalCostUsd: Double = 0
}

struct TokenUsageByModel: Identifiable, Equatable {
    var id: String { model.lowercased() }

    var model: String
    var requestCount: Int64
    var inputTokens: Int64
    var outputTokens: Int64
    var cachedInputTokens: Int64
    var reasoningTokens: Int64
    var totalTokens: Int64
    var totalCostUsd: Double
}

struct TokenUsageDailyPoint: Identifiable, Equatable {
    var id: Int64 { dayBucketStartMs }

    var dayBucketStartMs: Int64
    var requestCount: Int64
    var totalTokens: Int64
    var totalCostUsd: Double
}
