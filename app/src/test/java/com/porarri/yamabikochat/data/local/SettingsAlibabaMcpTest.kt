package com.porarri.yamabikochat.data.local

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class SettingsAlibabaMcpTest {
    @Test
    fun resolvedAlibabaMcpServerUrl_acceptsHttpsOnly() {
        val valid = Settings(alibabaMcpServerUrl = " https://mcp.firecrawl.dev/fc-key/v2/mcp ")
        val http = Settings(alibabaMcpServerUrl = "http://mcp.firecrawl.dev/fc-key/v2/mcp")
        val withUserInfo = Settings(alibabaMcpServerUrl = "https://user@mcp.firecrawl.dev/fc-key/v2/mcp")

        assertEquals("https://mcp.firecrawl.dev/fc-key/v2/mcp", valid.resolvedAlibabaMcpServerUrl())
        assertNull(http.resolvedAlibabaMcpServerUrl())
        assertNull(withUserInfo.resolvedAlibabaMcpServerUrl())
    }

    @Test
    fun alibabaMcpAllowedToolsList_normalizesCommaAndLineSeparatedTools() {
        val settings = Settings(
            alibabaMcpAllowedTools = "search, scrape\nsearch, crawl"
        )

        assertEquals(
            listOf("search", "scrape", "crawl"),
            settings.alibabaMcpAllowedToolsList()
        )
    }
}
