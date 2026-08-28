import XCTest
@testable import YamabikoChat

final class UserFacingErrorFormatterTests: XCTestCase {
    private let quotaJSON = """
    {"error":{"code":429,"message":"Resource has been exhausted (e.g. check quota).","status":"RESOURCE_EXHAUSTED"}}
    """

    func testFormats429QuotaJSONWithProviderWrappers() {
        let raw = "Response parse failed: Pi provider failed: \(quotaJSON)"
        let formatted = UserFacingErrorFormatter.format(raw)

        XCTAssertEqual(formatted.title, L10n.text("利用上限に達しました"))
        XCTAssertEqual(formatted.summary, L10n.text("プランまたは課金設定を確認してください。"))
        XCTAssertTrue(formatted.hasDetail)
        XCTAssertTrue(formatted.detail.contains("RESOURCE_EXHAUSTED"))
        XCTAssertFalse(formatted.summary.contains("{"))
        XCTAssertFalse(formatted.summary.contains("Response parse failed"))
    }

    func testFormatsEscaped429JSON() {
        let escaped = quotaJSON
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        let raw = "Response parse failed: Pi provider failed: \(escaped)"
        let formatted = UserFacingErrorFormatter.format(raw)

        XCTAssertEqual(formatted.title, L10n.text("利用上限に達しました"))
        XCTAssertEqual(formatted.summary, L10n.text("プランまたは課金設定を確認してください。"))
        XCTAssertTrue(formatted.detail.contains("429"))
    }

    func testFormats401AuthenticationJSON() {
        let raw = """
        Response parse failed: Pi agent failed: {"error":{"code":401,"message":"API key not valid. Please pass a valid API key.","status":"UNAUTHENTICATED"}}
        """
        let formatted = UserFacingErrorFormatter.format(raw)

        XCTAssertEqual(formatted.title, L10n.text("認証に失敗しました"))
        XCTAssertEqual(formatted.summary, L10n.text("ログインまたはAPIキーを確認してください。"))
        XCTAssertTrue(formatted.detail.contains("UNAUTHENTICATED"))
    }

    func testFormatsHTTPStatusWithoutJSON() {
        let formatted = UserFacingErrorFormatter.format("HTTP 503: upstream unavailable")

        XCTAssertEqual(formatted.title, L10n.text("サーバーエラー"))
        XCTAssertEqual(formatted.summary, L10n.text("しばらくしてから再試行してください。"))
        XCTAssertEqual(formatted.detail, "HTTP 503: upstream unavailable")
    }

    func testPiRuntimeStartupAndResumeFailuresTellTheUserToRestartTheApp() {
        for reason in [
            "Pi agent runtime did not start",
            "Pi agent runtime did not resume"
        ] {
            let raw = "Response parse failed: \(reason)"
            let formatted = UserFacingErrorFormatter.format(raw)

            XCTAssertEqual(formatted.title, L10n.text("AIを起動できませんでした"))
            XCTAssertEqual(
                formatted.summary,
                L10n.text("アプリを再起動して、もう一度お試しください。")
            )
            XCTAssertEqual(formatted.detail, raw)
        }
    }

    func testPiRuntimeRestartGuidanceSurvivesPlaceholderRoundTrip() {
        let placeholder = UserFacingErrorFormatter.placeholder(
            for: ProviderClientError.parseFailure("Pi agent runtime did not resume")
        )
        let formatted = UserFacingErrorFormatter.format(placeholder)

        XCTAssertEqual(formatted.title, L10n.text("AIを起動できませんでした"))
        XCTAssertEqual(
            formatted.summary,
            L10n.text("アプリを再起動して、もう一度お試しください。")
        )
    }

    func testLeavesShortJapaneseErrorsUnchanged() {
        let raw = L10n.format("添付ファイルが%.1fMBで上限10MBを超えています。", 12.3)
        let formatted = UserFacingErrorFormatter.format(raw)

        XCTAssertEqual(formatted.summary, raw)
        XCTAssertFalse(formatted.hasDetail)
        XCTAssertFalse(formatted.summary.contains("{"))
    }

