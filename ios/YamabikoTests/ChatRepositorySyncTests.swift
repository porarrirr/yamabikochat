import XCTest
import GRDB
@testable import YamabikoChat

private final class TestCredentialStore: SecureCredentialStore {
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

final class ChatRepositorySyncTests: XCTestCase {
    func testUpdateConversationModelAndProviderUpdatesConversation() throws {
        let fixture = try makeFixture()
        let conversationID = try fixture.repository.ensureInitialConversation()

        try fixture.repository.updateConversationModelAndProvider(
            conversationId: conversationID,
            model: "openai/gpt-4o-mini",
            provider: "OPENROUTER"
        )

        let updated = try fixture.repository.conversation(id: conversationID)
        XCTAssertEqual(updated?.model, "openai/gpt-4o-mini")
        XCTAssertEqual(updated?.apiProvider, "OPENROUTER")
    }

    func testSyncNewChatWithSettingsIfEmptyUpdatesConversationProviderAndModel() throws {
        let fixture = try makeFixture()
        let conversationID = try fixture.repository.ensureInitialConversation()
        let previous = try fixture.repository.loadSettings()

        var next = previous
        next.apiProvider = "OPENROUTER"
        next.defaultModel = "openai/gpt-4o-mini"
        next.providerDefaultModelsJSON = #"{"GEMINI":"gemini-2.5-flash","OPENROUTER":"openai/gpt-4o-mini"}"#
        next.systemPrompt = "updated prompt"

        let synced = try fixture.repository.syncNewChatWithSettingsIfEmpty(
            conversationId: conversationID,
            settings: next,
            previousSettings: previous
        )

        XCTAssertEqual(synced?.apiProvider, "OPENROUTER")
        XCTAssertEqual(synced?.model, "openai/gpt-4o-mini")
        XCTAssertEqual(synced?.systemPrompt, "updated prompt")
    }

    func testSyncNewChatWithSettingsIfEmptySkipsConversationWithMessages() throws {
        let fixture = try makeFixture()
        let conversationID = try fixture.repository.ensureInitialConversation()
        let previous = try fixture.repository.loadSettings()
        let originalConversation = try fixture.repository.conversation(id: conversationID)

        _ = try fixture.conversations.insertMessage(
            ChatMessage(
                conversationId: conversationID,
                role: "user",
                text: "hello"
            )
        )

        var next = previous
        next.apiProvider = "OPENROUTER"
        next.defaultModel = "openai/gpt-4o-mini"
        next.providerDefaultModelsJSON = #"{"GEMINI":"gemini-2.5-flash","OPENROUTER":"openai/gpt-4o-mini"}"#

        let synced = try fixture.repository.syncNewChatWithSettingsIfEmpty(
            conversationId: conversationID,
            settings: next,
            previousSettings: previous
        )

        XCTAssertEqual(synced?.apiProvider, originalConversation?.apiProvider)
        XCTAssertEqual(synced?.model, originalConversation?.model)
    }

    private func makeFixture() throws -> (repository: ChatRepository, conversations: ConversationRepository) {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)

        let settings = SettingsRepository(dbQueue: dbQueue)
        let conversations = ConversationRepository(dbQueue: dbQueue)
        let credentials = TestCredentialStore()
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
        return (repository, conversations)
    }
}
