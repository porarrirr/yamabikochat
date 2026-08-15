package com.porarri.yamabikochat.ui.chat

import com.porarri.yamabikochat.data.ChatRepository
import com.porarri.yamabikochat.data.local.ChatMessage
import com.porarri.yamabikochat.data.local.ChatMessageSummary
import com.porarri.yamabikochat.data.local.ChatMessageToolActivity
import com.porarri.yamabikochat.data.local.FullChatMessage
import com.porarri.yamabikochat.data.remote.Content
import com.porarri.yamabikochat.data.remote.FunctionCall
import com.porarri.yamabikochat.data.remote.FunctionResponse
import com.porarri.yamabikochat.data.remote.Part
import io.mockk.mockk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Test

class ConversationHistoryBuilderTest {

    @Test
    fun appendsStoredToolTranscriptBeforeFinalAnswerAndNewUserMessage() = runBlocking {
        val user = ChatMessage(id = 1, conversationId = 10, role = "user", text = "search")
        val replay = listOf(
            Content(
                role = "model",
                parts = listOf(
                    Part(
                        functionCall = FunctionCall(
                            name = "web_search",
                            args = JsonObject(mapOf("query" to JsonPrimitive("large query")))
                        )
                    )
                )
            ),
            Content(
                role = "user",
                parts = listOf(
                    Part(
                        functionResponse = FunctionResponse(
                            name = "web_search",
                            response = JsonObject(mapOf("content" to JsonPrimitive("large raw result"))),
                            id = "call-0-web_search"
                        )
                    )
                )
            )
        )
        val assistant = ChatMessage(id = 2, conversationId = 10, role = "model", text = "final answer")
        val assistantFull = FullChatMessage(
            chatMessage = assistant,
            toolActivity = ChatMessageToolActivity(
                messageId = 2,
                stepsJSON = "[]",
                providerTranscriptJSON = ChatMessageToolActivity.encodeProviderTranscript(replay)
            )
        )
        val builder = ConversationHistoryBuilder(
            repository = mockk<ChatRepository>(relaxed = true),
            ioDispatcher = Dispatchers.Unconfined
        )

        val result = builder.buildStandardHistory(
            text = "thanks",
            attachmentsToSend = emptyList(),
            messageSummaries = listOf(summary(user), summary(assistant)),
            existingFullMessages = mapOf(
                1L to FullChatMessage(chatMessage = user),
                2L to assistantFull
            )
        )

        assertEquals(listOf("user", "model", "user", "model", "user"), result.history.map { it.role })
        assertEquals("web_search", result.history[1].parts.single().functionCall?.name)
        assertEquals("large raw result", result.history[2].parts.single().functionResponse
            ?.response?.let { (it as JsonObject)["content"]?.let { value -> (value as JsonPrimitive).content } })
        assertEquals("final answer", result.history[3].parts.single().text)
        assertEquals("thanks", result.history[4].parts.single().text)
    }

    private fun summary(message: ChatMessage) = ChatMessageSummary(
        id = message.id,
        conversationId = message.conversationId,
        role = message.role,
        timestamp = message.timestamp,
        hasAttachments = false,
        hasThinking = false,
        textPreview = message.text
    )
}
