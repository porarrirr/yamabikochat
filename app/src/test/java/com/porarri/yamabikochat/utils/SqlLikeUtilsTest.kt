package com.porarri.yamabikochat.utils

import org.junit.Assert.assertEquals
import org.junit.Assert.assertThrows
import org.junit.Test

class SqlLikeUtilsTest {
    @Test
    fun `buildEscapedContainsPattern trims input`() {
        assertEquals("%hello%", SqlLikeUtils.buildEscapedContainsPattern("  hello  "))
    }

    @Test
    fun `buildEscapedContainsPattern escapes wildcards and backslash`() {
        val pattern = SqlLikeUtils.buildEscapedContainsPattern("foo%_\\bar")
        assertEquals("%foo\\%\\_\\\\bar%", pattern)
    }

    @Test
    fun `buildEscapedContainsPattern rejects blank query`() {
        assertThrows(IllegalArgumentException::class.java) {
            SqlLikeUtils.buildEscapedContainsPattern("   ")
        }
    }
}
