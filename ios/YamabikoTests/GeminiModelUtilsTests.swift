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

    func testGemini3FlashSupportsMinimalThinkingLevel() {
        let model = "gemini-3-flash"

        XCTAssertTrue(GeminiModelUtils.isThinkingSupported(model: model))
        XCTAssertTrue(GeminiModelUtils.isThinkingLevelSupported(model: model))
        XCTAssertFalse(GeminiModelUtils.isThinkingAlwaysOn(model: model))
        XCTAssertEqual(GeminiModelUtils.getThinkingLevelOptions(model: model), ["minimal", "low", "medium", "high"])
        XCTAssertEqual(GeminiModelUtils.getMinimalThinkingLevel(model: model), "minimal")
        XCTAssertEqual(GeminiModelUtils.normalizeThinkingLevel(model: model, level: " Medium "), "medium")
        XCTAssertNil(GeminiModelUtils.normalizeThinkingLevel(model: model, level: "budget"))
    }

    func testGemini25FlashCanDisableThinkingButHasNoLevelOptions() {
        let model = "gemini-2.5-flash"

        XCTAssertTrue(GeminiModelUtils.isThinkingSupported(model: model))
        XCTAssertFalse(GeminiModelUtils.isThinkingAlwaysOn(model: model))
        XCTAssertTrue(GeminiModelUtils.canDisableThinking(model: model))
        XCTAssertFalse(GeminiModelUtils.isThinkingLevelSupported(model: model))
        XCTAssertEqual(GeminiModelUtils.getThinkingLevelOptions(model: model), [])
        XCTAssertNil(GeminiModelUtils.getMinimalThinkingLevel(model: model))
        XCTAssertEqual(
            GeminiModelUtils.calculateEffectiveThinkingBudget(
                model: model,
                userThinkingEnabled: false,
                userThinkingBudget: 2048
            ),
            0
        )
    }

    func testNonGeminiModelsDoNotSupportGeminiThinking() {
        let models = ["claude-3.5-sonnet", "gemma-3", "gpt-5"]

        for model in models {
            XCTAssertFalse(GeminiModelUtils.isThinkingSupported(model: model))
            XCTAssertFalse(GeminiModelUtils.isThinkingLevelSupported(model: model))
            XCTAssertFalse(GeminiModelUtils.canDisableThinking(model: model))
            XCTAssertNil(
                GeminiModelUtils.calculateEffectiveThinkingBudget(
                    model: model,
                    userThinkingEnabled: true,
                    userThinkingBudget: 1024
                )
            )
        }
    }
}
