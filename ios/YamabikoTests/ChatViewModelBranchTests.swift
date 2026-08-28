import XCTest
import GRDB
@testable import YamabikoChat

private final class ViewModelBranchCredentialStore: SecureCredentialStore {
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

@MainActor
final class ChatViewModelBranchTests: XCTestCase {
    func testBranchConversationReturnsNewConversationId() throws {
        let fixture = try makeFixture()
        let conversationId = try fixture.repository.createConversation(title: "New Chat")
        let messageId = try fixture.conversations.insertMessage(
            ChatMessage(
                conversationId: conversationId,
                role: "user",
                text: "branch source",
                createdAtMs: 1
            )
        )

        let viewModel = ChatViewModel(conversationID: conversationId)
        viewModel.bind(
            repository: fixture.repository,
            attachmentRepository: AttachmentRepository()
        )

        let newConversationId = viewModel.branchConversation(from: messageId)

        XCTAssertNotNil(newConversationId)
        XCTAssertNotNil(try fixture.repository.conversation(id: newConversationId ?? 0))
        XCTAssertNil(viewModel.errorMessage)
    }

    func testBranchConversationSetsErrorWhenMessageIsMissing() throws {
        let fixture = try makeFixture()
        let conversationId = try fixture.repository.createConversation(title: "New Chat")
        let viewModel = ChatViewModel(conversationID: conversationId)
        viewModel.bind(
            repository: fixture.repository,
            attachmentRepository: AttachmentRepository()
        )

        let newConversationId = viewModel.branchConversation(from: 999_999)

        XCTAssertNil(newConversationId)
        XCTAssertNotNil(viewModel.errorMessage)
        let localizedPrefix = L10n.text("ブランチの作成に失敗しました: %@").components(separatedBy: "%@").first ?? ""
        XCTAssertTrue(viewModel.errorMessage?.contains(localizedPrefix) == true)
    }

    func testBindExposesSecretConversationState() throws {
        let fixture = try makeFixture()
        let conversationId = try fixture.repository.createSecretConversation()
        let viewModel = ChatViewModel(conversationID: conversationId)

        viewModel.bind(
            repository: fixture.repository,
            attachmentRepository: AttachmentRepository()
        )

        XCTAssertTrue(viewModel.isSecretConversation)
    }

    func testDisablingConversationSystemPromptClearsPersistedPromptAndSelectionState() throws {
        let fixture = try makeFixture()
        let conversationId = try fixture.repository.createConversation(title: "Prompt Test")
        try fixture.repository.updateConversationSystemPrompt(
            conversationId: conversationId,
            systemPrompt: "Conversation instructions"
        )
        let viewModel = ChatViewModel(conversationID: conversationId)
        viewModel.bind(
            repository: fixture.repository,
            attachmentRepository: AttachmentRepository()
        )

        XCTAssertTrue(viewModel.isCustomSystemPromptActive)
        XCTAssertFalse(viewModel.isSystemPromptDisabledForConversation)

        viewModel.disableSystemPromptForConversation()

        XCTAssertNil(try fixture.repository.conversation(id: conversationId)?.systemPrompt)
        XCTAssertTrue(viewModel.isSystemPromptDisabledForConversation)
        XCTAssertFalse(viewModel.isCustomSystemPromptActive)
        XCTAssertEqual(viewModel.systemPromptContextLabel, L10n.text("Prompt: なし"))
        XCTAssertNil(viewModel.errorMessage)
    }

    func testCodexReasoningEffortConfigurationUsesModelContractAndPersistsSelection() throws {
        let fixture = try makeFixture()
        var settings = try fixture.repository.loadSettings()
        settings.apiProvider = "CODEX_AUTH"
        settings.defaultModel = "gpt-5.6-terra"
        settings.codexReasoningEnabled = true
        settings.codexReasoningEffort = "medium"
        try fixture.repository.saveSettings(settings)

        let configuration = fixture.repository.reasoningEffortConfiguration(
            settings: settings,
            provider: "CODEX_AUTH",
            model: "gpt-5.6-terra"
        )

        XCTAssertEqual(configuration?.modelLabel, "GPT-5.6-Terra")
        XCTAssertEqual(configuration?.options, ["low", "medium", "high", "xhigh", "max", "ultra"])
        XCTAssertEqual(configuration?.selectedValue, "medium")

        try fixture.repository.setReasoningEffort(
            "xhigh",
            provider: "CODEX_AUTH",
            model: "gpt-5.6-terra"
        )
        XCTAssertEqual(try fixture.repository.loadSettings().codexReasoningEffort, "xhigh")
    }

    func testDisabledReasoningDoesNotExposeAnInactiveEffortAsCurrent() throws {
        let fixture = try makeFixture()
        var settings = try fixture.repository.loadSettings()
        settings.codexReasoningEnabled = false
        settings.codexReasoningEffort = "medium"

        XCTAssertNil(fixture.repository.reasoningEffortConfiguration(
            settings: settings,
            provider: "CODEX_AUTH",
            model: "gpt-5.6-sol"
        ))
    }

    func testSuperGrokReasoningEffortUsesSupportedContractAndPersistsSelection() throws {
        let fixture = try makeFixture()
        var settings = try fixture.repository.loadSettings()
        settings.superGrokReasoningEnabled = true
        settings.superGrokReasoningEffort = "medium"
        try fixture.repository.saveSettings(settings)

        let configuration = fixture.repository.reasoningEffortConfiguration(
            settings: settings,
            provider: "SUPERGROK",
            model: "grok-4.5"
        )

        XCTAssertEqual(configuration?.modelLabel, "Grok 4.5")
        XCTAssertEqual(configuration?.options, ["low", "medium", "high"])
        XCTAssertEqual(configuration?.selectedValue, "medium")

        try fixture.repository.setReasoningEffort(
            "high",
            provider: "SUPERGROK",
            model: "grok-4.5"
        )
        XCTAssertEqual(try fixture.repository.loadSettings().superGrokReasoningEffort, "high")
    }

