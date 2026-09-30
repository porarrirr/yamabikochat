import XCTest
@testable import YamabikoChat

final class CodexModelCatalogTests: XCTestCase {
    func testVisiblePresetsMatchPiCatalogAndDefault() {
        let preset = CodexModelCatalog.visiblePresets()
            .first { $0.model == "gpt-5.6-sol" }

        XCTAssertNotNil(preset)
        XCTAssertEqual(preset?.displayName, "GPT-5.6 Sol")
        XCTAssertEqual(preset?.defaultReasoningEffort, "low")
        XCTAssertEqual(preset?.supportedReasoningEfforts.map(\.effort), ["low", "medium", "high", "xhigh", "max"])
        XCTAssertEqual(CodexModelCatalog.defaultModel(), "gpt-6-sol")
        XCTAssertEqual(CodexModelCatalog.visiblePresets().map(\.model), ["gpt-6-sol", "gpt-6-astra", "gpt-6-luna", "gpt-5.6-sol", "gpt-5.6-terra", "gpt-5.6-luna", "gpt-5.5"])
        XCTAssertTrue(CodexModelCatalog.supportsReasoningSummary("gpt-5.6-sol"))
        XCTAssertTrue(CodexModelCatalog.supportsTextVerbosity("gpt-5.6-sol"))
    }

    func testRuntimeCatalogCanAddNewPiModelWithoutEditingPresets() {
        let models = [PiCodexModel(id: "future-codex-model", name: "Future Codex Model", supported: false, reason: "pi_model_missing")]
        let preset = CodexModelCatalog.visiblePresets(from: models).first
        XCTAssertEqual(preset?.model, "future-codex-model")
        XCTAssertEqual(preset?.displayName, "Future Codex Model")
        XCTAssertFalse(preset?.isSupported ?? true)
        XCTAssertEqual(preset?.unsupportedReason, "pi_model_missing")
        XCTAssertEqual(preset?.supportedReasoningEfforts, [])
    }

    func testAccountCatalogPreservesServerOrderingAndDisplayNames() {
        let models = [PiCodexModel(id: "gpt-5.5", name: "Account GPT", supported: true), PiCodexModel(id: "gpt-6-sol", name: "Account Sol", supported: true)]
        XCTAssertEqual(CodexModelCatalog.visiblePresets(from: models).map(\.model), ["gpt-5.5", "gpt-6-sol"])
        XCTAssertEqual(CodexModelCatalog.visiblePresets(from: models).map(\.displayName), ["Account GPT", "Account Sol"])
        XCTAssertTrue(CodexModelCatalog.visiblePresets(from: []).isEmpty)
    }

    func testSavedUltraEffortFallsBackToPiSupportedLevel() {
        XCTAssertEqual(CodexModelCatalog.resolvedReasoningEffort("ultra", model: "gpt-6-sol"), "medium")
        XCTAssertEqual(CodexModelCatalog.resolvedReasoningEffort("MAX", model: "gpt-6-sol"), "max")
    }

    func testFindPresetMatchesGpt56SolCaseInsensitively() {
        let preset = CodexModelCatalog.findPreset(" GPT-5.6-SOL ")

        XCTAssertEqual(preset?.model, "gpt-5.6-sol")
    }
}
