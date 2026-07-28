import XCTest
import GRDB
@testable import YamabikoChat

final class AppSettingsTests: XCTestCase {
    func testFreshDatabaseMigrationPersistsCurrentSettingsSchema() throws {
        let dbQueue = try DatabaseQueue()

        try AppDatabase.migrator.migrate(dbQueue)

        let settings = try dbQueue.read { db in
            try AppSettings.fetchOne(db, key: 1)
        }
        XCTAssertEqual(settings?.superGrokReasoningEnabled, true)
        XCTAssertEqual(settings?.superGrokReasoningEffort, "medium")
    }

    func testModelForProviderReturnsAppleIntelligenceDisplayModel() {
        var settings = AppSettings()
        settings.providerDefaultModelsJSON = #"{"APPLE_INTELLIGENCE":"legacy-model-id"}"#

        XCTAssertEqual(
            settings.modelForProvider("APPLE_INTELLIGENCE"),
            AppleIntelligenceModelCatalog.displayModel
        )
    }

    func testModelForProviderReturnsMappedSuperGrokModel() {
        var settings = AppSettings()
        settings.providerDefaultModelsJSON = #"{"SUPERGROK":"grok-4.3"}"#
        settings.defaultModel = "grok-build-0.1"

        XCTAssertEqual(settings.modelForProvider("SUPERGROK"), "grok-4.3")
    }

    func testModelForProviderFallsBackToDefaultModelForSuperGrok() {
        var settings = AppSettings()
        settings.providerDefaultModelsJSON = "{}"
        settings.defaultModel = "grok-4.3"

        XCTAssertEqual(settings.modelForProvider("SUPERGROK"), "grok-4.3")
    }

    func testModelForProviderFallsBackToCatalogDefaultWhenSuperGrokBlank() {
        var settings = AppSettings()
        settings.providerDefaultModelsJSON = #"{"SUPERGROK":"  "}"#
        settings.defaultModel = "   "

        XCTAssertEqual(
            settings.modelForProvider("SUPERGROK"),
            SuperGrokModelCatalog.defaultModel
        )
    }

    func testNormalizedForPersistenceSanitizesSuperGrokReasoningEffort() {
        var settings = AppSettings()
        settings.superGrokReasoningEffort = "xhigh"

        let normalized = settings.normalizedForPersistence()
        XCTAssertEqual(normalized.superGrokReasoningEffort, "medium")
    }

    func testNormalizedForPersistenceAppliesAppleIntelligenceDisplayModel() {
        var settings = AppSettings()
        settings.apiProvider = "APPLE_INTELLIGENCE"
        settings.defaultModel = "gemini-2.5-flash"
        settings.providerDefaultModelsJSON = #"{"APPLE_INTELLIGENCE":"legacy-model-id"}"#

        let normalized = settings.normalizedForPersistence()

        XCTAssertEqual(normalized.defaultModel, AppleIntelligenceModelCatalog.displayModel)
        XCTAssertEqual(
            normalized.modelForProvider("APPLE_INTELLIGENCE"),
            AppleIntelligenceModelCatalog.displayModel
        )
    }

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

    func testNormalizedForPersistenceEnforcesSingleModeAmongDualAutoFusion() {
        var settings = AppSettings()
        settings.isFusionModeEnabled = true
        settings.isDualModeEnabled = true
        settings.isAutoConversationEnabled = true

        let normalized = settings.normalizedForPersistence()

        XCTAssertTrue(normalized.isDualModeEnabled)
        XCTAssertFalse(normalized.isAutoConversationEnabled)
        XCTAssertFalse(normalized.isFusionModeEnabled)
    }

    func testNormalizedForPersistenceDisablesFusionWhenAutoIsEnabled() {
        var settings = AppSettings()
        settings.isFusionModeEnabled = true
        settings.isAutoConversationEnabled = true

        let normalized = settings.normalizedForPersistence()

        XCTAssertTrue(normalized.isAutoConversationEnabled)
        XCTAssertFalse(normalized.isFusionModeEnabled)
    }

    func testNormalizedForPersistenceKeepsFusionWhenOnlyFusionEnabled() {
        var settings = AppSettings()
        settings.isFusionModeEnabled = true
        settings.fusionPresetName = "unknown"

        let normalized = settings.normalizedForPersistence()

        XCTAssertTrue(normalized.isFusionModeEnabled)
        XCTAssertEqual(normalized.fusionPresetName, FusionPresetLoader.presetLabel)
    }

