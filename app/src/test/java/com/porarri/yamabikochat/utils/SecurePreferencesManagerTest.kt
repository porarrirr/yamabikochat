package com.porarri.yamabikochat.utils

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKeys
import com.porarri.yamabikochat.TestLogUtils
import io.mockk.*
import org.junit.Before
import org.junit.Test
import org.junit.Assert.*
import org.junit.After
import javax.crypto.AEADBadTagException

class SecurePreferencesManagerTest {

    private lateinit var context: Context
    private lateinit var mockSharedPreferences: SharedPreferences
    private lateinit var mockEditor: SharedPreferences.Editor
    private lateinit var fallbackSharedPreferences: SharedPreferences
    private lateinit var fallbackEditor: SharedPreferences.Editor
    private lateinit var securePreferencesManager: SecurePreferencesManager

    @Before
    fun setup() {
        TestLogUtils.setup()
        context = mockk(relaxed = true)
        every { context.applicationContext } returns context
        mockSharedPreferences = mockk()
        mockEditor = mockk(relaxed = true)
        fallbackSharedPreferences = mockk()
        fallbackEditor = mockk(relaxed = true)

        every { mockSharedPreferences.edit() } returns mockEditor
        every { mockEditor.putString(any(), any()) } returns mockEditor      
        every { mockEditor.remove(any()) } returns mockEditor
        every { mockEditor.clear() } returns mockEditor
        every { mockEditor.apply() } just Runs

        every { context.getSharedPreferences(any(), any()) } returns fallbackSharedPreferences
        every { fallbackSharedPreferences.edit() } returns fallbackEditor
        every { fallbackEditor.putString(any(), any()) } returns fallbackEditor
        every { fallbackEditor.remove(any()) } returns fallbackEditor
        every { fallbackEditor.clear() } returns fallbackEditor
        every { fallbackEditor.apply() } just Runs
        every { fallbackSharedPreferences.getString(any(), any()) } returns null
        mockkStatic(MasterKeys::class)
        every { MasterKeys.getOrCreate(any()) } returns "alias"

        resetSingletonInstance()
        securePreferencesManager = SecurePreferencesManager.getInstance(context)
        setEncryptedPrefsDelegate(securePreferencesManager, mockSharedPreferences)

        val encryptedPrefsGetter = SecurePreferencesManager::class.java.getDeclaredMethod("getEncryptedPrefs")
        encryptedPrefsGetter.isAccessible = true
        val injectedPrefs = encryptedPrefsGetter.invoke(securePreferencesManager) as SharedPreferences
        assertSame("encryptedPrefs should use mocked instance", mockSharedPreferences, injectedPrefs)
    }

    @After
    fun tearDown() {
        TestLogUtils.tearDown()
        unmockkStatic(MasterKeys::class)
    }

    @Test
    fun `getInstance returns singleton instance`() {
        val instance1 = SecurePreferencesManager.getInstance(context)
        val instance2 = SecurePreferencesManager.getInstance(context)
        
        assertSame("Should return same instance", instance1, instance2)
    }

    @Test
    fun `storeGeminiApiKey stores key successfully`() {
        // Given
        val testApiKey = "test-gemini-api-key"
        every { mockSharedPreferences.edit() } returns mockEditor

        // When
        securePreferencesManager.storeGeminiApiKey(testApiKey)

        // Then
        verify { mockEditor.putString("gemini_api_key", testApiKey) }
        verify { mockEditor.apply() }
    }

    @Test
    fun `storeGeminiApiKey handles null key`() {
        // When
        securePreferencesManager.storeGeminiApiKey(null)

        // Then
        verify { mockEditor.remove("gemini_api_key") }
        verify { mockEditor.apply() }
    }

    @Test
    fun `getGeminiApiKey returns stored key`() {
        // Given
        val expectedKey = "stored-gemini-key"
        every { mockSharedPreferences.getString("gemini_api_key", null) } returns expectedKey

        // When
        val result = securePreferencesManager.getGeminiApiKey()

        // Then
        assertEquals(expectedKey, result)
        verify { mockSharedPreferences.getString("gemini_api_key", null) }
    }

