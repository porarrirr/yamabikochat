import XCTest
@testable import YamabikoChat

final class ProviderEnumTests: XCTestCase {
    func testProviderNormalization() {
        XCTAssertEqual(LLMProvider(rawOrDefault: "openrouter"), .openRouter)
        XCTAssertEqual(LLMProvider(rawOrDefault: "CODEX_AUTH"), .codexAuth)
        XCTAssertEqual(LLMProvider(rawOrDefault: "unknown"), .gemini)
    }
}