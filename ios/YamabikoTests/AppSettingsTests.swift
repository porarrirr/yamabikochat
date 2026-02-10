import XCTest
@testable import YamabikoChat

final class AppSettingsTests: XCTestCase {
    func testCurrentModelUsesProviderMapFallback() {
        var settings = AppSettings()
        settings.apiProvider = "OPENAI"
        settings.defaultModel = "gpt-4o-mini"
        settings.providerDefaultModelsJSON = "{}"

        XCTAssertEqual(settings.currentModel(), "gpt-4o-mini")
    }

    func testSelectedCompatBaseURLReturnsPresetURL() {
        var settings = AppSettings()
        settings.openAICompatPresetsJSON = "[{\"name\":\"internal\",\"baseURL\":\"https://example.com/v1/\"}]"
        settings.selectedOpenAICompatPreset = "internal"

        XCTAssertEqual(settings.selectedCompatBaseURL()?.absoluteString, "https://example.com/v1/")
    }

    func testNormalizedForPersistenceDisablesAutoConversationWhenDualIsEnabled() {
        var settings = AppSettings()
        settings.isDualModeEnabled = true
        settings.isAutoConversationEnabled = true

        let normalized = settings.normalizedForPersistence()

        XCTAssertTrue(normalized.isDualModeEnabled)
        XCTAssertFalse(normalized.isAutoConversationEnabled)
    }

    func testResolvedOpenAIBaseURLFallsBackWhenInvalid() {
        var settings = AppSettings()
        settings.openAIBaseURL = "   "

        XCTAssertEqual(settings.resolvedOpenAIBaseURL(), AppConstants.defaultOpenAIBaseURL.absoluteString)
    }

    func testResolvedMiniMaxBaseURLFallsBackWhenInvalid() {
        var settings = AppSettings()
        settings.miniMaxBaseURL = "not-a-url"

        XCTAssertEqual(settings.resolvedMiniMaxBaseURL(), AppConstants.defaultMiniMaxBaseURL.absoluteString)
    }

    func testPreferredProvidersListRespectsNormalizationAndSelectionMax() {
        var settings = AppSettings()
        settings.providerSelectionMax = 2

        settings.setPreferredProvidersList([" OpenAI ", "anthropic", "openai", "google"])

        XCTAssertEqual(settings.preferredProvidersList(), ["openai", "anthropic"])
    }

    func testSelectedQuantizationsListRoundTrips() {
        var settings = AppSettings()
        settings.setSelectedQuantizationsList([" int8 ", "fp16", "int8"])

        XCTAssertEqual(settings.selectedQuantizationsList(), ["int8", "fp16"])
    }

    func testBuildGlobalProviderPresetsUsesProviderMapOrder() {
        var settings = AppSettings()
        settings.providerDefaultModelsJSON = #"{"OPENAI":"gpt-4o-mini","GEMINI":"gemini-2.5-flash","OPENROUTER":"deepseek/deepseek-chat"}"#

        let presets = settings.buildGlobalProviderPresets()

        XCTAssertEqual(presets.map(\.apiProvider), ["GEMINI", "OPENROUTER", "OPENAI"])
        XCTAssertEqual(presets.first?.name, "グローバル: Google Gemini")
    }

    func testProviderSpecificGlobalPresetVisibilityOverridesDefault() {
        var settings = AppSettings()
        settings.showGlobalProviderPresetsInChat = false

        XCTAssertFalse(settings.shouldShowGlobalProviderPresetInChat(provider: "GEMINI"))

        settings.setShowGlobalProviderPresetInChat(provider: "GEMINI", visible: true)

        XCTAssertTrue(settings.shouldShowGlobalProviderPresetInChat(provider: "gemini"))
        XCTAssertFalse(settings.shouldShowGlobalProviderPresetInChat(provider: "OPENAI"))
    }
}
