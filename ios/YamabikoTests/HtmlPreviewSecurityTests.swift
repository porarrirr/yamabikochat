import XCTest
@testable import YamabikoChat

final class HtmlPreviewSecurityTests: XCTestCase {
    func testSandboxInjectsDefaultDenyContentSecurityPolicy() {
        let html = HtmlPreviewWebView.Coordinator.sandbox(
            "<html><head><title>Preview</title></head><body>Hello</body></html>"
        )

        XCTAssertTrue(html.contains("default-src 'none'"))
        XCTAssertTrue(html.contains("connect-src 'none'"))
        XCTAssertTrue(html.contains("frame-src 'none'"))
        XCTAssertTrue(html.contains("form-action 'none'"))
    }
}