    func testGeminiReasoningEffortUsesEffectiveThinkingLevelAndPersistsSelection() throws {
        let fixture = try makeFixture()
        var settings = try fixture.repository.loadSettings()
        settings.geminiThinkingEnabled = true
        settings.geminiThinkingLevel = "medium"
        try fixture.repository.saveSettings(settings)

        let configuration = fixture.repository.reasoningEffortConfiguration(
            settings: settings,
            provider: "GEMINI",
            model: "gemini-3-flash-preview"
        )

        XCTAssertEqual(configuration?.options, ["minimal", "low", "medium", "high"])
        XCTAssertEqual(configuration?.selectedValue, "medium")

        try fixture.repository.setReasoningEffort(
            "high",
            provider: "GEMINI",
            model: "gemini-3-flash-preview"
        )
        let updated = try fixture.repository.loadSettings()
        XCTAssertTrue(updated.geminiThinkingEnabled)
        XCTAssertEqual(updated.geminiThinkingLevel, "high")
    }

    func testOpenRouterReasoningEffortPreservesLocalizedCatalogLabels() throws {
        let fixture = try makeFixture()
        let model = SimpleModel(
            id: "example/localized-reasoning",
            name: "Localized Reasoning",
            provider: "example",
            topProvider: nil,
            contextLength: 32_768,
            promptPricePerMillion: 1,
            completionPricePerMillion: 2,
            isFree: false,
            availableProviders: [],
            availableQuantizations: [],
            reasoning: OpenRouterReasoningCapabilities(
                supportedEfforts: ["低", "中程度", "高"],
                exposesEffortSelection: true,
                defaultEffort: "中程度",
                defaultEnabled: true
            )
        )
        fixture.modelService.replaceCachedModels([model])

        var settings = try fixture.repository.loadSettings()
        settings.openRouterThinkingEnabled = true
        settings.openRouterReasoningMode = "effort"
        settings.openRouterReasoningEffort = "中程度"
        try fixture.repository.saveSettings(settings)

        let configuration = fixture.repository.reasoningEffortConfiguration(
            settings: settings,
            provider: "OPENROUTER",
            model: model.id
        )

        XCTAssertEqual(configuration?.options, ["低", "中程度", "高"])
        XCTAssertEqual(configuration?.selectedValue, "中程度")

        try fixture.repository.setReasoningEffort(
            "高",
            provider: "OPENROUTER",
            model: model.id
        )
        XCTAssertEqual(try fixture.repository.loadSettings().openRouterReasoningEffort, "高")
    }

    func testModelsDevReasoningEffortUsesCatalogAndCredentialPreference() throws {
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("chat-effort-models-dev-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let provider = CatalogProvider(
            id: "example",
            name: "Example",
            npm: "@ai-sdk/openai-compatible",
            api: "https://example.com/v1",
            env: ["EXAMPLE_API_KEY"],
            models: [
                CatalogModel(
                    id: "localized-model",
                    name: "Localized Model",
                    reasoning: true,
                    reasoningOptions: [
                        CatalogReasoningOption(type: "effort", values: ["低", "中程度", "高"])
                    ],
                    toolCall: true,
                    inputModalities: ["text"],
                    outputModalities: ["text"],
                    limits: CatalogLimits(context: 32_768, input: nil, output: 8_192),
                    cost: CatalogCost(
                        inputPerMillion: nil,
                        outputPerMillion: nil,
                        reasoningPerMillion: nil,
                        cacheReadPerMillion: nil,
                        cacheWritePerMillion: nil
                    )
                )
            ]
        )
        try JSONEncoder().encode([provider]).write(to: cacheURL, options: .atomic)
        let catalog = ModelsDevCatalogRepository(cacheURL: cacheURL)
        let fixture = try makeFixture(modelsDevCatalogRepository: catalog)
        let key = ModelsDevReasoningPreference.storageKey(
            providerID: provider.id,
            modelID: "localized-model"
        )
        try fixture.credentials.saveSecret("中程度", key: key)

        let configuration = fixture.repository.reasoningEffortConfiguration(
            settings: try fixture.repository.loadSettings(),
            provider: "MODELS_DEV:example",
            model: "localized-model"
        )

        XCTAssertEqual(configuration?.modelLabel, "Localized Model")
        XCTAssertEqual(configuration?.options, ["低", "中程度", "高"])
        XCTAssertEqual(configuration?.selectedValue, "中程度")

        try fixture.repository.setReasoningEffort(
            "高",
            provider: "MODELS_DEV:example",
            model: "localized-model"
        )
        XCTAssertEqual(try fixture.credentials.readSecret(key: key), "高")
    }

    private func makeFixture(
        modelsDevCatalogRepository: ModelsDevCatalogRepository? = nil
    ) throws -> (
        repository: ChatRepository,
        conversations: ConversationRepository,
        credentials: ViewModelBranchCredentialStore,
        modelService: OpenRouterModelService
    ) {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)

        let settings = SettingsRepository(dbQueue: dbQueue)
        let conversations = ConversationRepository(dbQueue: dbQueue)
        let credentials = ViewModelBranchCredentialStore()
        let modelService = OpenRouterModelService(credentialStore: credentials)

        let repository = ChatRepositoryTestSupport.makeRepository(
            dbQueue: dbQueue,
            settings: settings,
            conversations: conversations,
            credentials: credentials,
            modelService: modelService,
            modelsDevCatalogRepository: modelsDevCatalogRepository
        )
        return (repository, conversations, credentials, modelService)
    }
}
