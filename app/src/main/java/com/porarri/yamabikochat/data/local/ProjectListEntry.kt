package com.porarri.yamabikochat.data.local

data class ProjectListEntry(
    val id: Long,
    val title: String,
    val iconName: String,
    val colorHex: String,
    val instructions: String?,
    val createdAtMs: Long,
    val updatedAtMs: Long,
    val conversationCount: Int
)