    @Test
    fun `getGeminiApiKey returns null when no key stored`() {
        // Given
        every { mockSharedPreferences.getString("gemini_api_key", null) } returns null

        // When
        val result = securePreferencesManager.getGeminiApiKey()

        // Then
        assertNull(result)
    }

    @Test
    fun `getGeminiApiKey handles AEADBadTagException and clears key`() {
        // Given
        every { mockSharedPreferences.getString("gemini_api_key", null) } throws AEADBadTagException("Decryption failed")

        // When
        val result = securePreferencesManager.getGeminiApiKey()

        // Then
        assertNull(result)
        verify { mockEditor.remove("gemini_api_key") }
        verify { mockEditor.apply() }
    }

    @Test
    fun `clearGeminiApiKey removes key`() {
        // When
        securePreferencesManager.clearGeminiApiKey()

        // Then
        verify { mockEditor.remove("gemini_api_key") }
        verify { mockEditor.apply() }
    }

    @Test
    fun `storeOpenRouterApiKey stores key successfully`() {
        // Given
        val testApiKey = "test-openrouter-api-key"

        // When
        securePreferencesManager.storeOpenRouterApiKey(testApiKey)

        // Then
        verify { mockEditor.putString("openrouter_api_key", testApiKey) }
        verify { mockEditor.apply() }
    }

    @Test
    fun `getOpenRouterApiKey returns stored key`() {
        // Given
        val expectedKey = "stored-openrouter-key"
        every { mockSharedPreferences.getString("openrouter_api_key", null) } returns expectedKey

        // When
        val result = securePreferencesManager.getOpenRouterApiKey()

        // Then
        assertEquals(expectedKey, result)
    }

    @Test
    fun `clearOpenRouterApiKey removes key`() {
        // When
        securePreferencesManager.clearOpenRouterApiKey()

        // Then
        verify { mockEditor.remove("openrouter_api_key") }
        verify { mockEditor.apply() }
    }

    @Test
    fun `clearAllSecureData removes all data`() {
        // When
        securePreferencesManager.clearAllSecureData()

        // Then
        verify { mockEditor.clear() }
        verify { mockEditor.apply() }
        verify { fallbackEditor.clear() }
        verify { fallbackEditor.apply() }
    }

    @Test
    fun `storage operations handle exceptions gracefully`() {
        // Given
        every { mockSharedPreferences.edit() } throws RuntimeException("Storage error")

        // When & Then - Should not throw exceptions
        assertDoesNotThrow {
            securePreferencesManager.storeGeminiApiKey("test")
            securePreferencesManager.clearGeminiApiKey()
            securePreferencesManager.storeOpenRouterApiKey("test")
            securePreferencesManager.clearOpenRouterApiKey()
            securePreferencesManager.clearAllSecureData()
        }
    }

    @Test
    fun `retrieval operations handle exceptions gracefully`() {
        // Given
        every { mockSharedPreferences.getString(any(), any()) } throws RuntimeException("Retrieval error")

        // When
        val geminiResult = securePreferencesManager.getGeminiApiKey()
        val openRouterResult = securePreferencesManager.getOpenRouterApiKey()

        // Then
        assertNull(geminiResult)
        assertNull(openRouterResult)
    }

    private fun resetSingletonInstance() {
        val instanceField = SecurePreferencesManager::class.java.getDeclaredField("INSTANCE")
        instanceField.isAccessible = true
        instanceField.set(null, null)
    }

    private fun setEncryptedPrefsDelegate(manager: SecurePreferencesManager, prefs: SharedPreferences) {
        val delegateField = SecurePreferencesManager::class.java.getDeclaredField("encryptedPrefs\$delegate")
        delegateField.isAccessible = true
        delegateField.set(manager, lazyOf(prefs))
    }

    private fun assertDoesNotThrow(executable: () -> Unit) {
        try {
            executable()
        } catch (e: Exception) {
            fail("Expected no exception, but got: ${e.message}")
        }
    }
}
