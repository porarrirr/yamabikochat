import XCTest
@testable import YamabikoChat

final class GeminiModelUtilsTests: XCTestCase {
    func testGemini31ProPreviewIsRecognizedAsGemini3ThinkingModel() {
        let model = "gemini-3.1-pro-preview"

        XCTAssertTrue(GeminiModelUtils.isThinkingSupported(model: model))
        XCTAssertTrue(GeminiModelUtils.isThinkingLevelSupported(model: model))
        XCTAssertTrue(GeminiModelUtils.isThinkingAlwaysOn(model: model))
        XCTAssertEqual(GeminiModelUtils.getDefaultThinkingLevel(model: model), "high")
        XCTAssertEqual(GeminiModelUtils.getThinkingLevelOptions(model: model), ["low", "high"])
    }
}
