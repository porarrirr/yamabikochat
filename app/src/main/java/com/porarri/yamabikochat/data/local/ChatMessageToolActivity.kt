package com.porarri.yamabikochat.data.local

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey

@Entity(
    tableName = "chat_message_tool_activity",
    foreignKeys = [
        ForeignKey(
            entity = ChatMessage::class,
            parentColumns = ["id"],
            childColumns = ["messageId"],
            onDelete = ForeignKey.CASCADE
        ),
        ForeignKey(
            entity = ChatMessageVariant::class,
            parentColumns = ["id"],
            childColumns = ["variantId"],
            onDelete = ForeignKey.CASCADE
        )
    ],
    indices = [
        Index(value = ["messageId"]),
        Index(value = ["variantId"])
    ]
)
data class ChatMessageToolActivity(
    @PrimaryKey(autoGenerate = true)
    val id: Long = 0,
    val messageId: Long? = null,
    val variantId: Long? = null,
    val stepsJSON: String
) {
    val steps: List<com.porarri.yamabikochat.data.tools.ToolActivityStep>
        get() = com.porarri.yamabikochat.data.tools.ToolActivityStep.decodeSteps(stepsJSON)
}
