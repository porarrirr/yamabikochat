import XCTest
@testable import YamabikoChat

final class ReasoningEffortOptionsTests: XCTestCase {
    func testModelsDevProviderUsesCatalogEfforts() {
        let model = CatalogModel(
            id: "glm-5.3",
            name: "GLM-5.3",
            reasoningOptions: [CatalogReasoningOption(type: "effort", values: ["low", "HIGH", " max ", "low"])],
            inputModalities: ["text"],
            outputModalities: ["text"],
            limits: CatalogLimits(),
            cost: CatalogCost()
        )
        let provider = CatalogProvider(
            id: "opencode-go",
            name: "OpenCode Go",
            npm: "@ai-sdk/openai-compatible",
            env: ["OPENCODE_GO_API_KEY"],
            models: [model]
        )

        XCTAssertEqual(
            ReasoningEffortOptions.options(
                provider: "MODELS_DEV:OPENCODE-GO",
                model: "glm-5.3",
                catalogProviders: [provider]
            ),
            ["low", "high", "max"]
        )
    }

    func testModelsDevProviderWithoutCatalogModelHasNoOptions() {
        let provider = CatalogProvider(
            id: "opencode-go",
            name: "OpenCode Go",
            npm: "@ai-sdk/openai-compatible",
            env: [],
            models: []
        )

        XCTAssertEqual(
            ReasoningEffortOptions.options(
                provider: "MODELS_DEV:opencode-go",
                model: "glm-5.3",
                catalogProviders: [provider]
            ),
            []
        )
    }

    func testCodexProviderUsesAccountCatalogLevels() {
        let models = [
            PiCodexModel(
                id: "gpt-6-luna",
                name: "GPT-6-Luna",
                supported: true,
                reason: nil,
                supportedThinkingLevels: ["low", "medium", "high", "xhigh", "max"]
            )
        ]

        XCTAssertEqual(
            ReasoningEffortOptions.options(provider: "CODEX_AUTH", model: "gpt-6-luna", codexModels: models),
            ["low", "medium", "high", "xhigh", "max"]
        )
    }

    func testCodexProviderWithoutAccountCatalogHasNoOptions() {
        XCTAssertEqual(
            ReasoningEffortOptions.options(provider: "CODEX_AUTH", model: "gpt-6-luna", codexModels: []),
            []
        )
    }

    func testSuperGrokUsesSharedLevels() {
        XCTAssertEqual(ReasoningEffortOptions.superGrok, ["low", "medium", "high"])
        XCTAssertEqual(
            ReasoningEffortOptions.options(provider: "SUPERGROK", model: "grok-4.5"),
            ReasoningEffortOptions.superGrok
        )
    }

    func testUnsupportedProviderOrEmptyModelHasNoOptions() {
        XCTAssertEqual(ReasoningEffortOptions.options(provider: "OPENROUTER", model: "deepseek/deepseek-chat"), [])
        XCTAssertEqual(ReasoningEffortOptions.options(provider: "CODEX_AUTH", model: "  "), [])
    }
}
