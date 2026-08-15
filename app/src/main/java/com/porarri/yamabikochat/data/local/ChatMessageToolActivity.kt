package com.porarri.yamabikochat.data.local

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import com.porarri.yamabikochat.data.remote.Content
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

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
    val stepsJSON: String,
    val providerTranscriptJSON: String? = null
) {
    val steps: List<com.porarri.yamabikochat.data.tools.ToolActivityStep>
        get() = com.porarri.yamabikochat.data.tools.ToolActivityStep.decodeSteps(stepsJSON)

    val providerTranscript: List<Content>?
        get() = providerTranscriptJSON?.let { encoded ->
            runCatching { transcriptCodec.decodeFromString<List<Content>>(encoded) }.getOrNull()
        }

    companion object {
        private val transcriptCodec = Json {
            ignoreUnknownKeys = true
            isLenient = true
            encodeDefaults = true
        }

        fun encodeProviderTranscript(contents: List<Content>): String =
            transcriptCodec.encodeToString(contents)
    }
}