    func testNormalizedForPersistenceKeepsCustomFusionPreset() {
        var settings = AppSettings()
        settings.fusionPresetName = "quality"
        settings.fusionCustomPresetJSON = ""

        let normalized = settings.normalizedForPersistence()

        XCTAssertEqual(normalized.fusionPresetName, FusionPresetLoader.presetLabel)
        XCTAssertFalse(normalized.fusionCustomPresetJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        XCTAssertNotNil(normalized.decodeFusionCustomPreset())
    }

    func testNormalizedForPersistenceReplacesInvalidCustomFusionJSON() {
        var settings = AppSettings()
        settings.fusionCustomPresetJSON = "{not-json"

        let normalized = settings.normalizedForPersistence()

        XCTAssertEqual(normalized.fusionPresetName, FusionPresetLoader.presetLabel)
        XCTAssertNotNil(normalized.decodeFusionCustomPreset())
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

    func testGeminiKeyNamesRoundTripsAndDeduplicates() {
        var settings = AppSettings()
        settings.setGeminiKeyNames([" slot-a ", "slot-b", "slot-a"])

        XCTAssertEqual(settings.geminiKeyNames(), ["slot-a", "slot-b"])
    }

    func testGeminiRotationModelsListRoundTripsAndDeduplicates() {
        var settings = AppSettings()
        settings.setGeminiRotationModelsList([" gemini-2.5-flash-lite ", "gemini-2.0-flash", "gemini-2.5-flash-lite"])

        XCTAssertEqual(settings.geminiRotationModelsList(), ["gemini-2.5-flash-lite", "gemini-2.0-flash"])
    }

    func testBuildGlobalProviderPresetsUsesProviderMapOrder() {
        var settings = AppSettings()
        settings.providerDefaultModelsJSON = #"{"OPENAI":"gpt-4o-mini","GEMINI":"gemini-2.5-flash","OPENROUTER":"deepseek/deepseek-chat","OPENCODE_GO":"glm-5.1","ALIBABA_CODING_PLAN":"qwen3.5-plus"}"#

        let presets = settings.buildGlobalProviderPresets()

        XCTAssertEqual(presets.map(\.apiProvider), ["GEMINI", "OPENROUTER", "OPENCODE_GO", "ALIBABA_CODING_PLAN", "OPENAI"])
        XCTAssertEqual(presets.first?.name, L10n.format("グローバル: %@", "Google Gemini"))
    }

    func testRemapRemovedProvidersMigratesAppleIntelligenceFromDualAutoProviders() {
        var settings = AppSettings()
        settings.dualProviderA = "APPLE_INTELLIGENCE"
        settings.dualProviderB = "apple_intelligence"
        settings.autoProviderA = "APPLE_INTELLIGENCE"
        settings.autoProviderB = "OPENROUTER"

        let normalized = settings.normalizedForPersistence()

        XCTAssertEqual(normalized.dualProviderA, "GEMINI")
        XCTAssertEqual(normalized.dualProviderB, "GEMINI")
        XCTAssertEqual(normalized.autoProviderA, "GEMINI")
        XCTAssertEqual(normalized.autoProviderB, "OPENROUTER")
    }

    func testRemapRemovedProvidersMigratesLegacyProviderKeys() {
        var settings = AppSettings()
        settings.apiProvider = "GEMINI_AUTH"
        settings.dualProviderA = "QWEN_CODE"
        settings.autoProviderB = "GEMINI_AUTH"
        settings.providerDefaultModelsJSON = #"{"GEMINI_AUTH":"gemini-2.5-flash","QWEN_CODE":"coder-model","OPENROUTER":"deepseek/deepseek-chat"}"#

        let normalized = settings.normalizedForPersistence()

        XCTAssertEqual(normalized.apiProvider, "GEMINI")
        XCTAssertEqual(normalized.dualProviderA, "OPENROUTER")
        XCTAssertEqual(normalized.autoProviderB, "GEMINI")
        XCTAssertEqual(normalized.modelForProvider("GEMINI"), "gemini-2.5-flash")
        XCTAssertEqual(normalized.modelForProvider("OPENROUTER"), "coder-model")
        XCTAssertNil(normalized.providerModelMap()["GEMINI_AUTH"])
        XCTAssertNil(normalized.providerModelMap()["QWEN_CODE"])
    }

    func testProviderSpecificGlobalPresetVisibilityOverridesDefault() {
        var settings = AppSettings()
        settings.showGlobalProviderPresetsInChat = false

        XCTAssertFalse(settings.shouldShowGlobalProviderPresetInChat(provider: "GEMINI"))

        settings.setShowGlobalProviderPresetInChat(provider: "GEMINI", visible: true)

        XCTAssertTrue(settings.shouldShowGlobalProviderPresetInChat(provider: "gemini"))
        XCTAssertFalse(settings.shouldShowGlobalProviderPresetInChat(provider: "OPENAI"))
    }

    func testChatVisibleGlobalProviderPresetsForDualAutoRespectsVisibilityAndSupportedProviders() {
        var settings = AppSettings()
        settings.providerDefaultModelsJSON =
            #"{"OPENAI":"gpt-4o-mini","GEMINI":"gemini-2.5-flash","OPENROUTER":"deepseek/deepseek-chat","APPLE_INTELLIGENCE":"default"}"#
        settings.showGlobalProviderPresetsInChat = false
        settings.setShowGlobalProviderPresetInChat(provider: "GEMINI", visible: true)
        settings.setShowGlobalProviderPresetInChat(provider: "OPENROUTER", visible: true)

        let presets = settings.chatVisibleGlobalProviderPresetsForDualAuto()

        XCTAssertEqual(presets.map(\.apiProvider), ["GEMINI", "OPENROUTER"])
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
