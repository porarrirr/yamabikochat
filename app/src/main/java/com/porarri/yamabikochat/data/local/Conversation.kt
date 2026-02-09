package com.porarri.yamabikochat.data.local

import androidx.room.Entity
import androidx.room.PrimaryKey

@Entity(tableName = "conversations")
data class Conversation(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val title: String,
    val systemPrompt: String? = null,
    val model: String,
    val apiProvider: String = "GEMINI",
    val timestamp: Long = System.currentTimeMillis(),
    val codexSessionId: String? = null,
    val isSecret: Boolean = false
)
