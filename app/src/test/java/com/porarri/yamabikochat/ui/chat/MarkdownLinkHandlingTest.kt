package com.porarri.yamabikochat.ui.chat

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class MarkdownLinkHandlingTest {

    @Test
    fun supportedUrl_acceptsHttpAndHttps() {
        assertTrue(isSupportedHttpUrl("https://example.com"))
        assertTrue(isSupportedHttpUrl("http://example.com/path?q=1"))
    }

    @Test
    fun supportedUrl_rejectsUnsupportedSchemes() {
        assertFalse(isSupportedHttpUrl("mailto:test@example.com"))
        assertFalse(isSupportedHttpUrl("javascript:alert(1)"))
        assertFalse(isSupportedHttpUrl("intent://scan/#Intent;scheme=zxing;end"))
    }

    @Test
    fun supportedUrl_rejectsBlankAndHostlessUrls() {
        assertFalse(isSupportedHttpUrl(""))
        assertFalse(isSupportedHttpUrl("   "))
        assertFalse(isSupportedHttpUrl("https:///path-only"))
    }
}
