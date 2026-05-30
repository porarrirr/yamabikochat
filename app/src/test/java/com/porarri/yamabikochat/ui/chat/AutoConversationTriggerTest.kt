package com.porarri.yamabikochat.ui.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AutoConversationTriggerTest {
    @Test
    fun `matches rejects blank short and known test messages`() {
        listOf("", " ", "a", " A ", "test", "TEST", "テスト", "1", "aa", "kk").forEach { message ->
            assertFalse("Expected '$message' to be ignored", AutoConversationTrigger.matches(message))
        }
    }

    @Test
    fun `matches accepts explicit conversation intent`() {
        listOf(
            "こんにちは。AIについて話しましょう",
            "この設計について相談したい",
            "質問があります",
            "今日のテーマを議論しよう"
        ).forEach { message ->
            assertTrue("Expected '$message' to start auto conversation", AutoConversationTrigger.matches(message))
        }
    }

    @Test
    fun `matches accepts punctuation only when message has substance`() {
        assertFalse(AutoConversationTrigger.matches("??"))
        assertFalse(AutoConversationTrigger.matches("!!"))
        assertTrue(AutoConversationTrigger.matches("どう思う？"))
        assertTrue(AutoConversationTrigger.matches("What?"))
    }

    @Test
    fun `matches accepts longer Japanese and alphabetic messages`() {
        assertTrue(AutoConversationTrigger.matches("今日はとても良い天気です"))
        assertTrue(AutoConversationTrigger.matches("hello world"))
        assertFalse(AutoConversationTrigger.matches("12345"))
        assertFalse(AutoConversationTrigger.matches("-----"))
    }
}
