package com.porarri.yamabikochat.data.local

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SettingsGlobalProviderPresetVisibilityTest {

    @Test
    fun shouldShowGlobalProviderPresetInChat_fallsBackToGlobalSetting() {
        val disabled = Settings(showGlobalProviderPresetsInChat = false)
        assertFalse(disabled.shouldShowGlobalProviderPresetInChat("OPENAI"))
        assertFalse(disabled.shouldShowGlobalProviderPresetInChat("GEMINI"))

        val enabled = Settings(showGlobalProviderPresetsInChat = true)
        assertTrue(enabled.shouldShowGlobalProviderPresetInChat("OPENAI"))
        assertTrue(enabled.shouldShowGlobalProviderPresetInChat("GEMINI"))
    }

    @Test
    fun shouldShowGlobalProviderPresetInChat_overrideDisablesSpecificProvider() {
        val settings = Settings(
            showGlobalProviderPresetsInChat = true,
            showGlobalProviderPresetsInChatByProvider = "{\"OPENAI\":false}"
        )
        assertFalse(settings.shouldShowGlobalProviderPresetInChat("OPENAI"))
        assertTrue(settings.shouldShowGlobalProviderPresetInChat("GEMINI"))
    }

    @Test
    fun shouldShowGlobalProviderPresetInChat_overrideEnablesSpecificProvider() {
        val settings = Settings(
            showGlobalProviderPresetsInChat = false,
            showGlobalProviderPresetsInChatByProvider = "{\"OPENAI\":true}"
        )
        assertTrue(settings.shouldShowGlobalProviderPresetInChat("OPENAI"))
        assertFalse(settings.shouldShowGlobalProviderPresetInChat("GEMINI"))
    }

    @Test
    fun shouldShowGlobalProviderPresetInChat_overrideIsCaseInsensitiveForKeys() {
        val settings = Settings(
            showGlobalProviderPresetsInChat = true,
            showGlobalProviderPresetsInChatByProvider = "{\"openai\":false}"
        )
        assertFalse(settings.shouldShowGlobalProviderPresetInChat("OPENAI"))
    }
}

