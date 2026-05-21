import XCTest
import GRDB
@testable import YamabikoChat

private final class BranchTestCredentialStore: SecureCredentialStore {
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

final class ChatRepositoryBranchTests: XCTestCase {
    func testBranchConversationUsesSnippetTitleForNewChat() throws {
        let fixture = try makeFixture()
        let conversationId = try fixture.repository.createConversation(title: "New Chat")
        let messageText = "  1234567890123456789012345678901234567890  "
        let messageId = try fixture.conversations.insertMessage(
            ChatMessage(
                conversationId: conversationId,
                role: "user",
                text: messageText,
                createdAtMs: 1
            )
        )

        let newConversationId = try fixture.repository.branchConversation(
            from: conversationId,
            messageId: messageId
        )
        let branched = try fixture.repository.conversation(id: newConversationId)

        XCTAssertEqual(
            branched?.title,
            L10n.format("ブランチ: %@", "12345678901234567890123456789012...")
        )
    }

    func testBranchConversationUsesBaseTitleForNamedConversation() throws {
        let fixture = try makeFixture()
        let conversationId = try fixture.repository.createConversation(title: "計画A")
        let messageId = try fixture.conversations.insertMessage(
            ChatMessage(
                conversationId: conversationId,
                role: "user",
                text: "hello",
                createdAtMs: 1
            )
        )

        let newConversationId = try fixture.repository.branchConversation(
            from: conversationId,
            messageId: messageId
        )
        let branched = try fixture.repository.conversation(id: newConversationId)

        XCTAssertEqual(branched?.title, L10n.format("ブランチ: %@", "計画A"))
    }

    func testBranchConversationCopiesMessagesUpToTargetOnly() throws {
        let fixture = try makeFixture()
        let conversationId = try fixture.repository.createConversation(title: "New Chat")
        _ = try fixture.conversations.insertMessage(
            ChatMessage(
                conversationId: conversationId,
                role: "user",
                text: "m1",
                createdAtMs: 1
            )
        )
        let targetId = try fixture.conversations.insertMessage(
            ChatMessage(
                conversationId: conversationId,
                role: "model",
                text: "m2",
                createdAtMs: 2
            )
        )
        _ = try fixture.conversations.insertMessage(
            ChatMessage(
                conversationId: conversationId,
                role: "user",
                text: "m3",
                createdAtMs: 3
            )
        )

        let newConversationId = try fixture.repository.branchConversation(
            from: conversationId,
            messageId: targetId
        )
        let branchedMessages = try fixture.conversations.fetchMessages(conversationId: newConversationId)

        XCTAssertEqual(branchedMessages.map(\.text), ["m1", "m2"])
    }

    func testBranchConversationCopiesSelectedVariantText() throws {
        let fixture = try makeFixture()
        let conversationId = try fixture.repository.createConversation(title: "New Chat")
        _ = try fixture.conversations.insertMessage(
            ChatMessage(
                conversationId: conversationId,
                role: "user",
                text: "question",
                createdAtMs: 1
            )
        )
        let assistantId = try fixture.conversations.insertMessage(
            ChatMessage(
                conversationId: conversationId,
                role: "model",
                text: "base answer",
                createdAtMs: 2
            )
        )
        _ = try fixture.conversations.insertMessageVariant(
            baseMessageId: assistantId,
            text: "branchable variant"
        )

        let newConversationId = try fixture.repository.branchConversation(
            from: conversationId,
            messageId: assistantId
        )
        let branchedMessages = try fixture.conversations.fetchMessages(conversationId: newConversationId)

        XCTAssertEqual(branchedMessages.count, 2)
        XCTAssertEqual(branchedMessages.last?.role, "model")
        XCTAssertEqual(branchedMessages.last?.text, "branchable variant")
    }

    private func makeFixture() throws -> (
        repository: ChatRepository,
        conversations: ConversationRepository
    ) {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)

        let settings = SettingsRepository(dbQueue: dbQueue)
        let conversations = ConversationRepository(dbQueue: dbQueue)
        let credentials = BranchTestCredentialStore()
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
