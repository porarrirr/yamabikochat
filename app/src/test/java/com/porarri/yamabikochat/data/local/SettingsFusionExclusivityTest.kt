package com.porarri.yamabikochat.data.local

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SettingsFusionExclusivityTest {
    @Test
    fun fusionWinsOverDualAndAutoWhenOnlyFusionRequested() {
        val normalized = Settings(
            isFusionModeEnabled = true,
            isDualModeEnabled = false,
            isAutoConversationEnabled = false
        ).normalizedForPersistence()
        assertTrue(normalized.isFusionModeEnabled)
        assertFalse(normalized.isDualModeEnabled)
        assertFalse(normalized.isAutoConversationEnabled)
    }

    @Test
    fun dualDisablesFusionAndAuto() {
        val normalized = Settings(
            isDualModeEnabled = true,
            isAutoConversationEnabled = true,
            isFusionModeEnabled = true
        ).normalizedForPersistence()
        assertTrue(normalized.isDualModeEnabled)
        assertFalse(normalized.isAutoConversationEnabled)
        assertFalse(normalized.isFusionModeEnabled)
    }

    @Test
    fun autoDisablesFusionWhenDualOff() {
        val normalized = Settings(
            isDualModeEnabled = false,
            isAutoConversationEnabled = true,
            isFusionModeEnabled = true
        ).normalizedForPersistence()
        assertFalse(normalized.isDualModeEnabled)
        assertTrue(normalized.isAutoConversationEnabled)
        assertFalse(normalized.isFusionModeEnabled)
    }

    @Test
    fun fusionTaskTypeNormalized() {
        val normalized = Settings(
            isFusionModeEnabled = true,
            fusionTaskType = "CODING"
        ).normalizedForPersistence()
        assertEquals("coding", normalized.fusionTaskType)
        assertEquals("custom", normalized.fusionPresetName)
    }
}
