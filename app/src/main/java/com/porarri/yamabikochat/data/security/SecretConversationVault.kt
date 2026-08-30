package com.porarri.yamabikochat.data.security

import java.security.SecureRandom
import java.util.Base64
import java.util.concurrent.ConcurrentHashMap
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

/** Process-memory-only keys provide cryptographic erasure for secret chats. */
object SecretConversationVault {
    const val PREFIX = "yamabiko-secret:v1:"
    private val keys = ConcurrentHashMap<Long, SecretKey>()
    private val random = SecureRandom()

    fun activate(conversationId: Long) {
        keys.computeIfAbsent(conversationId) {
            ByteArray(32).also(random::nextBytes).let { SecretKeySpec(it, "AES") }
        }
    }

    fun destroy(conversationId: Long) {
        keys.remove(conversationId)
    }

    fun destroyAll() {
        keys.clear()
    }

    fun seal(plaintext: String, conversationId: Long): String {
        val key = keys[conversationId]
            ?: error("Secret conversation key is unavailable: $conversationId")
        val nonce = ByteArray(12).also(random::nextBytes)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(128, nonce))
        val encrypted = cipher.doFinal(plaintext.toByteArray(Charsets.UTF_8))
        return PREFIX + Base64.getEncoder().encodeToString(nonce + encrypted)
    }

    fun open(value: String, conversationId: Long): String {
        if (!value.startsWith(PREFIX)) return value
        val key = keys[conversationId]
            ?: error("Secret conversation key is unavailable: $conversationId")
        val combined = Base64.getDecoder().decode(value.removePrefix(PREFIX))
        require(combined.size > 12) { "Invalid secret conversation ciphertext" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key, GCMParameterSpec(128, combined.copyOfRange(0, 12)))
        return cipher.doFinal(combined.copyOfRange(12, combined.size)).toString(Charsets.UTF_8)
    }
}
