import XCTest
@testable import YamabikoChat

final class CodexModelCatalogTests: XCTestCase {
    func testVisiblePresetsMatchReferenceCatalogAndDefault() {
        let preset = CodexModelCatalog.visiblePresets()
            .first { $0.model == "gpt-5.6-sol" }

        XCTAssertNotNil(preset)
        XCTAssertEqual(preset?.displayName, "GPT-5.6-Sol")
        XCTAssertEqual(preset?.defaultReasoningEffort, "low")
        XCTAssertEqual(preset?.supportedReasoningEfforts.map(\.effort), ["low", "medium", "high", "xhigh", "max", "ultra"])
        XCTAssertEqual(CodexModelCatalog.defaultModel(), "gpt-5.6-sol")
        XCTAssertEqual(CodexModelCatalog.visiblePresets().map(\.model), ["gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5", "gpt-5.4", "gpt-5.4-mini", "gpt-5.2"])
        XCTAssertTrue(CodexModelCatalog.supportsReasoningSummary("gpt-5.6-sol"))
        XCTAssertTrue(CodexModelCatalog.supportsTextVerbosity("gpt-5.6-sol"))
    }

    func testFindPresetMatchesGpt56SolCaseInsensitively() {
        let preset = CodexModelCatalog.findPreset(" GPT-5.6-SOL ")

        XCTAssertEqual(preset?.model, "gpt-5.6-sol")
    }
}
