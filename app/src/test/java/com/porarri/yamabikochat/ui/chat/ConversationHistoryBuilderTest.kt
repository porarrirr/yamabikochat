package com.porarri.yamabikochat.ui.chat

import com.porarri.yamabikochat.data.ChatRepository
import com.porarri.yamabikochat.data.local.ChatMessage
import com.porarri.yamabikochat.data.local.ChatMessageSummary
import com.porarri.yamabikochat.data.local.FullChatMessage
import io.mockk.mockk
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Test

class ConversationHistoryBuilderTest {

    @Test
    fun buildsOrderedProviderRequestMessages() = runBlocking {
        val user = ChatMessage(id = 1, conversationId = 10, role = "user", text = "hello")
        val assistant = ChatMessage(id = 2, conversationId = 10, role = "model", text = "world")
        val assistantFull = FullChatMessage(chatMessage = assistant)

        val builder = ConversationHistoryBuilder(
            repository = mockk<ChatRepository>(relaxed = true),
            ioDispatcher = Dispatchers.Unconfined
        )

        val result = builder.buildStandardHistory(
            text = "next question",
            attachmentsToSend = emptyList(),
            messageSummaries = listOf(summary(user), summary(assistant)),
            existingFullMessages = mapOf(
                1L to FullChatMessage(chatMessage = user),
                2L to assistantFull
            )
        )

        assertEquals(3, result.messages.size)
        assertEquals("user", result.messages[0].role)
        assertEquals("hello", result.messages[0].content)
        assertEquals("assistant", result.messages[1].role)
        assertEquals("world", result.messages[1].content)
        assertEquals("user", result.messages[2].role)
        assertEquals("next question", result.messages[2].content)
    }

    @Test
    fun keepsMoreThanOneHundredHistoryMessages() = runBlocking {
        val summaries = (1L..120L).map { id ->
            val role = if (id % 2L == 1L) "user" else "model"
            val message = ChatMessage(id = id, conversationId = 10, role = role, text = "m$id")
            summary(message)
        }
        val fullMessages = summaries.associate { item ->
            val message = ChatMessage(
                id = item.id,
                conversationId = item.conversationId,
                role = item.role,
                text = item.textPreview
            )
            item.id to FullChatMessage(chatMessage = message)
        }
        val builder = ConversationHistoryBuilder(
            repository = mockk<ChatRepository>(relaxed = true),
            ioDispatcher = Dispatchers.Unconfined
        )

        val result = builder.buildStandardHistory(
            text = "latest",
            attachmentsToSend = emptyList(),
            messageSummaries = summaries,
            existingFullMessages = fullMessages
        )

        assertEquals(121, result.messages.size)
        assertEquals("m1", result.messages.first().content)
        assertEquals("latest", result.messages.last().content)
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
