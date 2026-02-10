import XCTest
@testable import YamabikoChat

final class SettingsViewModelTests: XCTestCase {
    func testGeminiQuotaMissingCredentialErrorIsDetected() {
        XCTAssertTrue(
            SettingsViewModel.isGeminiQuotaMissingCredentialError(
                ProviderClientError.missingCredential("GEMINI_AUTH")
            )
        )
        XCTAssertTrue(
            SettingsViewModel.isGeminiQuotaMissingCredentialError(
                ProviderClientError.missingCredential("gemini_auth")
            )
        )
    }

    func testGeminiQuotaMissingCredentialErrorIgnoresOtherErrors() {
        XCTAssertFalse(
            SettingsViewModel.isGeminiQuotaMissingCredentialError(
                ProviderClientError.missingCredential("GEMINI")
            )
        )
        XCTAssertFalse(
            SettingsViewModel.isGeminiQuotaMissingCredentialError(
                ProviderClientError.parseFailure("bad response")
            )
        )
    }
}
