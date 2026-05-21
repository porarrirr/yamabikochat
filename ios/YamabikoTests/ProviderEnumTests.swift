import XCTest
@testable import YamabikoChat

final class ProviderEnumTests: XCTestCase {
    func testProviderNormalization() {
        XCTAssertEqual(LLMProvider(rawOrDefault: "openrouter"), .openRouter)
        XCTAssertEqual(LLMProvider(rawOrDefault: "opencode_go"), .openCodeGo)
        XCTAssertEqual(LLMProvider(rawOrDefault: "alibaba_coding_plan"), .alibabaCodingPlan)
        XCTAssertEqual(LLMProvider(rawOrDefault: "gemini_auth"), .gemini)
        XCTAssertEqual(LLMProvider(rawOrDefault: "qwen_code"), .openRouter)
        XCTAssertEqual(LLMProvider(rawOrDefault: "CODEX_AUTH"), .codexAuth)
        XCTAssertEqual(LLMProvider(rawOrDefault: "apple_intelligence"), .appleIntelligence)
        XCTAssertEqual(LLMProvider(rawOrDefault: "unknown"), .gemini)
    }
}
