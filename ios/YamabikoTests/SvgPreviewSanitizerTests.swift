import XCTest
import WebKit
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
        XCTAssertTrue(html.contains("id=\"yamabiko-svg-preview-root\""))
        XCTAssertTrue(html.contains("connect-src 'none'"))
    }

    func testHeightBridgeMeasuresPreviewRootInsteadOfDocumentViewport() {
        let script = SvgPreviewHeightBridge.measurementScript

        XCTAssertTrue(script.contains("getElementById('yamabiko-svg-preview-root')"))
        XCTAssertTrue(script.contains("root.getBoundingClientRect().height"))
        XCTAssertTrue(script.contains("new ResizeObserver(reportHeight).observe(root)"))
        XCTAssertFalse(script.contains("document.body.scrollHeight"))
        XCTAssertFalse(script.contains("document.documentElement.scrollHeight"))
    }

    @MainActor
    func testHeightBridgeReportsRenderedSVGHeightWhenViewportIsTaller() async throws {
        let expectation = expectation(description: "SVG content height")
        let recorder = SvgHeightMessageRecorder(expectation: expectation)
        let userContentController = WKUserContentController()
        userContentController.addUserScript(WKUserScript(
            source: SvgPreviewHeightBridge.measurementScript,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
        userContentController.add(recorder, name: SvgPreviewHeightBridge.messageName)

        let configuration = YamabikoWebKitSupport.makeConfiguration(
            userContentController: userContentController
        )
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 320, height: 360),
            configuration: configuration
        )
        webView.loadHTMLString(
            SvgPreviewHTMLBuilder.buildHTML(
                svgContent: #"<svg viewBox="0 0 2 1"></svg>"#,
                maxHeight: 360,
                allowsZoom: false
            ),
            baseURL: nil
        )

        await fulfillment(of: [expectation], timeout: 5)
        let reportedHeight = try XCTUnwrap(recorder.height)
        XCTAssertEqual(reportedHeight, 172, accuracy: 1)
        XCTAssertLessThan(reportedHeight, webView.bounds.height)
        userContentController.removeScriptMessageHandler(forName: SvgPreviewHeightBridge.messageName)
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

private final class SvgHeightMessageRecorder: NSObject, WKScriptMessageHandler {
    let expectation: XCTestExpectation
    private(set) var height: CGFloat?

    init(expectation: XCTestExpectation) {
        self.expectation = expectation
    }

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard height == nil, let value = message.body as? NSNumber else { return }
        height = CGFloat(truncating: value)
        expectation.fulfill()
    }
}