    func testPlainStringFallsBackWhenNotHumanReadableJSON() {
        let raw = String(repeating: "x", count: 400)
        let formatted = UserFacingErrorFormatter.format(raw)

        XCTAssertEqual(formatted.summary, L10n.text("応答を取得できませんでした"))
        XCTAssertEqual(formatted.detail, raw)
    }

    func testPlainShortEnglishErrorPassesThrough() {
        let formatted = UserFacingErrorFormatter.format("Conversation not found")

        XCTAssertEqual(formatted.summary, "Conversation not found")
        XCTAssertFalse(formatted.hasDetail)
    }

    func testPlaceholderUsesSummaryAndLooksLikeChatError() {
        let error = ProviderClientError.parseFailure("Pi provider failed: \(quotaJSON)")
        let placeholder = UserFacingErrorFormatter.placeholder(for: error)

        XCTAssertTrue(placeholder.hasPrefix("エラー:") || placeholder.hasPrefix("Error:"))
        XCTAssertTrue(placeholder.contains(L10n.text("プランまたは課金設定を確認してください。")))
        XCTAssertFalse(placeholder.contains("{"))
        XCTAssertTrue(UserFacingErrorFormatter.looksLikeChatError(placeholder))
        XCTAssertTrue(UserFacingErrorFormatter.looksLikeChatError("Response parse failed: \(quotaJSON)"))
        XCTAssertFalse(UserFacingErrorFormatter.looksLikeChatError("通常のアシスタント応答です。"))
    }

    func testFormatsHistoricalErrorPrefixPlusRawJSON() {
        let raw = L10n.format("エラー: %@", "Response parse failed: Pi provider failed: \(quotaJSON)")
        let formatted = UserFacingErrorFormatter.format(raw)

        XCTAssertEqual(formatted.title, L10n.text("利用上限に達しました"))
        XCTAssertTrue(formatted.hasDetail)
    }

    func testDoesNotTreatHTTPStatusInProseAsChatError() {
        let prose = "REST APIs often return HTTP 200 OK when a request succeeds. HTTP 404 means not found."
        XCTAssertFalse(UserFacingErrorFormatter.looksLikeChatError(prose))
        XCTAssertFalse(
            UserFacingErrorFormatter.looksLikeChatError(
                prose + String(repeating: " More explanation.", count: 40)
            )
        )
    }

    func testTreatsWholeMessageHTTPStatusAsChatError() {
        XCTAssertTrue(UserFacingErrorFormatter.looksLikeChatError("HTTP 503: upstream unavailable"))
        XCTAssertTrue(UserFacingErrorFormatter.looksLikeChatError("エラー: HTTP 503: upstream unavailable"))
    }

    func testRoundTripPlaceholderRestoresQuotaTitleWithoutRedundantDetail() {
        let error = ProviderClientError.parseFailure("Pi provider failed: \(quotaJSON)")
        let placeholder = UserFacingErrorFormatter.placeholder(for: error)
        let formatted = UserFacingErrorFormatter.format(placeholder)

        XCTAssertEqual(formatted.title, L10n.text("利用上限に達しました"))
        XCTAssertEqual(formatted.summary, L10n.text("プランまたは課金設定を確認してください。"))
        XCTAssertFalse(formatted.hasDetail)
        XCTAssertTrue(UserFacingErrorFormatter.looksLikeChatError(placeholder))
    }

    func testDetectsFrenchAndChineseErrorPrefixes() {
        XCTAssertTrue(
            UserFacingErrorFormatter.looksLikeChatError(
                "Erreur : Vérifiez votre forfait ou les paramètres de facturation."
            )
        )
        XCTAssertTrue(UserFacingErrorFormatter.looksLikeChatError("错误：请检查套餐或账单设置。"))
    }

    func testFormatRestoresQuotaCategoryFromLocalizedPlaceholder() {
        let formatted = UserFacingErrorFormatter.format(
            "Erreur : Vérifiez votre forfait ou les paramètres de facturation."
        )

        XCTAssertEqual(formatted.title, L10n.text("利用上限に達しました"))
        XCTAssertEqual(formatted.summary, L10n.text("プランまたは課金設定を確認してください。"))
        XCTAssertFalse(formatted.hasDetail)
    }
}
