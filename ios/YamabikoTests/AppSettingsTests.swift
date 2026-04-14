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
        settings.providerDefaultModelsJSON = #"{"OPENAI":"gpt-4o-mini","GEMINI":"gemini-2.5-flash","OPENROUTER":"deepseek/deepseek-chat","ALIBABA_CODING_PLAN":"qwen3.5-plus"}"#

        let presets = settings.buildGlobalProviderPresets()

        XCTAssertEqual(presets.map(\.apiProvider), ["GEMINI", "OPENROUTER", "ALIBABA_CODING_PLAN", "OPENAI"])
        XCTAssertEqual(presets.first?.name, L10n.format("グローバル: %@", "Google Gemini"))
    }

    func testBuildGlobalProviderPresetsPlacesQwenBeforeOpenRouter() {
        var settings = AppSettings()
        settings.providerDefaultModelsJSON = #"{"OPENROUTER":"deepseek/deepseek-chat","QWEN_CODE":"coder-model","GEMINI_AUTH":"gemini-2.5-flash"}"#

        let presets = settings.buildGlobalProviderPresets()

        XCTAssertEqual(presets.map(\.apiProvider), ["GEMINI_AUTH", "QWEN_CODE", "OPENROUTER"])
        XCTAssertEqual(presets[1].model, "coder-model")
    }

    func testProviderSpecificGlobalPresetVisibilityOverridesDefault() {
        var settings = AppSettings()
        settings.showGlobalProviderPresetsInChat = false

        XCTAssertFalse(settings.shouldShowGlobalProviderPresetInChat(provider: "GEMINI"))

        settings.setShowGlobalProviderPresetInChat(provider: "GEMINI", visible: true)

        XCTAssertTrue(settings.shouldShowGlobalProviderPresetInChat(provider: "gemini"))
        XCTAssertFalse(settings.shouldShowGlobalProviderPresetInChat(provider: "OPENAI"))
    }

    func testNormalizedForPersistenceNormalizesDualLayoutAndRatio() {
        var settings = AppSettings()
        settings.dualSplitLayout = "invalid"
        settings.dualSplitRatio = 3.0

        let normalized = settings.normalizedForPersistence()

        XCTAssertEqual(normalized.dualSplitLayout, "VERTICAL")
        XCTAssertEqual(normalized.dualSplitRatio, 0.9, accuracy: 0.0001)
    }

    func testNormalizedForPersistenceNormalizesDualOverrideValues() {
        var settings = AppSettings()
        settings.dualOpenRouterReasoningModeA = "unexpected"
        settings.dualOpenRouterReasoningModeB = "EFFORT"
        settings.dualOpenRouterReasoningEffortA = " "
        settings.dualCodexReasoningEffortB = " HIGH "
        settings.dualThinkingLevelA = " "
        settings.dualThinkingLevelB = " high "
        settings.dualThinkingBudgetA = -3

        let normalized = settings.normalizedForPersistence()

        XCTAssertNil(normalized.dualOpenRouterReasoningModeA)
        XCTAssertEqual(normalized.dualOpenRouterReasoningModeB, "effort")
        XCTAssertNil(normalized.dualOpenRouterReasoningEffortA)
        XCTAssertEqual(normalized.dualCodexReasoningEffortB, "high")
        XCTAssertNil(normalized.dualThinkingLevelA)
        XCTAssertEqual(normalized.dualThinkingLevelB, "high")
        XCTAssertEqual(normalized.dualThinkingBudgetA, 0)
    }

    func testNormalizedForPersistenceNormalizesAutoOverrideValues() {
        var settings = AppSettings()
        settings.autoOpenRouterReasoningModeA = "unexpected"
        settings.autoOpenRouterReasoningModeB = "BUDGET"
        settings.autoOpenRouterReasoningEffortA = " "
        settings.autoCodexReasoningEffortB = " HIGH "
        settings.autoThinkingLevelA = " "
        settings.autoThinkingLevelB = " high "
        settings.autoThinkingBudgetA = -5
        settings.autoOpenRouterThinkingBudgetB = -8

        let normalized = settings.normalizedForPersistence()

        XCTAssertNil(normalized.autoOpenRouterReasoningModeA)
        XCTAssertEqual(normalized.autoOpenRouterReasoningModeB, "budget")
        XCTAssertNil(normalized.autoOpenRouterReasoningEffortA)
        XCTAssertEqual(normalized.autoCodexReasoningEffortB, "high")
        XCTAssertNil(normalized.autoThinkingLevelA)
        XCTAssertEqual(normalized.autoThinkingLevelB, "high")
        XCTAssertEqual(normalized.autoThinkingBudgetA, 0)
        XCTAssertEqual(normalized.autoOpenRouterThinkingBudgetB, 0)
    }

    func testNormalizedForPersistenceNormalizesAlibabaRemoteMCPSettings() {
        var settings = AppSettings()
        settings.alibabaMCPServerURL = " https://mcp.firecrawl.dev/fc-key/v2/mcp "
        settings.alibabaMCPServerName = " "
        settings.alibabaMCPAllowedToolsCSV = "search,\n extract , SEARCH "

        let normalized = settings.normalizedForPersistence()

        XCTAssertEqual(normalized.resolvedAlibabaMCPServerURL(), "https://mcp.firecrawl.dev/fc-key/v2/mcp")
        XCTAssertEqual(normalized.resolvedAlibabaMCPServerName(), AppConstants.alibabaMCPDefaultServerName)
        XCTAssertEqual(normalized.alibabaMCPAllowedToolsList(), ["search", "extract"])
    }

    func testResolvedAlibabaMCPServerURLRejectsHostlessAndCredentialedURLs() {
        var settings = AppSettings()
        settings.alibabaMCPServerURL = "https://"
        XCTAssertNil(settings.resolvedAlibabaMCPServerURL())

        settings.alibabaMCPServerURL = "https://user:pass@example.com/mcp"
        XCTAssertNil(settings.resolvedAlibabaMCPServerURL())
    }

    func testAutoContextOverridesResolveFromAutoFields() {
        var settings = AppSettings()
        settings.autoGoogleSearchEnabledA = true
        settings.autoCodeExecutionEnabledA = false
        settings.autoThinkingEnabledB = true
        settings.autoThinkingBudgetB = 42
        settings.autoThinkingLevelB = "low"
        settings.autoOpenRouterReasoningModeA = "effort"
        settings.autoOpenRouterReasoningEffortA = "high"

        let toolOverrideA = settings.toolOverride(for: .autoA)
        XCTAssertEqual(toolOverrideA.googleSearch, true)
        XCTAssertEqual(toolOverrideA.codeExecution, false)

        let thinkingOverrideB = settings.thinkingOverride(for: .autoB)
        XCTAssertEqual(thinkingOverrideB.enabled, true)
        XCTAssertEqual(thinkingOverrideB.budget, 42)
        XCTAssertEqual(thinkingOverrideB.level, "low")

        let openRouterOverrideA = settings.openRouterOverride(for: .autoA)
        XCTAssertEqual(openRouterOverrideA.mode, "effort")
        XCTAssertEqual(openRouterOverrideA.effort, "high")
    }
}
