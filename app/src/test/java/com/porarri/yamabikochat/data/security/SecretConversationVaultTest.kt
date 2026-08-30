package com.porarri.yamabikochat.data.security

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test

class SecretConversationVaultTest {
    @Test
    fun `destroying process key makes ciphertext unreadable`() {
        val conversationId = System.nanoTime()
        SecretConversationVault.activate(conversationId)
        try {
            val ciphertext = SecretConversationVault.seal("sensitive text", conversationId)

            assertTrue(ciphertext.startsWith(SecretConversationVault.PREFIX))
            assertFalse(ciphertext.contains("sensitive text"))
            assertEquals("sensitive text", SecretConversationVault.open(ciphertext, conversationId))

            SecretConversationVault.destroy(conversationId)
            assertThrows(IllegalStateException::class.java) {
                SecretConversationVault.open(ciphertext, conversationId)
            }
        } finally {
            SecretConversationVault.destroy(conversationId)
        }
    }

    @Test
    fun `authenticated ciphertext rejects modification`() {
        val conversationId = System.nanoTime()
        SecretConversationVault.activate(conversationId)
        try {
            val ciphertext = SecretConversationVault.seal("sensitive text", conversationId)
            val replacement = if (ciphertext.last() == 'A') 'B' else 'A'
            val modified = ciphertext.dropLast(1) + replacement

            assertThrows(Exception::class.java) {
                SecretConversationVault.open(modified, conversationId)
            }
        } finally {
            SecretConversationVault.destroy(conversationId)
        }
    }

    @Test
    fun `plaintext beginning with storage prefix is still encrypted`() {
        val conversationId = System.nanoTime()
        val plaintext = SecretConversationVault.PREFIX + "user supplied text"
        SecretConversationVault.activate(conversationId)
        try {
            val ciphertext = SecretConversationVault.seal(plaintext, conversationId)

            assertFalse(ciphertext == plaintext)
            assertEquals(plaintext, SecretConversationVault.open(ciphertext, conversationId))
        } finally {
            SecretConversationVault.destroy(conversationId)
        }
    }
}
