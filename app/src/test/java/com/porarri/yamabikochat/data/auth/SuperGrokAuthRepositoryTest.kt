package com.porarri.yamabikochat.data.auth

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import java.util.Base64

class SuperGrokAuthRepositoryTest {
    @Test
    fun buildAuthorizeUrlIncludesRequiredParams() {
        val url = SuperGrokAuthRepository.buildAuthorizeUrl(
            redirectUri = SuperGrokAuthConstants.REDIRECT_URI,
            verifier = "verifier",
            challenge = "challenge",
            state = "state-token",
            nonce = "nonce-token"
        )

        val query = url.substringAfter('?')
            .split('&')
            .mapNotNull { part ->
                val pieces = part.split('=', limit = 2)
                if (pieces.size == 2) {
                    pieces[0] to URLDecoder.decode(pieces[1], StandardCharsets.UTF_8.name())
                } else {
                    null
                }
            }
            .toMap()

        assertEquals("code", query["response_type"])
        assertEquals(SuperGrokAuthConstants.CLIENT_ID, query["client_id"])
        assertEquals(SuperGrokAuthConstants.REDIRECT_URI, query["redirect_uri"])
        assertEquals(SuperGrokAuthConstants.SCOPE, query["scope"])
        assertEquals("challenge", query["code_challenge"])
        assertEquals("S256", query["code_challenge_method"])
        assertEquals("state-token", query["state"])
        assertEquals("nonce-token", query["nonce"])
        assertEquals("generic", query["plan"])
        assertEquals("opencode", query["referrer"])
    }

    @Test
    fun accessTokenIsExpiringHonorsSkew() {
        val expired = makeJwt(exp = (System.currentTimeMillis() / 1_000L) - 60)
        assertTrue(SuperGrokJwtParser.accessTokenIsExpiring(expired, skewMs = 0))

        val fresh = makeJwt(exp = (System.currentTimeMillis() / 1_000L) + 3_600)
        assertFalse(SuperGrokJwtParser.accessTokenIsExpiring(fresh, skewMs = 0))
        assertTrue(SuperGrokJwtParser.accessTokenIsExpiring(fresh, skewMs = 3_600_000))
    }

    @Test
    fun refreshErrorClassification() {
        assertEquals(
            SuperGrokAuthRefreshError.Expired,
            SuperGrokAuthRefreshError.classified("""{"error":"invalid_grant"}""")
        )
        assertEquals(
            SuperGrokAuthRefreshError.Reused,
            SuperGrokAuthRefreshError.classified("""{"error":"refresh_token_reused"}""")
        )
    }

    @Test
    fun superGrokModelCatalogNormalization() {
        assertEquals(
            "grok-4.3",
            com.porarri.yamabikochat.data.remote.SuperGrokModelCatalog.normalizedModelId("supergrok/grok-4.3")
        )
        assertEquals(
            "grok-build-0.1",
            com.porarri.yamabikochat.data.remote.SuperGrokModelCatalog.modelFor("grok-build-0.1")?.id
        )
        assertEquals(
            "grok-4.5",
            com.porarri.yamabikochat.data.remote.SuperGrokModelCatalog.modelFor("grok-4.5")?.id
        )
        assertEquals(
            true,
            com.porarri.yamabikochat.data.remote.SuperGrokModelCatalog.modelFor("grok-4.5")?.supportsReasoning
        )
    }

    private fun makeJwt(exp: Long): String {
        val header = base64Url("""{"alg":"none","typ":"JWT"}""")
        val payload = base64Url("""{"exp":$exp}""")
        return "$header.$payload.sig"
    }

    private fun base64Url(value: String): String =
        Base64.getUrlEncoder().withoutPadding().encodeToString(value.toByteArray())
}