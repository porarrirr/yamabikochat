import XCTest
@testable import YamabikoChat

final class DiagnosticsLogSanitizerTests: XCTestCase {
    func testSanitizeRedactsBearerToken() {
        let input = "Authorization failed bearer abc.def-ghi_123"
        let sanitized = DiagnosticsLogSanitizer.sanitize(input)
        XCTAssertTrue(sanitized.contains("Bearer [REDACTED]"))
        XCTAssertFalse(sanitized.contains("abc.def-ghi_123"))
    }

    func testSanitizeRedactsSensitiveQueryItems() {
        let input = "/oauth2callback?state=secret-state&code=secret-code&foo=bar"
        let sanitized = DiagnosticsLogSanitizer.sanitize(input)
        XCTAssertTrue(sanitized.contains("state=[REDACTED]"))
        XCTAssertTrue(sanitized.contains("code=[REDACTED]"))
        XCTAssertTrue(sanitized.contains("foo=bar"))
        XCTAssertFalse(sanitized.contains("secret-code"))
    }

    func testSanitizeCallbackPathRedactsQuery() {
        let sanitized = DiagnosticsLogSanitizer.sanitizeCallbackPath("/auth/callback?code=abc&state=xyz")
        XCTAssertEqual(sanitized, "/auth/callback?[REDACTED]")
    }

    func testSanitizeCallbackPathWithoutQueryIsUnchanged() {
        let sanitized = DiagnosticsLogSanitizer.sanitizeCallbackPath("/auth/callback")
        XCTAssertEqual(sanitized, "/auth/callback")
    }
}
