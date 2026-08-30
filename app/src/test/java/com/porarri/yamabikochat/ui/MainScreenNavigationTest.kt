package com.porarri.yamabikochat.ui

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MainScreenNavigationTest {
    @Test
    fun `resets navigation when visible conversation was purged`() {
        assertTrue(
            shouldResetNavigationAfterSecretPurge(
                purgedConversationIds = setOf(42L),
                visibleConversationIds = listOf(42L)
            )
        )
    }

    @Test
    fun `keeps navigation when only another secret conversation was purged`() {
        assertFalse(
            shouldResetNavigationAfterSecretPurge(
                purgedConversationIds = setOf(42L),
                visibleConversationIds = listOf(7L)
            )
        )
    }

    @Test
    fun `resets navigation when settings covers a purged conversation`() {
        assertTrue(
            shouldResetNavigationAfterSecretPurge(
                purgedConversationIds = setOf(42L),
                visibleConversationIds = listOf(7L, 42L)
            )
        )
    }
}
