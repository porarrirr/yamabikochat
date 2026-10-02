import XCTest
@testable import YamabikoChat

final class CodexModelCatalogTests: XCTestCase {
    func testAccountCatalogPreservesServerOrderingAndDisplayNames() {
        let models = [PiCodexModel(id: "gpt-5.5", name: "Account GPT", supported: true), PiCodexModel(id: "gpt-6-sol", name: "Account Sol", supported: true)]
        XCTAssertEqual(CodexModelCatalog.visiblePresets(from: models).map(\.model), ["gpt-5.5", "gpt-6-sol"])
        XCTAssertEqual(CodexModelCatalog.visiblePresets(from: models).map(\.displayName), ["Account GPT", "Account Sol"])
        XCTAssertTrue(CodexModelCatalog.visiblePresets(from: []).isEmpty)
    }

    func testRuntimeCatalogModelWithoutContractStaysDisabled() {
        let models = [PiCodexModel(id: "future-codex-model", name: "Future Codex Model", supported: false, reason: "pi_model_missing")]
        let preset = CodexModelCatalog.visiblePresets(from: models).first
        XCTAssertEqual(preset?.model, "future-codex-model")
        XCTAssertEqual(preset?.displayName, "Future Codex Model")
        XCTAssertFalse(preset?.isSupported ?? true)
        XCTAssertEqual(preset?.unsupportedReason, "pi_model_missing")
        XCTAssertEqual(preset?.supportedReasoningEfforts, [])
    }

    func testDefaultModelIsOnlyAnInitialDefault() {
        XCTAssertEqual(CodexModelCatalog.defaultModel(), "gpt-6.1-sol")
        let models = [
            PiCodexModel(id: "gpt-6.1-sol", name: "Sol", supported: true),
            PiCodexModel(id: "gpt-5.5", name: "GPT", supported: true)
        ]
        let presets = CodexModelCatalog.visiblePresets(from: models)
        XCTAssertEqual(presets.first(where: { $0.model == "gpt-6.1-sol" })?.isDefault, true)
        XCTAssertEqual(presets.first(where: { $0.model == "gpt-5.5" })?.isDefault, false)
    }

    func testDefaultReasoningEffortPrefersMediumThenFirstLevel() {
        let models = [
            PiCodexModel(id: "a", name: "A", supported: true, supportedThinkingLevels: ["low", "medium", "high"]),
            PiCodexModel(id: "b", name: "B", supported: true, supportedThinkingLevels: ["xhigh", "max"]),
            PiCodexModel(id: "c", name: "C", supported: true)
        ]
        let presets = CodexModelCatalog.visiblePresets(from: models)
        XCTAssertEqual(presets[0].defaultReasoningEffort, "medium")
        XCTAssertEqual(presets[1].defaultReasoningEffort, "xhigh")
        XCTAssertEqual(presets[2].defaultReasoningEffort, "off")
    }

    func testResolvedReasoningEffortUsesAccountCatalogLevels() {
        let models = [
            PiCodexModel(id: "gpt-6.1-sol", name: "Sol", supported: true, supportedThinkingLevels: ["low", "medium", "high", "xhigh", "max"])
        ]
        XCTAssertEqual(CodexModelCatalog.resolvedReasoningEffort("MAX", model: "gpt-6.1-sol", models: models), "max")
        XCTAssertEqual(CodexModelCatalog.resolvedReasoningEffort("ultra", model: "gpt-6.1-sol", models: models), "medium")
    }

    func testResolvedReasoningEffortFallsBackToModelDefaultWhenUnsupported() {
        let models = [
            PiCodexModel(id: "limited", name: "Limited", supported: true, supportedThinkingLevels: ["xhigh"])
        ]
        XCTAssertEqual(CodexModelCatalog.resolvedReasoningEffort("low", model: "limited", models: models), "xhigh")
    }

    func testResolvedReasoningEffortIsUnchangedWhenModelIsNotInCatalog() {
        XCTAssertEqual(CodexModelCatalog.resolvedReasoningEffort(" HIGH ", model: "unknown", models: []), "high")
        XCTAssertEqual(CodexModelCatalog.resolvedReasoningEffort("ultra", model: "unknown", models: []), "ultra")
    }

    func testModelsDevContractsPreserveModelProviderContract() {
        let provider = CatalogProvider(
            id: "openai",
            name: "OpenAI",
            npm: "@ai-sdk/openai",
            api: "https://api.openai.com/v1",
            env: ["OPENAI_API_KEY"],
            models: [
                CatalogModel(
                    id: "gpt-6.1-sol",
                    name: "GPT 6.1 Sol",
                    reasoning: true,
                    reasoningOptions: [
                        CatalogReasoningOption(type: "effort", values: ["low", "medium", "high", "xhigh", "max"])
                    ],
                    toolCall: true,
                    inputModalities: ["text", "image", "pdf"],
                    outputModalities: ["text"],
                    limits: CatalogLimits(context: 1_050_000, input: nil, output: 128_000),
                    cost: CatalogCost(
                        inputPerMillion: nil, outputPerMillion: nil, reasoningPerMillion: nil,
                        cacheReadPerMillion: nil, cacheWritePerMillion: nil
                    ),
                    providerContract: CatalogModelProviderContract(
                        npm: "@ai-sdk/openai",
                        api: "https://api.openai.com/v1",
                        provenance: "provider"
                    )
                )
            ]
        )
        let contracts = CodexModelCatalog.modelsDevContracts(from: provider)
        let contract = contracts["gpt-6.1-sol"]
        XCTAssertEqual(contracts.count, 1)
        XCTAssertEqual(contract?.providerName, "OpenAI")
        XCTAssertEqual(contract?.npm, "@ai-sdk/openai")
        XCTAssertEqual(contract?.api, "https://api.openai.com/v1")
        XCTAssertEqual(contract?.provenance, "provider")
        XCTAssertEqual(contract?.name, "GPT 6.1 Sol")
        XCTAssertEqual(contract?.reasoning, true)
        XCTAssertEqual(contract?.toolCall, true)
        XCTAssertEqual(contract?.input, ["text", "image", "pdf"])
        XCTAssertEqual(contract?.contextWindow, 1_050_000)
        XCTAssertEqual(contract?.maxTokens, 128_000)
        XCTAssertEqual(contract?.reasoningEfforts, ["low", "medium", "high", "xhigh", "max"])
    }

    func testModelsDevContractsAreEmptyWithoutAProvider() {
        XCTAssertTrue(CodexModelCatalog.modelsDevContracts(from: nil).isEmpty)
    }

    func testSupportsReasoningSummaryAndTextVerbosityStayModelPrefixed() {
        XCTAssertTrue(CodexModelCatalog.supportsReasoningSummary("gpt-5.6-sol"))
        XCTAssertTrue(CodexModelCatalog.supportsTextVerbosity("gpt-5.6-sol"))
        XCTAssertFalse(CodexModelCatalog.supportsReasoningSummary("gpt-6.1-sol"))
    }
}
