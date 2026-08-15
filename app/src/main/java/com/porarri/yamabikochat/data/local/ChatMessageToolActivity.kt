package com.porarri.yamabikochat.data.local

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import com.porarri.yamabikochat.data.model.ProviderRequestMessage
import com.porarri.yamabikochat.data.model.ToolSource
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Serializable
data class ToolActivityStep(
    val id: String,
    val round: Int = 0,
    val toolName: String = "",
    val title: String = "",
    val detail: String = "",
    val status: Status = Status.completed,
    val resultCount: Int? = null,
    val sources: List<ToolSource> = emptyList(),
    val errorMessage: String? = null,
    val createdAtMs: Long = System.currentTimeMillis()
) {
    @Serializable
    enum class Status {
        running,
        completed,
        failed
    }

    companion object {
        private val json = Json { ignoreUnknownKeys = true; isLenient = true; encodeDefaults = true }

        fun decodeSteps(raw: String): List<ToolActivityStep> =
            runCatching { json.decodeFromString<List<ToolActivityStep>>(raw) }.getOrDefault(emptyList())

        fun encodeSteps(steps: List<ToolActivityStep>): String =
            json.encodeToString(steps)
    }
}

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
    val steps: List<ToolActivityStep>
        get() = ToolActivityStep.decodeSteps(stepsJSON)

    val providerTranscript: List<ProviderRequestMessage>?
        get() = providerTranscriptJSON?.let { encoded ->
            runCatching { transcriptCodec.decodeFromString<List<ProviderRequestMessage>>(encoded) }.getOrNull()
        }

    companion object {
        private val transcriptCodec = Json {
            ignoreUnknownKeys = true
            isLenient = true
            encodeDefaults = true
        }

        fun encodeProviderTranscript(contents: List<ProviderRequestMessage>): String =
            transcriptCodec.encodeToString(contents)
    }
}
