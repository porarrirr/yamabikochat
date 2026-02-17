package com.porarri.yamabikochat.data.local

data class TokenUsageTotals(
    val requestCount: Long = 0,
    val inputTokens: Long = 0,
    val outputTokens: Long = 0,
    val totalTokens: Long = 0,
    val totalCostUsd: Double = 0.0
)

data class TokenUsageByModel(
    val model: String,
    val requestCount: Long,
    val inputTokens: Long,
    val outputTokens: Long,
    val totalTokens: Long,
    val totalCostUsd: Double
)

data class TokenUsageDailyPoint(
    val dayBucketStartMs: Long,
    val requestCount: Long,
    val totalTokens: Long,
    val totalCostUsd: Double
)
