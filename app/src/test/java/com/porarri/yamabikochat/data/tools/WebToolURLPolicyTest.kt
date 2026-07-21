package com.porarri.yamabikochat.data.tools.search

import com.porarri.yamabikochat.data.tools.WebToolException
import org.junit.Assert.assertThrows
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.URL

class WebToolURLPolicyTest {

    @Test
    fun rejectsLocalhost() {
        val error = assertThrows(WebToolException.InvalidUrl::class.java) {
            WebToolURLPolicy.validatePublicHTTPURL(URL("http://localhost/path"))
        }
        assertTrue(error.message!!.contains("Local hostnames", ignoreCase = true))
    }

    @Test
    fun rejectsLocalhostSubdomain() {
        assertThrows(WebToolException.InvalidUrl::class.java) {
            WebToolURLPolicy.validatePublicHTTPURL(URL("https://app.localhost/"))
        }
    }

    @Test
    fun rejectsLocalTld() {
        assertThrows(WebToolException.InvalidUrl::class.java) {
            WebToolURLPolicy.validatePublicHTTPURL(URL("http://printer.local/status"))
        }
    }

    @Test
    fun rejectsNonHttpSchemes() {
        assertThrows(WebToolException.InvalidUrl::class.java) {
            WebToolURLPolicy.validatePublicHTTPURL(URL("file:///etc/passwd"))
        }
    }
}
