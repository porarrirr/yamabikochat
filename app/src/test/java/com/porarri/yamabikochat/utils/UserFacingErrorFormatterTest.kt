package com.porarri.yamabikochat.utils

import com.porarri.yamabikochat.data.model.ProviderClientError
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class UserFacingErrorFormatterTest {
    private val quotaJson =
        """{"error":{"code":429,"message":"Resource has been exhausted (e.g. check quota).","status":"RESOURCE_EXHAUSTED"}}"""
    private val copy = UserFacingErrorCopy.Default

    @Test
    fun formats429QuotaJsonWithProviderWrappers() {
        val raw = "Response parse failed: Pi provider failed: $quotaJson"
        val formatted = UserFacingErrorFormatter.format(raw, copy)

        assertEquals(copy.quotaTitle, formatted.title)
        assertEquals(copy.quotaSummary, formatted.summary)
        assertTrue(formatted.hasDetail)
        assertTrue(formatted.detail.contains("RESOURCE_EXHAUSTED"))
        assertFalse(formatted.summary.contains("{"))
        assertFalse(formatted.summary.contains("Response parse failed"))
    }

    @Test
    fun formatsEscaped429Json() {
        val escaped = quotaJson
            .replace("\\", "\\\\")
            .replace("\"", "\\\"")
            .replace("\n", "\\n")
        val raw = "Response parse failed: Pi provider failed: $escaped"
        val formatted = UserFacingErrorFormatter.format(raw, copy)

        assertEquals(copy.quotaTitle, formatted.title)
        assertEquals(copy.quotaSummary, formatted.summary)
        assertTrue(formatted.detail.contains("429"))
    }

    @Test
    fun formats401AuthenticationJson() {
        val raw =
            """Response parse failed: Pi agent failed: {"error":{"code":401,"message":"API key not valid. Please pass a valid API key.","status":"UNAUTHENTICATED"}}"""
        val formatted = UserFacingErrorFormatter.format(raw, copy)

        assertEquals(copy.authTitle, formatted.title)
        assertEquals(copy.authSummary, formatted.summary)
        assertTrue(formatted.detail.contains("UNAUTHENTICATED"))
    }

    @Test
    fun formatsHttpStatusWithoutJson() {
        val formatted = UserFacingErrorFormatter.format("HTTP 503: upstream unavailable", copy)

        assertEquals(copy.serverTitle, formatted.title)
        assertEquals(copy.serverSummary, formatted.summary)
        assertEquals("HTTP 503: upstream unavailable", formatted.detail)
    }

    @Test
    fun leavesShortJapaneseErrorsUnchanged() {
        val raw = "ファイルサイズが12.3MBで、10MB制限を超えています。より小さなファイルを選択してください。"
        val formatted = UserFacingErrorFormatter.format(raw, copy)

        assertEquals(raw, formatted.summary)
        assertFalse(formatted.hasDetail)
        assertFalse(formatted.summary.contains("{"))
    }

    @Test
    fun plainStringFallsBackWhenNotHumanReadable() {
        val raw = "x".repeat(400)
        val formatted = UserFacingErrorFormatter.format(raw, copy)

        assertEquals(copy.fallbackSummary, formatted.summary)
        assertEquals(raw, formatted.detail)
    }

    @Test
    fun plainShortEnglishErrorPassesThrough() {
        val formatted = UserFacingErrorFormatter.format("Conversation not found", copy)

        assertEquals("Conversation not found", formatted.summary)
        assertFalse(formatted.hasDetail)
    }

    @Test
    fun placeholderUsesSummaryAndLooksLikeChatError() {
        val error = ProviderClientError.ParseFailure("Pi provider failed: $quotaJson")
        val placeholder = UserFacingErrorFormatter.placeholder(error, copy)

        assertTrue(placeholder.startsWith("エラー:"))
        assertTrue(placeholder.contains(copy.quotaSummary))
        assertFalse(placeholder.contains("{"))
        assertTrue(UserFacingErrorFormatter.looksLikeChatError(placeholder))
        assertTrue(UserFacingErrorFormatter.looksLikeChatError("Response parse failed: $quotaJson"))
        assertFalse(UserFacingErrorFormatter.looksLikeChatError("通常のアシスタント応答です。"))
    }

    @Test
    fun formatsHistoricalErrorPrefixPlusRawJson() {
        val raw = "エラー: Response parse failed: Pi provider failed: $quotaJson"
        val formatted = UserFacingErrorFormatter.format(raw, copy)

        assertEquals(copy.quotaTitle, formatted.title)
        assertTrue(formatted.hasDetail)
    }

    @Test
    fun doesNotTreatHttpStatusInProseAsChatError() {
        val prose = "REST APIs often return HTTP 200 OK when a request succeeds. HTTP 404 means not found."
        assertFalse(UserFacingErrorFormatter.looksLikeChatError(prose))
        assertFalse(
            UserFacingErrorFormatter.looksLikeChatError(
                prose + " " + "More explanation. ".repeat(40)
            )
        )
    }

    @Test
    fun treatsWholeMessageHttpStatusAsChatError() {
        assertTrue(UserFacingErrorFormatter.looksLikeChatError("HTTP 503: upstream unavailable"))
        assertTrue(UserFacingErrorFormatter.looksLikeChatError("エラー: HTTP 503: upstream unavailable"))
    }

    @Test
    fun roundTripPlaceholderRestoresQuotaTitleWithoutRedundantDetail() {
        val error = ProviderClientError.ParseFailure("Pi provider failed: $quotaJson")
        val placeholder = UserFacingErrorFormatter.placeholder(error, copy)
        val formatted = UserFacingErrorFormatter.format(placeholder, copy)

        assertEquals(copy.quotaTitle, formatted.title)
        assertEquals(copy.quotaSummary, formatted.summary)
        assertFalse(formatted.hasDetail)
        assertTrue(UserFacingErrorFormatter.looksLikeChatError(placeholder))
    }

    @Test
    fun detectsFrenchAndChineseErrorPrefixes() {
        assertTrue(
            UserFacingErrorFormatter.looksLikeChatError(
                "Erreur : Vérifiez votre forfait ou les paramètres de facturation."
            )
        )
        assertTrue(
            UserFacingErrorFormatter.looksLikeChatError("错误：请检查套餐或账单设置。")
        )
    }

    @Test
    fun formatRestoresQuotaCategoryFromLocalizedPlaceholder() {
        val formatted = UserFacingErrorFormatter.format(
            "Erreur : Vérifiez votre forfait ou les paramètres de facturation.",
            copy
        )

        assertEquals(copy.quotaTitle, formatted.title)
        assertEquals(copy.quotaSummary, formatted.summary)
        assertFalse(formatted.hasDetail)
    }
}
