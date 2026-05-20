import XCTest
@testable import YamabikoChat

final class SvgPreviewSanitizerTests: XCTestCase {
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
}
