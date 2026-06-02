import XCTest
@testable import YamabikoChat

final class CodexModelCatalogTests: XCTestCase {
    func testVisiblePresetsIncludeGpt53CodexSpark() {
        let preset = CodexModelCatalog.visiblePresets()
            .first { $0.model == "gpt-5.3-codex-spark" }

        XCTAssertNotNil(preset)
        XCTAssertEqual(preset?.displayName, "gpt-5.3-codex-spark")
        XCTAssertEqual(preset?.defaultReasoningEffort, "medium")
        XCTAssertEqual(preset?.supportedReasoningEfforts.map(\.effort), ["medium", "high"])
        XCTAssertTrue(CodexModelCatalog.supportsReasoningSummary("gpt-5.3-codex-spark"))
        XCTAssertTrue(CodexModelCatalog.supportsTextVerbosity("gpt-5.3-codex-spark"))
    }

    func testFindPresetMatchesGpt53CodexSparkCaseInsensitively() {
        let preset = CodexModelCatalog.findPreset(" GPT-5.3-CODEX-SPARK ")

        XCTAssertEqual(preset?.model, "gpt-5.3-codex-spark")
    }
}
