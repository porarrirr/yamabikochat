package com.porarri.yamabikochat.data.local

data class FullChatMessage(
    val chatMessage: ChatMessage,
    val thinkingStream: String? = null
)
