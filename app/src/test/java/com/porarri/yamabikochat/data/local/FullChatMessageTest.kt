package com.porarri.yamabikochat.data.local

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class FullChatMessageTest {

    @Test
    fun selectedVariantWithoutThinkingDoesNotExposeBaseThinking() {
        val message = ChatMessage(
            id = 1L,
            conversationId = 10L,
            role = "model",
            text = "base",
            thinkingSummary = "base-summary",
            selectedVariantIndex = 1
        )
        val fullMessage = FullChatMessage(
            chatMessage = message,
            thinkingStream = "base-thinking",
            variants = listOf(
                ChatMessageVariant(
                    baseMessageId = 1L,
                    variantIndex = 1,
                    text = "regenerated"
                )
            )
        )

        assertEquals("regenerated", fullMessage.displayText)
        assertNull(fullMessage.displayThinkingStream)
    }

    @Test
    fun baseVariantUsesBaseThinking() {
        val message = ChatMessage(
            id = 1L,
            conversationId = 10L,
            role = "model",
            text = "base",
            selectedVariantIndex = 0
        )
        val fullMessage = FullChatMessage(
            chatMessage = message,
            thinkingStream = "base-thinking",
            variants = listOf(
                ChatMessageVariant(
                    baseMessageId = 1L,
                    variantIndex = 1,
                    text = "regenerated",
                    thinkingStream = "variant-thinking"
                )
            )
        )

        assertEquals("base", fullMessage.displayText)
        assertEquals("base-thinking", fullMessage.displayThinkingStream)
    }
}
