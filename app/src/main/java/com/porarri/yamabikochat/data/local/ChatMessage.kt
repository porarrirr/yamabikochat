package com.porarri.yamabikochat.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "chat_messages")
data class ChatMessage(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val conversationId: Long,
    val role: String, // "user" or "model"
    val text: String,
    val attachments: List<String> = emptyList(),
    val timestamp: Long = System.currentTimeMillis(),
    val thinkingSummary: String? = null
)
