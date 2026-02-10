package com.porarri.yamabikochat.data.local

data class ConversationListEntry(
    val conversationId: Long,
    val title: String,
    val timestamp: Long,
    val apiProvider: String,
    val model: String,
    val lastChatTimestamp: Long?,
    val lastChatSnippet: String?,
    val lastDualTimestamp: Long?,
    val lastDualSnippet: String?,
    val lastChatModelTimestamp: Long?,
    val lastDualModelTimestamp: Long?,
    val lastDualModelAProvider: String?,
    val lastDualModelAName: String?,
    val lastDualModelBProvider: String?,
    val lastDualModelBName: String?
)
