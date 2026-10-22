import XCTest
import GRDB
@testable import YamabikoChat

final class AppSettingsTests: XCTestCase {
    func testRetiringFusionPreservesConversationAndIgnoresLegacySettings() throws {
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database, upTo: "v32_context_compaction")
        let repository = SettingsRepository(dbQueue: database)
        try repository.save(AppSettings())
        let conversations = ConversationRepository(dbQueue: database)
        let conversationID = try conversations.createConversation(
            title: "Historical Fusion", model: "saved-model", provider: "OPENAI", systemPrompt: nil
        )
        _ = try conversations.insertMessage(ChatMessage(
            conversationId: conversationID, role: "model", text: "Saved answer", createdAtMs: 1
        ))
        try database.write { db in
            try db.execute(sql: "UPDATE settings SET isFusionModeEnabled = 1, fusionCustomPresetJSON = '{invalid}' WHERE id = 1")
        }

        try AppDatabase.migrator.migrate(database)
        let loaded = try repository.load()
        XCTAssertEqual(ChatMode(settings: loaded), .standard)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(loaded)) as? [String: Any])
        XCTAssertNil(encoded["isFusionModeEnabled"])
        XCTAssertNil(encoded["fusionCustomPresetJSON"])
        let savedText = try database.read { db in
            try String.fetchOne(db, sql: "SELECT text FROM chat_messages WHERE conversationId = ?", arguments: [conversationID])
        }
        XCTAssertEqual(savedText, "Saved answer")
        let legacyEnabled = try database.read { db in
            try Bool.fetchOne(db, sql: "SELECT isFusionModeEnabled FROM settings WHERE id = 1")
        }
        XCTAssertEqual(legacyEnabled, false)
        try repository.save(loaded)
        XCTAssertEqual(try repository.load(), loaded)
    }

    func testRetiredMathPreferenceDoesNotAffectSettings() throws {
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database)
        let repository = SettingsRepository(dbQueue: database)
        let original = AppSettings().normalizedForPersistence()
        try repository.save(original)

        // Existing databases may still contain the old disabled preference.
        try database.write { db in
            try db.execute(sql: "UPDATE settings SET mathRenderingEnabled = 0 WHERE id = 1")
        }
        let loaded = try repository.load()
        XCTAssertEqual(loaded, original)
        let encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(loaded)) as? [String: Any])
        XCTAssertNil(encoded["mathRenderingEnabled"])
        try repository.save(loaded)
        XCTAssertEqual(try repository.load(), original)
    }

    func testNormalizationIsStableAcrossSaveAndReload() throws {
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database)
        let repository = SettingsRepository(dbQueue: database)
        var settings = AppSettings()
        settings.providerDefaultModelsJSON = #"{"OPENROUTER":"saved-router-model","OPENAI":"saved-openai-model","GEMINI":"saved-gemini-model"}"#
        settings.showGlobalProviderPresetsInChatByProviderJSON = #"{"OPENROUTER":true,"OPENAI":false,"GEMINI":true}"#
        let normalized = settings.normalizedForPersistence()

        try repository.save(normalized)
        let reloaded = try repository.load()

        XCTAssertEqual(reloaded, normalized, "Saving unchanged settings must not look like an external edit")
        XCTAssertEqual(reloaded.normalizedForPersistence(), reloaded)
    }

    func testGenUIToolDefaultsAndPersistence() throws {
        XCTAssertTrue(AppSettings().genUIToolEnabled)
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database)
        let repository = SettingsRepository(dbQueue: database)
        for enabled in [false, true, false] {
            var settings = AppSettings()
            settings.apiProvider = "OPENAI"
            settings.genUIToolEnabled = enabled
            try repository.save(settings)
            XCTAssertEqual(try repository.load().genUIToolEnabled, enabled)
        }
    }

    func testGenUIMigrationPreservesExistingSettings() throws {
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database, upTo: "v29_compact_pi_diagnostics")
        var existing = AppSettings()
        existing.apiProvider = "OPENAI"
        existing.pythonToolEnabled = false
        existing.clientWebSearchToolEnabled = true
        try database.write { db in
            try db.execute(sql: "ALTER TABLE settings DROP COLUMN genUIToolEnabled")
            try LegacyURLSettingsFixture(settings: existing).save(db)
        }
        try AppDatabase.migrator.migrate(database)
        let settings = try database.read { db in try XCTUnwrap(AppSettings.fetchOne(db)) }
        XCTAssertTrue(settings.genUIToolEnabled)
        XCTAssertFalse(settings.pythonToolEnabled)
        XCTAssertTrue(settings.clientWebSearchToolEnabled)
    }

    func testPythonToolIsEnabledByDefault() {
        XCTAssertTrue(AppSettings().pythonToolEnabled)
    }

    func testPCCPythonMigrationEnablesExistingPCCSettingOnly() throws {
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database, upTo: "v27_pcc_reasoning")
        var settings = AppSettings()
        settings.apiProvider = "APPLE_INTELLIGENCE"
        settings.defaultModel = AppleIntelligenceModelCatalog.pccModel
        settings.pythonToolEnabled = false
        try database.write { db in try LegacyURLSettingsFixture(settings: settings).save(db) }

        try AppDatabase.migrator.migrate(database)

        let migrated = try database.read { db in try AppSettings.fetchOne(db)! }
        XCTAssertTrue(migrated.pythonToolEnabled)
    }

    func testPCCPythonMigrationPreservesExplicitlyDisabledNonPCCSetting() throws {
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database, upTo: "v27_pcc_reasoning")
        var settings = AppSettings()
        settings.apiProvider = "OPENAI"
        settings.defaultModel = "gpt-5.6"
        settings.pythonToolEnabled = false
        try database.write { db in try LegacyURLSettingsFixture(settings: settings).save(db) }

        try AppDatabase.migrator.migrate(database)

        let migrated = try database.read { db in try AppSettings.fetchOne(db)! }
        XCTAssertFalse(migrated.pythonToolEnabled)
    }

    func testNormalizationClearsRemovedGeminiComputerUseAndJSONSettings() {
        var settings = AppSettings()
        settings.geminiComputerUseEnabled = true
        settings.geminiResponseMimeType = "application/json"
        settings.geminiResponseJSONSchema = #"{"type":"object"}"#
        settings.geminiFunctionDeclarations = #"[{"name":"lookup"}]"#
        settings.dualComputerUseEnabledA = true
        settings.dualComputerUseEnabledB = false
        settings.autoComputerUseEnabledA = true
        settings.autoComputerUseEnabledB = false

        let normalized = settings.normalizedForPersistence()

        XCTAssertFalse(normalized.geminiComputerUseEnabled)
        XCTAssertTrue(normalized.geminiResponseMimeType.isEmpty)
        XCTAssertTrue(normalized.geminiResponseJSONSchema.isEmpty)
        XCTAssertTrue(normalized.geminiFunctionDeclarations.isEmpty)
        XCTAssertNil(normalized.dualComputerUseEnabledA)
        XCTAssertNil(normalized.dualComputerUseEnabledB)
        XCTAssertNil(normalized.autoComputerUseEnabledA)
        XCTAssertNil(normalized.autoComputerUseEnabledB)
    }

    func testNormalizationMigratesOnlyZaiLegacyModelIDs() throws {
        var settings = AppSettings()
        settings.apiProvider = "ZAI"
        settings.defaultModel = "glm-5.1"
        settings.dualProviderA = "ZAI"
        settings.dualModelA = "glm-5.1"
        settings.dualProviderB = "OPENCODE_GO"
        settings.dualModelB = "glm-5.1"
        settings.autoProviderA = "ZAI"
        settings.autoModelA = "glm-5.1"
        settings.providerDefaultModelsJSON = #"{"ZAI":"glm-5.1","OPENCODE_GO":"glm-5.1"}"#

        let normalized = settings.normalizedForPersistence()

        XCTAssertEqual(normalized.defaultModel, "glm-5.2")
        XCTAssertEqual(normalized.dualModelA, "glm-5.2")
        XCTAssertEqual(normalized.dualModelB, "glm-5.1")
        XCTAssertEqual(normalized.autoModelA, "glm-5.2")
        XCTAssertEqual(normalized.providerModelMap()["ZAI"], "glm-5.2")
        XCTAssertEqual(normalized.providerModelMap()["OPENCODE_GO"], "glm-5.1")
    }

    func testFreshDatabaseMigrationPersistsCurrentSettingsSchema() throws {
        let dbQueue = try DatabaseQueue()

        try AppDatabase.migrator.migrate(dbQueue)

        let settings = try dbQueue.read { db in
            try AppSettings.fetchOne(db, key: 1)
        }
        XCTAssertEqual(settings?.superGrokReasoningEnabled, true)
        XCTAssertEqual(settings?.superGrokReasoningEffort, "medium")
        XCTAssertEqual(settings?.isSystemPromptEnabled, true)
    }

    func testDisabledSystemPromptResolvesToNilWithoutDestroyingDraft() throws {
        var settings = AppSettings()
        settings.systemPrompt = "draft prompt"
        settings.systemPromptPresetsJSON = String(
            data: try JSONEncoder().encode([
                SystemPromptPreset(name: "Review", prompt: "preset prompt")
            ]),
            encoding: .utf8
        ) ?? "[]"
        settings.selectedSystemPromptPreset = "Review"
        settings.isSystemPromptEnabled = false

        XCTAssertNil(settings.effectiveSystemPrompt())
        XCTAssertEqual(settings.systemPrompt, "draft prompt")
        XCTAssertEqual(settings.selectedSystemPromptPreset, "Review")
    }

    func testBlankSelectedSystemPromptPresetFallsBackToTrimmedDraft() throws {
        var settings = AppSettings()
        settings.systemPrompt = "  draft prompt\n"
        settings.systemPromptPresetsJSON = String(
            data: try JSONEncoder().encode([
                SystemPromptPreset(name: "Review", prompt: "  \n")
            ]),
            encoding: .utf8
        ) ?? "[]"
        settings.selectedSystemPromptPreset = "Review"
        settings.isSystemPromptEnabled = true

        XCTAssertEqual(settings.effectiveSystemPrompt(), "draft prompt")
    }

    func testModelForProviderPreservesUnknownAppleIntelligenceIdentity() {
        var settings = AppSettings()
        settings.providerDefaultModelsJSON = #"{"APPLE_INTELLIGENCE":"legacy-model-id"}"#

        XCTAssertEqual(
            settings.modelForProvider("APPLE_INTELLIGENCE"),
            "legacy-model-id"
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

    func testNormalizedForPersistencePreservesExplicitAppleIntelligenceIdentity() {
        var settings = AppSettings()
        settings.apiProvider = "APPLE_INTELLIGENCE"
        settings.defaultModel = "gemini-2.5-flash"
        settings.providerDefaultModelsJSON = #"{"APPLE_INTELLIGENCE":"legacy-model-id"}"#

        let normalized = settings.normalizedForPersistence()

        XCTAssertEqual(normalized.defaultModel, "gemini-2.5-flash")
        XCTAssertEqual(
            normalized.modelForProvider("APPLE_INTELLIGENCE"),
            "gemini-2.5-flash"
        )
    }

    func testNormalizedForPersistenceDefaultsPCCReasoningLevelToModerateForPCCModel() {
        var settings = AppSettings()
        settings.apiProvider = "APPLE_INTELLIGENCE"
        settings.defaultModel = AppleIntelligenceModelCatalog.pccModel
        settings.pccReasoningLevel = nil

        let normalized = settings.normalizedForPersistence()

        XCTAssertEqual(normalized.defaultModel, AppleIntelligenceModelCatalog.pccModel)
        XCTAssertEqual(normalized.pccReasoningLevel, "moderate")
    }

    func testNormalizedForPersistenceSanitizesInvalidPCCReasoningLevel() {
        var settings = AppSettings()
        settings.apiProvider = "APPLE_INTELLIGENCE"
        settings.defaultModel = AppleIntelligenceModelCatalog.pccModel
        settings.pccReasoningLevel = "ultra"

        let normalized = settings.normalizedForPersistence()

        XCTAssertEqual(normalized.pccReasoningLevel, "moderate")
    }

    func testNormalizedForPersistencePreservesExplicitPCCReasoningLevels() {
        for level in ["light", "deep"] {
            var settings = AppSettings()
            settings.apiProvider = "APPLE_INTELLIGENCE"
            settings.defaultModel = AppleIntelligenceModelCatalog.pccModel
            settings.pccReasoningLevel = level

            let normalized = settings.normalizedForPersistence()

            XCTAssertEqual(normalized.pccReasoningLevel, level)
        }
    }

    func testDualAndAutoPCCReasoningSurvivesWithOnDevicePrimaryModel() {
        for side in 0..<4 {
            var settings = AppSettings()
            settings.apiProvider = "APPLE_INTELLIGENCE"
            settings.defaultModel = AppleIntelligenceModelCatalog.displayModel
            settings.pccReasoningLevel = "light"
            switch side {
            case 0:
                settings.dualProviderA = "APPLE_INTELLIGENCE"
                settings.dualModelA = AppleIntelligenceModelCatalog.pccModel
            case 1:
                settings.dualProviderB = "APPLE_INTELLIGENCE"
                settings.dualModelB = AppleIntelligenceModelCatalog.pccModel
            case 2:
                settings.autoProviderA = "APPLE_INTELLIGENCE"
                settings.autoModelA = AppleIntelligenceModelCatalog.pccModel
            default:
                settings.autoProviderB = "APPLE_INTELLIGENCE"
                settings.autoModelB = AppleIntelligenceModelCatalog.pccModel
            }
            XCTAssertEqual(settings.normalizedForPersistence().pccReasoningLevel, "light")
        }
        XCTAssertTrue(ProviderCatalog.dualAutoConversationOptions.contains { $0.key == "APPLE_INTELLIGENCE" })
    }

    func testCurrentModelUsesProviderMapFallback() {
        var settings = AppSettings()
        settings.apiProvider = "OPENAI"
        settings.defaultModel = "gpt-4o-mini"
        settings.providerDefaultModelsJSON = "{}"

        XCTAssertEqual(settings.currentModel(), "gpt-4o-mini")
    }

    func testCustomEndpointRoundTripKeepsExplicitProtocolAndCapabilities() throws {
        for api in ["anthropic-messages", "openai-completions", "openai-responses", "google-generative-ai", "mistral-conversations"] {
            var preset = OpenAICompatPreset(name: "Custom", baseURL: "https://example.com/v1")
            preset.apiProtocol = api
            preset.modelId = "private-model"
            preset.reasoning = true
            preset.reasoningEffort = "high"
            preset.vision = true
            preset.toolCall = true
            preset.temperature = 0.4
            XCTAssertNil(preset.validationError)
            let data = try JSONEncoder().encode(preset)
            XCTAssertEqual(try JSONDecoder().decode(OpenAICompatPreset.self, from: data), preset)
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            XCTAssertEqual(json["protocol"] as? String, api)
            XCTAssertEqual(json["baseUrl"] as? String, preset.baseURL)
        }
    }

    func testMigrationRemovesLegacyEndpointColumnsAndPreservesSettings() throws {
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database, upTo: "v29_compact_pi_diagnostics")
        var settings = AppSettings()
        settings.apiProvider = "SARASHINA"
        settings.defaultModel = "sarashina3-nano"
        settings.themeMode = "DARK"
        var custom = OpenAICompatPreset(name: "Current", baseURL: "https://current.example/v1")
        custom.apiProtocol = "openai-responses"
        custom.modelId = "custom-model"
        settings.openAICompatPresetsJSON = String(decoding: try JSONEncoder().encode([custom]), as: UTF8.self)
        settings.selectedOpenAICompatPreset = "Current"
        try database.write { db in try LegacyURLSettingsFixture(settings: settings).save(db) }
        try AppDatabase.migrator.migrate(database)
        try database.read { db in
            let columns = Set(try db.columns(in: "settings").map(\.name))
            XCTAssertFalse(columns.contains("openAIBaseURL"))
            XCTAssertFalse(columns.contains("miniMaxBaseURL"))
            let migrated = try XCTUnwrap(AppSettings.fetchOne(db))
            XCTAssertEqual(migrated.apiProvider, "SARASHINA")
            XCTAssertEqual(migrated.defaultModel, "sarashina3-nano")
            XCTAssertEqual(migrated.themeMode, "DARK")
            XCTAssertEqual(migrated.openAICompatPresets(), [custom])
            XCTAssertEqual(migrated.selectedOpenAICompatPreset, "Current")
        }
    }

    func testPersistenceDeletesURLOnlyPresetsWithoutSelectingAnotherEndpoint() throws {
        var settings = AppSettings()
        var retained = OpenAICompatPreset(name: "Current", baseURL: "https://example.com/v1")
        retained.apiProtocol = "openai-responses"
        retained.modelId = "private-model"
        settings.openAICompatPresetsJSON = String(decoding: try JSONEncoder().encode([OpenAICompatPreset(name: "Old", baseURL: "https://old.example/v1"), retained]), as: UTF8.self)
        settings.selectedOpenAICompatPreset = "Old"
        let normalized = settings.normalizedForPersistence()
        XCTAssertEqual(normalized.openAICompatPresets(), [retained])
        XCTAssertNil(normalized.selectedOpenAICompatPreset)
        XCTAssertEqual(normalized.normalizedForPersistence(), normalized)
    }

    func testCustomEndpointRejectsMissingProtocolAndInvalidBudget() {
        var preset = OpenAICompatPreset(name: "Local", baseURL: "http://localhost:8080/v1")
        preset.modelId = "private-model"
        XCTAssertNotNil(preset.validationError)
        preset.apiProtocol = "anthropic-messages"
        XCTAssertNil(preset.validationError)
        preset.reasoning = true
        preset.reasoningEffort = "high"
        preset.thinkingBudget = preset.maxTokens
        XCTAssertNotNil(preset.validationError)
        preset.thinkingBudget = 2048
        XCTAssertNil(preset.validationError)
        preset.baseURL = "https://user:secret@example.com/v1"
        XCTAssertNotNil(preset.validationError)
    }

    func testNormalizedForPersistenceDisablesAutoConversationWhenDualIsEnabled() {
        var settings = AppSettings()
        settings.isDualModeEnabled = true
        settings.isAutoConversationEnabled = true

        let normalized = settings.normalizedForPersistence()

        XCTAssertTrue(normalized.isDualModeEnabled)
        XCTAssertFalse(normalized.isAutoConversationEnabled)
    }

    func testNormalizedForPersistenceDisablesClientToolsWhenGeminiToolIsEnabled() {
        var settings = AppSettings()
        settings.apiProvider = "GEMINI"
        settings.clientWebSearchToolEnabled = true
        settings.pythonToolEnabled = true
        settings.geminiURLContextEnabled = true

        let normalized = settings.normalizedForPersistence()

        XCTAssertTrue(normalized.geminiURLContextEnabled)
        XCTAssertFalse(normalized.clientWebSearchToolEnabled)
        XCTAssertFalse(normalized.pythonToolEnabled)
        XCTAssertFalse(normalized.genUIToolEnabled)
    }

    func testNormalizedForPersistenceKeepsClientToolsForNonGeminiProvider() {
        var settings = AppSettings()
        settings.apiProvider = "OPENAI"
        settings.clientWebSearchToolEnabled = true
        settings.pythonToolEnabled = true
        settings.geminiURLContextEnabled = true

        let normalized = settings.normalizedForPersistence()

        XCTAssertTrue(normalized.clientWebSearchToolEnabled)
        XCTAssertTrue(normalized.pythonToolEnabled)
        XCTAssertTrue(normalized.genUIToolEnabled)
        XCTAssertTrue(normalized.geminiURLContextEnabled)
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

    func testBuildGlobalProviderPresetsUsesCurrentModelsDevModelWhenStoredEntryIsEmpty() {
        var settings = AppSettings()
        settings.apiProvider = "MODELS_DEV:anthropic"
        settings.defaultModel = "claude-sonnet-4-5"
        settings.providerDefaultModelsJSON = #"{"MODELS_DEV:ANTHROPIC":""}"#
        settings.showGlobalProviderPresetsInChat = false
        settings.setShowGlobalProviderPresetInChat(provider: settings.apiProvider, visible: true)

        let presets = settings.chatVisibleGlobalProviderPresets()

        XCTAssertEqual(presets.map(\.apiProvider), ["MODELS_DEV:ANTHROPIC"])
        XCTAssertEqual(presets.map(\.model), ["claude-sonnet-4-5"])
    }

    func testPersistencePreservesAppleIntelligenceInDualAutoProviders() {
        var settings = AppSettings()
        settings.dualProviderA = "APPLE_INTELLIGENCE"
        settings.dualProviderB = "apple_intelligence"
        settings.autoProviderA = "APPLE_INTELLIGENCE"
        settings.autoProviderB = "OPENROUTER"

        let normalized = settings.normalizedForPersistence()

        XCTAssertEqual(normalized.dualProviderA, "APPLE_INTELLIGENCE")
        XCTAssertEqual(normalized.dualProviderB, "APPLE_INTELLIGENCE")
        XCTAssertEqual(normalized.autoProviderA, "APPLE_INTELLIGENCE")
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

// Fixtures for historical schemas only; production settings no longer contain URL overrides.
struct LegacyURLSettingsFixture: PersistableRecord {
    static let databaseTableName = "settings"
    var settings: AppSettings
    func encode(to container: inout PersistenceContainer) throws {
        var current = container
        try settings.encode(to: &current)
        let fields = try JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as! [String: Any]
        for column in fields.keys where column != "genUIToolEnabled" {
            container[column] = current[column]
        }
        container["openAIBaseURL"] = "https://legacy.example/v1"
        container["miniMaxBaseURL"] = "https://legacy.example/anthropic"
    }
}
