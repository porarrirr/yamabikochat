import XCTest
import GRDB
@testable import YamabikoChat

private final class SettingsViewModelCredentialStore: SecureCredentialStore {
    private var storage: [String: String] = [:]

    func saveSecret(_ value: String?, key: String) throws {
        if let value {
            storage[key] = value
        } else {
            storage.removeValue(forKey: key)
        }
    }

    func readSecret(key: String) throws -> String? {
        storage[key]
    }

    func deleteSecret(key: String) throws {
        storage.removeValue(forKey: key)
    }
}

final class SettingsViewModelTests: XCTestCase {
    @MainActor
    func testSelectingNewSystemPromptClearsPreviousPresetDraft() throws {
        let viewModel = SettingsViewModel()
        viewModel.settings.systemPromptPresetsJSON = String(
            data: try JSONEncoder().encode([
                SystemPromptPreset(name: "Review", prompt: "Review carefully")
            ]),
            encoding: .utf8
        ) ?? "[]"
        viewModel.selectSystemPromptPreset("Review")

        viewModel.selectSystemPromptOption(SettingsViewModel.newSystemPromptSelection)

        XCTAssertTrue(viewModel.settings.isSystemPromptEnabled)
        XCTAssertNil(viewModel.settings.selectedSystemPromptPreset)
        XCTAssertNil(viewModel.settings.systemPrompt)
        XCTAssertEqual(viewModel.systemPromptPresetNameInput, "")
        XCTAssertEqual(viewModel.systemPromptPickerSelection, SettingsViewModel.newSystemPromptSelection)
    }

    @MainActor
    func testSelectingDisabledSystemPromptKeepsDraftButStopsApplyingIt() throws {
        let viewModel = SettingsViewModel()
        viewModel.settings.systemPromptPresetsJSON = String(
            data: try JSONEncoder().encode([
                SystemPromptPreset(name: "Review", prompt: "Review carefully")
            ]),
            encoding: .utf8
        ) ?? "[]"
        viewModel.selectSystemPromptPreset("Review")

        viewModel.selectSystemPromptOption(SettingsViewModel.disabledSystemPromptSelection)

        XCTAssertFalse(viewModel.settings.isSystemPromptEnabled)
        XCTAssertNil(viewModel.settings.effectiveSystemPrompt())
        XCTAssertEqual(viewModel.settings.selectedSystemPromptPreset, "Review")
        XCTAssertEqual(viewModel.systemPromptPickerSelection, SettingsViewModel.disabledSystemPromptSelection)
    }

    @MainActor
    func testSavingSelectedSystemPromptPresetRenamesInsteadOfDuplicatingIt() throws {
        let viewModel = SettingsViewModel()
        viewModel.settings.systemPromptPresetsJSON = String(
            data: try JSONEncoder().encode([
                SystemPromptPreset(name: "Review", prompt: "Old prompt")
            ]),
            encoding: .utf8
        ) ?? "[]"
        viewModel.selectSystemPromptPreset("Review")
        viewModel.systemPromptPresetNameInput = "Careful Review"
        viewModel.settings.systemPrompt = "New prompt"

        viewModel.addOrUpdateSystemPromptPreset()

        XCTAssertEqual(viewModel.systemPromptPresets, [
            SystemPromptPreset(name: "Careful Review", prompt: "New prompt")
        ])
        XCTAssertEqual(viewModel.settings.selectedSystemPromptPreset, "Careful Review")
    }

    @MainActor
    func testApplyFusionModelToAllSlotsUpdatesEveryExecutionRole() {
        let viewModel = SettingsViewModel()
        viewModel.ensureFusionCustomPresetInitialized()

        viewModel.applyFusionModelToAllSlots(provider: " openai ", modelId: " gpt-5 ")

        let preset = viewModel.fusionCustomPreset
        XCTAssertTrue(preset.panelModels.allSatisfy {
            $0.provider == "OPENAI" && $0.modelId == "gpt-5"
        })
        XCTAssertEqual(preset.judgeModel.provider, "OPENAI")
        XCTAssertEqual(preset.judgeModel.modelId, "gpt-5")
        XCTAssertEqual(preset.synthesizerModel.provider, "OPENAI")
        XCTAssertEqual(preset.synthesizerModel.modelId, "gpt-5")
    }

