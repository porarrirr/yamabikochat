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

    private func makeFixture() throws -> (
        repository: ChatRepository,
        conversations: ConversationRepository
    ) {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)

        let settings = SettingsRepository(dbQueue: dbQueue)
        let conversations = ConversationRepository(dbQueue: dbQueue)
        let credentials = ViewModelBranchCredentialStore()
        let providers = ProviderGateway(
            settingsRepository: settings,
            credentialStore: credentials,
            httpClient: URLSessionHTTPClient()
        )
        let modelService = OpenRouterModelService(credentialStore: credentials)
        let codexAuth = CodexAuthRepository(credentialStore: credentials)

        let repository = ChatRepository(
            conversations: conversations,
            settings: settings,
            providers: providers,
            credentialStore: credentials,
            modelService: modelService,
            codexAuthRepository: codexAuth
        )
        return (repository, conversations)
    }
}
