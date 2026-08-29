import XCTest
@testable import YamabikoChat

final class SvgPreviewSanitizerTests: XCTestCase {
    func testSvgDownloadDocumentEncodesContentAsUTF8() {
        let input = #"<svg viewBox="0 0 10 10"><text>山彦</text></svg>"#
        let document = SvgDownloadDocument(svgContent: input)

        XCTAssertEqual(String(data: document.data, encoding: .utf8), input)
    }

    func testSanitizeRemovesScriptTags() {
        let input = #"<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script><rect width="10" height="10"/></svg>"#
        let sanitized = SvgPreviewSanitizer.sanitize(input)

        XCTAssertFalse(sanitized.lowercased().contains("<script"))
        XCTAssertTrue(sanitized.contains("<rect"))
    }

    func testSanitizeRemovesEventHandlerAttributes() {
        let input = #"<svg><rect onclick="x()" onload='y()' width="10" height="10"/></svg>"#
        let sanitized = SvgPreviewSanitizer.sanitize(input)

        XCTAssertFalse(sanitized.lowercased().contains("onclick="))
        XCTAssertFalse(sanitized.lowercased().contains("onload="))
    }

    func testSanitizeRemovesJavascriptScheme() {
        let input = #"<svg><a href="javascript:alert(1)">x</a></svg>"#
        let sanitized = SvgPreviewSanitizer.sanitize(input)

        XCTAssertFalse(sanitized.lowercased().contains("javascript:"))
    }

    func testSanitizeAllowsHashHrefAndBlocksExternalHref() {
        let input = ##"<svg><use href="#shape"/><use href="https://evil.example/a.svg#shape"/></svg>"##
        let sanitized = SvgPreviewSanitizer.sanitize(input)

        XCTAssertTrue(sanitized.contains("href=\"#shape\""))
        XCTAssertFalse(sanitized.contains("evil.example"))
    }

    func testSanitizeBlocksExternalUrlFunction() {
        let input = #"<svg><rect fill="url(http://evil.example/a)"/><rect fill="url(#grad1)"/></svg>"#
        let sanitized = SvgPreviewSanitizer.sanitize(input)

        XCTAssertTrue(sanitized.contains("fill=\"none\""))
        XCTAssertTrue(sanitized.contains("url(#grad1)"))
    }

    func testInlineHTMLUsesMermaidStyleSizingAndLockedViewport() {
        let html = SvgPreviewHTMLBuilder.buildHTML(
            svgContent: #"<svg viewBox="0 0 10 10"></svg>"#,
            maxHeight: 360,
            allowsZoom: false
        )

        XCTAssertTrue(html.contains("maximum-scale=1"))
        XCTAssertTrue(html.contains("user-scalable=no"))
        XCTAssertTrue(html.contains("width: 100%; max-width: 100%; max-height: 360px; height: auto;"))
        XCTAssertTrue(html.contains("connect-src 'none'"))
    }

    func testExpandedHTMLAllowsZoomAndUsesViewportHeight() {
        let html = SvgPreviewHTMLBuilder.buildHTML(
            svgContent: #"<svg viewBox="0 0 10 10"></svg>"#,
            maxHeight: 360,
            allowsZoom: true
        )

        XCTAssertTrue(html.contains("maximum-scale=5"))
        XCTAssertTrue(html.contains("user-scalable=yes"))
        XCTAssertTrue(html.contains("max-height: calc(100vh - 24px)"))
    }
}
