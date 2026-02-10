package com.porarri.yamabikochat.data.local

data class ConversationSearchResult(
    val conversationId: Long,
    val conversationTitle: String,
    val source: String, // "CHAT" or "DUAL"
    val messageId: Long,
    val timestamp: Long,
    val role: String,
    val matchedField: String, // "CHAT", "USER", "MODEL_A", "MODEL_B"
    val snippet: String
)

