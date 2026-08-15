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

    @Test
    fun displayToolActivityUsesBaseOrVariant() {
        val message = ChatMessage(
            id = 1L,
            conversationId = 10L,
            role = "model",
            text = "base",
            selectedVariantIndex = 0
        )
        val baseActivity = ChatMessageToolActivity(
            messageId = 1L,
            stepsJSON = """[{"id":"base","round":1,"toolName":"web_search","title":"Webを検索","detail":"q","status":"completed","createdAtMs":1}]"""
        )
        val variant = ChatMessageVariant(
            id = 99L,
            baseMessageId = 1L,
            variantIndex = 1,
            text = "regenerated"
        )
        val variantActivity = ChatMessageToolActivity(
            variantId = 99L,
            stepsJSON = """[{"id":"variant","round":1,"toolName":"web_search","title":"Webを検索","detail":"v","status":"completed","createdAtMs":1}]"""
        )
        val fullMessage = FullChatMessage(
            chatMessage = message,
            thinkingStream = null,
            variants = listOf(variant),
            toolActivity = baseActivity,
            variantToolActivities = mapOf(99L to variantActivity)
        )

        assertEquals("q", fullMessage.displayToolActivity?.steps?.firstOrNull()?.detail)

        val selected = fullMessage.copy(
            chatMessage = message.copy(selectedVariantIndex = 1)
        )
        assertEquals("v", selected.displayToolActivity?.steps?.firstOrNull()?.detail)
    }
}
