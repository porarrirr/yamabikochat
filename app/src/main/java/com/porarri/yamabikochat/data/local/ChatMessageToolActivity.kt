package com.porarri.yamabikochat.data.local

import androidx.room.Entity
import androidx.room.ForeignKey
import androidx.room.Index
import androidx.room.PrimaryKey
import com.porarri.yamabikochat.data.model.ProviderRequestMessage
import com.porarri.yamabikochat.data.model.ToolActivityEvent
import com.porarri.yamabikochat.data.model.ToolSource
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.net.URI
import java.io.File

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
    val createdAtMs: Long = System.currentTimeMillis(),
    val artifactNames: List<String>? = null
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
    val providerTranscriptJSON: String? = null,
    val attachmentPathsJSON: String? = null
) {
    val steps: List<ToolActivityStep>
        get() = ToolActivityStep.decodeSteps(stepsJSON)

    val providerTranscript: List<ProviderRequestMessage>?
        get() = providerTranscriptJSON?.let { encoded ->
            runCatching { transcriptCodec.decodeFromString<List<ProviderRequestMessage>>(encoded) }.getOrNull()
        }

    val attachmentPaths: List<String>
        get() = attachmentPathsJSON?.let { encoded ->
            runCatching { transcriptCodec.decodeFromString<List<String>>(encoded) }.getOrNull()
        }.orEmpty()

    companion object {
        private val transcriptCodec = Json {
            ignoreUnknownKeys = true
            isLenient = true
            encodeDefaults = true
        }

        fun encodeProviderTranscript(contents: List<ProviderRequestMessage>): String =
            transcriptCodec.encodeToString(contents)

        fun encodeAttachmentPaths(paths: List<String>): String = transcriptCodec.encodeToString(paths)
    }
}

@Serializable
data class ToolActivityPayload(
    val steps: List<ToolActivityStep> = emptyList(),
    val providerTranscript: List<ProviderRequestMessage> = emptyList(),
    val attachmentPaths: List<String> = emptyList()
) {
    fun applying(event: ToolActivityEvent): ToolActivityPayload {
        val previous = steps.firstOrNull { it.id == event.call.id }
        val updatedStep = stepFor(event).copy(
            round = previous?.round ?: ((steps.maxOfOrNull { it.round } ?: 0) + 1)
        )
        var updatedSteps = (steps.filterNot { it.id == updatedStep.id } + updatedStep)
            .sortedBy { it.round }
        if (event.phase != ToolActivityEvent.Phase.finished || event.result == null) {
            return copy(steps = updatedSteps)
        }
        val callId = event.call.id
        var updatedAttachments = attachmentPaths
        if (event.result.artifacts.isNotEmpty()) {
            val logicalNames = event.result.artifacts.mapTo(mutableSetOf()) { it.name }
            event.result.artifacts.forEach { artifact ->
                updatedAttachments = updatedAttachments.filterNot { isPersistedVersionOf(it, artifact.name) } + artifact.path
            }
            updatedSteps = updatedSteps.map { step ->
                if (step.id == callId) {
                    step.copy(artifactNames = event.result.artifacts.map { it.name })
                } else {
                    step.copy(artifactNames = step.artifactNames?.filterNot(logicalNames::contains)?.takeIf { it.isNotEmpty() })
                }
            }
        }
        val transcript = providerTranscript.filterNot { message ->
            message.toolCallId == callId || message.toolCalls?.any { it.id == callId } == true
        } + listOf(
            ProviderRequestMessage(role = "assistant", content = "", toolCalls = listOf(event.call)),
            ProviderRequestMessage(
                role = "tool",
                content = event.result.content,
                toolCallId = callId,
                toolName = event.call.name,
                toolResultIsError = event.result.isError
            )
        )
        return copy(steps = updatedSteps, providerTranscript = transcript, attachmentPaths = updatedAttachments)
    }

    fun failRunning(message: String): ToolActivityPayload = copy(
        steps = steps.map {
            if (it.status == ToolActivityStep.Status.running) {
                it.copy(status = ToolActivityStep.Status.failed, errorMessage = message)
            } else it
        }
    )

    private fun stepFor(event: ToolActivityEvent): ToolActivityStep {
        val arguments = runCatching { payloadJson.parseToJsonElement(event.call.argumentsJSON).jsonObject }.getOrNull()
        val isSearch = event.call.name == "web_search"
        val isEditor = event.call.name == "str_replace_editor"
        val query = arguments?.get("query")?.jsonPrimitive?.contentOrNull?.trim().orEmpty()
        val goal = arguments?.get("goal")?.jsonPrimitive?.contentOrNull?.trim().orEmpty()
        val host = arguments?.get("url")?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() }
            ?.let { runCatching { URI(it).host }.getOrNull() }
        val editorCommand = arguments?.get("command")?.jsonPrimitive?.contentOrNull.orEmpty()
        val editorPath = arguments?.get("path")?.jsonPrimitive?.contentOrNull.orEmpty()
        val detail = if (isEditor) listOf(editorCommand, editorPath).filter { it.isNotBlank() }.joinToString(" — ")
        else if (isSearch) query.ifBlank { "検索語を確認中" }
        else listOfNotNull(host, goal.takeIf { it.isNotBlank() }).joinToString(" — ").ifBlank { "ページを確認中" }
        val resultObject = event.result?.let { runCatching { payloadJson.parseToJsonElement(it.content).jsonObject }.getOrNull() }
        val resultCount = resultObject?.get("results")?.let { runCatching { it.jsonArray.size }.getOrNull() }
        val error = if (event.result?.isError == true) {
            resultObject?.get("error")?.jsonPrimitive?.contentOrNull?.takeIf { it.isNotBlank() }
                ?: "ツールの実行に失敗しました"
        } else null
        return ToolActivityStep(
            id = event.call.id,
            toolName = event.call.name,
            title = if (isEditor) "ファイルを編集" else if (isSearch) "Webを検索" else "ページを確認",
            detail = detail,
            status = if (event.phase == ToolActivityEvent.Phase.started) ToolActivityStep.Status.running
                else if (event.result?.isError == true) ToolActivityStep.Status.failed else ToolActivityStep.Status.completed,
            resultCount = resultCount,
            sources = event.result?.sources.orEmpty().distinctBy { it.url },
            errorMessage = error,
            createdAtMs = event.createdAtMs,
            artifactNames = event.result?.artifacts?.map { it.name }?.takeIf { it.isNotEmpty() }
        )
    }

    companion object {
        private val payloadJson = Json { ignoreUnknownKeys = true; isLenient = true }

        private fun isPersistedVersionOf(path: String, logicalName: String): Boolean {
            val candidate = File(path).name
            if (candidate == logicalName) return true
            val source = File(logicalName)
            val extension = source.extension.takeIf { it.isNotEmpty() }?.let { ".${Regex.escape(it)}" }.orEmpty()
            val stem = if (source.extension.isEmpty()) source.name else source.nameWithoutExtension
            return candidate.matches(Regex("${Regex.escape(stem)} \\(\\d+\\)$extension"))
        }
    }
}
