package com.porarri.yamabikochat.data.local

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "token_usage_records",
    foreignKeys = [
        ForeignKey(
            entity = Conversation::class,
            parentColumns = ["id"],
            childColumns = ["conversationId"],
            onDelete = ForeignKey.SET_NULL
        )
    ],
    indices = [
        Index("timestamp"),
        Index(value = ["model", "timestamp"]),
        Index("conversationId")
    ]
)
data class TokenUsageRecord(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val timestamp: Long = System.currentTimeMillis(),
    val provider: String,
    val model: String,
    val requestType: String = "chat",
    val conversationId: Long? = null,
    val inputTokens: Int = 0,
    val outputTokens: Int = 0,
    val totalTokens: Int = 0,
    val reasoningTokens: Int? = null,
    val cachedInputTokens: Int? = null,
    val costUsd: Double? = null
)
