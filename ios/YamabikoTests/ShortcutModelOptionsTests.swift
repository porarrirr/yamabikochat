import XCTest
@testable import YamabikoChat

final class ShortcutModelOptionsTests: XCTestCase {
    func testGeminiOptionsIncludeCurrentSettingsSavedModelAndCatalog() {
        var settings = AppSettings()
        settings.apiProvider = "GEMINI"
        settings.defaultModel = "custom-gemini-model"
        settings.providerDefaultModelsJSON = #"{"GEMINI":"saved-gemini-model"}"#

        let options = ShortcutModelOptionsBuilder.modelOptions(
            provider: "GEMINI",
            settings: settings,
            openRouterModels: []
        )

        XCTAssertTrue(options.contains("custom-gemini-model"))
        XCTAssertTrue(options.contains("saved-gemini-model"))
        XCTAssertTrue(options.contains("gemini-2.5-flash"))
        XCTAssertEqual(options.first, "custom-gemini-model")
    }

    func testOpenRouterOptionsPreferCachedModelsOverFallback() {
        var settings = AppSettings()
        settings.apiProvider = "OPENROUTER"
        settings.defaultModel = "openai/gpt-4o-mini"
        let cached = [
            SimpleModel(
                id: "cached/model-a",
                name: "Cached A",
                provider: "cached",
                topProvider: nil,
                contextLength: 1,
                promptPricePerMillion: 0,
                completionPricePerMillion: 0,
                isFree: false,
                availableProviders: [],
                availableQuantizations: []
            )
        ]

        let options = ShortcutModelOptionsBuilder.modelOptions(
            provider: "OPENROUTER",
            settings: settings,
            openRouterModels: cached
        )

        XCTAssertEqual(options.first, "openai/gpt-4o-mini")
        XCTAssertTrue(options.contains("cached/model-a"))
        XCTAssertFalse(options.contains("anthropic/claude-3.5-sonnet"))
    }

    func testOpenRouterOptionsUseFallbackWhenCacheEmpty() {
        let settings = AppSettings()
        let options = ShortcutModelOptionsBuilder.modelOptions(
            provider: "OPENROUTER",
            settings: settings,
            openRouterModels: []
        )

        XCTAssertTrue(options.contains("openai/gpt-4o"))
        XCTAssertTrue(options.contains("meta-llama/llama-3.1-8b-instruct:free"))
    }

    func testAppleIntelligenceOptionsOnlyIncludeDisplayModel() {
        let settings = AppSettings()
        let options = ShortcutModelOptionsBuilder.modelOptions(
            provider: "APPLE_INTELLIGENCE",
            settings: settings,
            openRouterModels: []
        )

        XCTAssertEqual(options, [AppleIntelligenceModelCatalog.displayModel])
    }

    func testProviderOptionsIncludeAppleIntelligence() {
        let options = ShortcutModelOptionsBuilder.providerOptions()
        XCTAssertTrue(options.contains(where: { $0.key == "APPLE_INTELLIGENCE" }))
        XCTAssertEqual(options.count, ProviderCatalog.options.count)
    }

    func testOpenCodeGoOptionsIncludeCatalogModels() {
        let settings = AppSettings()
        let options = ShortcutModelOptionsBuilder.modelOptions(
            provider: "OPENCODE_GO",
            settings: settings,
            openRouterModels: []
        )

        XCTAssertTrue(options.contains(OpenCodeGoModelCatalog.defaultModel))
        XCTAssertTrue(options.contains("deepseek-v4-flash"))
    }
}
