package com.porarri.yamabikochat.data.local

import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "fusion_traces",
    indices = [Index(value = ["conversationId"])]
)
data class FusionTraceRecord(
    @PrimaryKey
    val id: String,
    val conversationId: Long?,
    val preset: String,
    val startedAtMs: Long,
    val completedAtMs: Long?,
    val totalLatencyMs: Long?,
    val totalCostUsd: Double?,
    val failedModelsJSON: String,
    val traceJSON: String,
    val status: String
)
