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
    func testGeminiQuotaMissingCredentialErrorIsDetected() {
        XCTAssertTrue(
            SettingsViewModel.isGeminiQuotaMissingCredentialError(
                ProviderClientError.missingCredential("GEMINI_AUTH")
            )
        )
        XCTAssertTrue(
            SettingsViewModel.isGeminiQuotaMissingCredentialError(
                ProviderClientError.missingCredential("gemini_auth")
            )
        )
    }

    func testGeminiQuotaMissingCredentialErrorIgnoresOtherErrors() {
        XCTAssertFalse(
            SettingsViewModel.isGeminiQuotaMissingCredentialError(
                ProviderClientError.missingCredential("GEMINI")
            )
        )
        XCTAssertFalse(
            SettingsViewModel.isGeminiQuotaMissingCredentialError(
                ProviderClientError.parseFailure("bad response")
            )
        )
    }

    @MainActor
    func testGeminiQuotaDisplayRowsUseRemainingFractionWhenAmountMissing() {
        let viewModel = SettingsViewModel()
        viewModel.geminiUserQuota = GeminiUserQuota(
            buckets: [
                GeminiQuotaBucket(
                    modelId: "gemini-3-pro-preview",
                    tokenType: "REQUESTS",
                    remainingAmount: nil,
                    remainingFraction: 0.75,
                    resetTime: "2026-02-10T00:00:00Z"
                )
            ]
        )

        XCTAssertEqual(
            viewModel.geminiQuotaDisplayRows,
            [
                GeminiQuotaDisplayRow(
                    modelId: "gemini-3-pro-preview",
                    detail: "25% used",
                    resetTime: "2026-02-10T00:00:00Z"
                )
            ]
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
    func testSetProviderReloadsApiKeyDraftForSelectedProvider() throws {
        let fixture = try makeFixture()
        var settings = try fixture.repository.loadSettings()
        settings.apiProvider = "OPENROUTER"
        try fixture.repository.saveSettings(settings)
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)
        try fixture.credentials.setCredential("openai-key", for: .openAI)

        let viewModel = SettingsViewModel()
        viewModel.bind(repository: fixture.repository, credentialStore: fixture.credentials)
        viewModel.setProvider("OPENAI")

        XCTAssertEqual(viewModel.apiKeyDraft, "openai-key")
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
    func testSetProviderReloadsAlibabaApiKeyDraftForSelectedProvider() throws {
        let fixture = try makeFixture()
        var settings = try fixture.repository.loadSettings()
        settings.apiProvider = "OPENAI"
        try fixture.repository.saveSettings(settings)
        try fixture.credentials.setCredential("openai-key", for: .openAI)
        try fixture.credentials.setCredential("alibaba-key", for: .alibabaCodingPlan)

        let viewModel = SettingsViewModel()
        viewModel.bind(repository: fixture.repository, credentialStore: fixture.credentials)
        viewModel.setProvider("ALIBABA_CODING_PLAN")

        XCTAssertEqual(viewModel.apiKeyDraft, "alibaba-key")
        XCTAssertEqual(viewModel.settings.defaultModel, AlibabaCodingPlanModelCatalog.defaultModel)
    }

    @MainActor
    func testSetProviderReloadsQwenCredentialAndDefaultModel() throws {
        let fixture = try makeFixture()
        var settings = try fixture.repository.loadSettings()
        settings.apiProvider = "OPENAI"
        try fixture.repository.saveSettings(settings)
        try fixture.credentials.setCredential("openai-key", for: .openAI)
        try fixture.credentials.setCredential("qwen-token", for: .qwenCode)

        let viewModel = SettingsViewModel()
        viewModel.bind(repository: fixture.repository, credentialStore: fixture.credentials)
        viewModel.setProvider("QWEN_CODE")

        XCTAssertEqual(viewModel.apiKeyDraft, "qwen-token")
        XCTAssertEqual(viewModel.settings.defaultModel, QwenModelCatalog.defaultModel)
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
    func testSetAlibabaMCPServerURLClearsAuthorizationTokenWhenServerChanges() throws {
        let fixture = try makeFixture()
        try fixture.credentials.saveSecret("mcp-token", key: AppConstants.alibabaMCPAuthorizationTokenKey)

        let viewModel = SettingsViewModel()
        viewModel.bind(repository: fixture.repository, credentialStore: fixture.credentials)
        XCTAssertEqual(viewModel.alibabaMCPAuthorizationTokenInput, "mcp-token")

        viewModel.setAlibabaMCPServerURL("https://mcp.firecrawl.dev/example/v2/mcp")

        XCTAssertEqual(viewModel.alibabaMCPAuthorizationTokenInput, "")
    }

    @MainActor
    func testSaveSettingsRejectsInvalidAlibabaMCPURLWhenEnabled() throws {
        let fixture = try makeFixture()
        let viewModel = SettingsViewModel()
        viewModel.bind(repository: fixture.repository, credentialStore: fixture.credentials)
        viewModel.settings.alibabaMCPEnabled = true
        viewModel.setAlibabaMCPServerURL("http://example.com/mcp")

        viewModel.saveSettings()

        XCTAssertEqual(viewModel.errorMessage, L10n.text("Remote MCP URL に有効な https:// URL を入力してください。"))
        XCTAssertFalse(try fixture.repository.loadSettings().alibabaMCPEnabled)
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
        let geminiAuth = GeminiAuthRepository(credentialStore: credentials)
        let repository = ChatRepository(
            conversations: conversations,
            settings: settings,
            providers: providers,
            credentialStore: credentials,
            modelService: modelService,
            codexAuthRepository: codexAuth,
            geminiAuthRepository: geminiAuth
        )

        return (repository, credentials)
    }
}
