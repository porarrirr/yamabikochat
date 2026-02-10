package com.porarri.yamabikochat.data.local

data class ChatMessageSummary(
    val id: Long,
    val conversationId: Long,
    val role: String,
    val timestamp: Long,
    val hasAttachments: Boolean,
    val hasThinking: Boolean,
    val textPreview: String // 最初の100文字のプレビュー
)
