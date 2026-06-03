package com.porarri.yamabikochat.data.local

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "chat_message_variants",
    foreignKeys = [
        ForeignKey(
            entity = ChatMessage::class,
            parentColumns = ["id"],
            childColumns = ["baseMessageId"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index(value = ["baseMessageId", "variantIndex"], unique = true)
    ]
)
data class ChatMessageVariant(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val baseMessageId: Long,
    val variantIndex: Int,
    val text: String,
    val attachments: List<String> = emptyList(),
    val thinkingStream: String? = null,
    val createdAtMs: Long = System.currentTimeMillis()
)