    @MainActor
    func testGeminiRotationCatalogProviderUsesModelsDevGoogleModels() throws {
        let providers = try ModelsDevCatalogRepository.parseCatalog(Data(Self.modelsDevGeminiFixture.utf8))
        let viewModel = SettingsViewModel()
        viewModel.modelsDevCatalogState = CatalogLoadState(
            availability: .ready,
            providers: providers
        )

        XCTAssertEqual(viewModel.geminiRotationCatalogProvider?.id, "google")
        XCTAssertEqual(
            viewModel.geminiRotationCatalogProvider?.models.map(\.id),
            ["gemini-model-from-models-dev"]
        )
    }

    @MainActor
    func testBindLoadsCurrentProviderApiKeyFromCredentialStore() throws {
        let fixture = try makeFixture()
        var settings = try fixture.repository.loadSettings()
        settings.apiProvider = "OPENROUTER"
        try fixture.repository.saveSettings(settings)
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)

        let viewModel = SettingsViewModel()
        viewModel.bind(repository: fixture.repository, credentialStore: fixture.credentials)

        XCTAssertEqual(viewModel.apiKeyDraft, "openrouter-key")
    }

    @MainActor
    func testSetProviderReloadsApiKeyDraftForSelectedProvider() async throws {
        let fixture = try makeFixture()
        var settings = try fixture.repository.loadSettings()
        settings.apiProvider = "OPENROUTER"
        try fixture.repository.saveSettings(settings)
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)
        try fixture.credentials.setCredential("openai-key", for: .openAI)

        let viewModel = SettingsViewModel()
        viewModel.bind(repository: fixture.repository, credentialStore: fixture.credentials)
        viewModel.setProvider("OPENAI")
        await Task.yield()

        XCTAssertEqual(viewModel.apiKeyDraft, "openai-key")
    }

    @MainActor
    func testSetProviderPreservesUnsavedDraftPerProvider() throws {
        let fixture = try makeFixture()
        let viewModel = SettingsViewModel()
        viewModel.bind(repository: fixture.repository, credentialStore: fixture.credentials)

        viewModel.apiKeyDraft = "gemini-unsaved"
        viewModel.setProvider("OPENAI")
        viewModel.apiKeyDraft = "openai-unsaved"
        viewModel.setProvider("GEMINI")

        XCTAssertEqual(viewModel.apiKeyDraft, "gemini-unsaved")
        viewModel.setProvider("OPENAI")
        XCTAssertEqual(viewModel.apiKeyDraft, "openai-unsaved")
    }

    @MainActor
    func testBindLoadsAlibabaApiKeyFromCredentialStore() throws {
        let fixture = try makeFixture()
        var settings = try fixture.repository.loadSettings()
        settings.apiProvider = "ALIBABA_CODING_PLAN"
        try fixture.repository.saveSettings(settings)
        try fixture.credentials.setCredential("alibaba-key", for: .alibabaCodingPlan)

        let viewModel = SettingsViewModel()
        viewModel.bind(repository: fixture.repository, credentialStore: fixture.credentials)

        XCTAssertEqual(viewModel.apiKeyDraft, "alibaba-key")
    }

    @MainActor
    func testSetProviderSetsAppleIntelligenceDisplayModel() throws {
        let fixture = try makeFixture()
        var settings = try fixture.repository.loadSettings()
        settings.apiProvider = "GEMINI"
        settings.defaultModel = "gemini-2.5-flash"
        try fixture.repository.saveSettings(settings)

        let viewModel = SettingsViewModel()
        viewModel.bind(repository: fixture.repository, credentialStore: fixture.credentials)
        viewModel.setProvider("APPLE_INTELLIGENCE")

        XCTAssertEqual(viewModel.settings.defaultModel, AppleIntelligenceModelCatalog.displayModel)
        XCTAssertEqual(
            viewModel.settings.modelForProvider("APPLE_INTELLIGENCE"),
            AppleIntelligenceModelCatalog.displayModel
        )
    }

    @MainActor
    func testSetProviderReloadsAlibabaApiKeyDraftForSelectedProvider() async throws {
        let fixture = try makeFixture()
        var settings = try fixture.repository.loadSettings()
        settings.apiProvider = "OPENAI"
        try fixture.repository.saveSettings(settings)
        try fixture.credentials.setCredential("openai-key", for: .openAI)
        try fixture.credentials.setCredential("alibaba-key", for: .alibabaCodingPlan)

        let viewModel = SettingsViewModel()
        viewModel.bind(repository: fixture.repository, credentialStore: fixture.credentials)
        viewModel.setProvider("ALIBABA_CODING_PLAN")
        await Task.yield()

        XCTAssertEqual(viewModel.apiKeyDraft, "alibaba-key")
        XCTAssertEqual(viewModel.settings.defaultModel, AlibabaCodingPlanModelCatalog.defaultModel)
    }

    @MainActor
    func testSetProviderUsesOpenCodeGoCatalogInsteadOfOpenCodeZenModel() throws {
        let fixture = try makeFixture()
        var settings = try fixture.repository.loadSettings()
        settings.apiProvider = "OPENROUTER"
        settings.defaultModel = "openai/gpt-4o-mini"
        try fixture.repository.saveSettings(settings)

        let viewModel = SettingsViewModel()
        viewModel.bind(repository: fixture.repository, credentialStore: fixture.credentials)
        viewModel.setProvider("OPENCODE_GO")

        XCTAssertEqual(viewModel.settings.apiProvider, "OPENCODE_GO")
        XCTAssertEqual(viewModel.settings.defaultModel, OpenCodeGoModelCatalog.defaultModel)
    }

    @MainActor
    func testSetProviderUsesZAICodingPlanModel() throws {
        let fixture = try makeFixture()
        var settings = try fixture.repository.loadSettings()
        settings.apiProvider = "OPENAI"
        settings.defaultModel = "gpt-4.1-mini"
        try fixture.repository.saveSettings(settings)

        let viewModel = SettingsViewModel()
        viewModel.bind(repository: fixture.repository, credentialStore: fixture.credentials)
        viewModel.setProvider("ZAI")

        XCTAssertEqual(viewModel.settings.defaultModel, ZAICodingPlanModelCatalog.defaultModel)
    }

    @MainActor
    func testBindLoadsAlibabaMCPAuthorizationTokenFromCredentialStore() throws {
        let fixture = try makeFixture()
        try fixture.credentials.saveSecret("mcp-token", key: AppConstants.alibabaMCPAuthorizationTokenKey)

        let viewModel = SettingsViewModel()
        viewModel.bind(repository: fixture.repository, credentialStore: fixture.credentials)

        XCTAssertEqual(viewModel.alibabaMCPAuthorizationTokenInput, "mcp-token")
    }

    @MainActor
    func testSaveSettingsPersistsAlibabaMCPAuthorizationTokenToCredentialStore() throws {
        let fixture = try makeFixture()
        let viewModel = SettingsViewModel()
        viewModel.bind(repository: fixture.repository, credentialStore: fixture.credentials)
        viewModel.alibabaMCPAuthorizationTokenInput = "persist-me"

        viewModel.saveSettings()

        XCTAssertEqual(
            try fixture.credentials.readSecret(key: AppConstants.alibabaMCPAuthorizationTokenKey),
            "persist-me"
        )
    }

    @MainActor
    func testSetAlibabaMCPServerURLPreservesAuthorizationTokenDraftWhileEditing() throws {
        let fixture = try makeFixture()
        try fixture.credentials.saveSecret("mcp-token", key: AppConstants.alibabaMCPAuthorizationTokenKey)

        let viewModel = SettingsViewModel()
        viewModel.bind(repository: fixture.repository, credentialStore: fixture.credentials)
        XCTAssertEqual(viewModel.alibabaMCPAuthorizationTokenInput, "mcp-token")

        viewModel.setAlibabaMCPServerURL("https://mcp.firecrawl.dev/example/v2/mcp")

        XCTAssertEqual(viewModel.alibabaMCPAuthorizationTokenInput, "mcp-token")
    }

    @MainActor
    func testFlushPendingSettingsSavePersistsSettingsImmediately() throws {
        let fixture = try makeFixture()
        let viewModel = SettingsViewModel()
        viewModel.bind(repository: fixture.repository, credentialStore: fixture.credentials)
        viewModel.settings.themeMode = "DARK"

        viewModel.flushPendingSettingsSave()

        XCTAssertEqual(try fixture.repository.loadSettings().themeMode, "DARK")
    }

    @MainActor
    func testAutoSavePersistsSettingsAfterDebounce() async throws {
        let fixture = try makeFixture()
        let viewModel = SettingsViewModel()
        viewModel.bind(repository: fixture.repository, credentialStore: fixture.credentials)
        viewModel.settings.mathRenderingEnabled.toggle()

        try await Task.sleep(nanoseconds: 900_000_000)

        XCTAssertEqual(
            try fixture.repository.loadSettings().mathRenderingEnabled,
            viewModel.settings.mathRenderingEnabled
        )
    }

    @MainActor
    func testAutoSavePersistsApiKeyDraftAfterDebounce() async throws {
        let fixture = try makeFixture()
        var settings = try fixture.repository.loadSettings()
        settings.apiProvider = "OPENROUTER"
        try fixture.repository.saveSettings(settings)

        let viewModel = SettingsViewModel()
        viewModel.bind(repository: fixture.repository, credentialStore: fixture.credentials)
        viewModel.apiKeyDraft = "auto-saved-key"

        try await Task.sleep(nanoseconds: 900_000_000)

        XCTAssertEqual(try fixture.credentials.credential(for: .openRouter), "auto-saved-key")
    }

    @MainActor
    func testSaveSettingsRejectsInvalidAlibabaMCPURLWhenEnabled() throws {
        let fixture = try makeFixture()
        let viewModel = SettingsViewModel()
        viewModel.bind(repository: fixture.repository, credentialStore: fixture.credentials)
        viewModel.settings.alibabaMCPEnabled = true
        viewModel.settings.themeMode = "DARK"
        viewModel.setAlibabaMCPServerURL("http://example.com/mcp")

        viewModel.saveSettings()

        XCTAssertEqual(viewModel.errorMessage, L10n.text("Remote MCP URL に有効な https:// URL を入力してください。"))
        XCTAssertFalse(try fixture.repository.loadSettings().alibabaMCPEnabled)
        XCTAssertEqual(try fixture.repository.loadSettings().themeMode, "DARK")
    }

    private func makeFixture() throws -> (repository: ChatRepository, credentials: SettingsViewModelCredentialStore) {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)

        let settings = SettingsRepository(dbQueue: dbQueue)
        let conversations = ConversationRepository(dbQueue: dbQueue)
        let credentials = SettingsViewModelCredentialStore()
        let providers = ProviderGateway(settingsRepository: settings, credentialStore: credentials)
        let modelService = OpenRouterModelService(credentialStore: credentials)
        let codexAuth = CodexAuthRepository(credentialStore: credentials)
        let repository = ChatRepositoryTestSupport.makeRepository(
            dbQueue: dbQueue,
            settings: settings,
            conversations: conversations,
            credentials: credentials
        )

        return (repository, credentials)
    }

    private static let modelsDevGeminiFixture = #"""
    {"providers":{
      "other":{"name":"Other","npm":"@ai-sdk/openai-compatible","models":{
        "other-model":{"name":"Other Model","modalities":{"output":["text"]}}
      }},
      "google":{"name":"Google Generative AI","npm":"@ai-sdk/google","models":{
        "gemini-model-from-models-dev":{"name":"Gemini from models.dev","modalities":{"output":["text"]}}
      }}
    }}
    """#
}
