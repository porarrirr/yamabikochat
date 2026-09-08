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

    func testBranchAttachmentsSurviveDeletingEitherBranchAndProjects() throws {
        for mode in 0..<4 {
            let fixture = try makeFixture()
            let original = try fixture.repository.createConversation(title: "original")
            let attachments = AttachmentRepository()
            let file = try attachments.persistGeneratedFile(data: Data("branch attachment".utf8), filename: "branch.txt", collection: ConversationWorkspacePath.generatedFilesCollection(for: String(original)))
            defer { try? FileManager.default.removeItem(at: file) }
            let raw = String(decoding: try JSONEncoder().encode([file.path]), as: UTF8.self)
            let message = try fixture.conversations.insertMessage(ChatMessage(conversationId: original, role: "user", text: "question", attachmentsJSON: raw))
            let branch = try fixture.repository.branchConversation(from: original, messageId: message)
            let survivor: Int64
            switch mode {
            case 0:
                try fixture.repository.deleteConversation(id: original)
                survivor = branch
            case 1:
                try fixture.repository.deleteConversation(id: branch)
                survivor = original
            case 2:
                try fixture.repository.deleteConversations(ids: [original])
                survivor = branch
            default:
                let project = try fixture.conversations.createProject(title: "project", instructions: nil)
                try fixture.conversations.assignConversationToProject(conversationId: original, projectId: project)
                try fixture.repository.deleteProject(id: project, mode: .withConversations)
                survivor = branch
            }
            XCTAssertEqual(try String(contentsOf: file, encoding: .utf8), "branch attachment")
            let history = try fixture.conversations.fetchMessages(conversationId: survivor)
            XCTAssertEqual(history.first?.attachmentsJSON, raw)
            let archive = try ConversationExportService.createArchive(snapshot: fixture.conversations.fetchDebugExport(conversationId: survivor))
            try FileManager.default.removeItem(at: archive)
            try fixture.repository.deleteConversation(id: survivor)
            XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        }
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
            credentialStore: credentials
        )
        let modelService = OpenRouterModelService(credentialStore: credentials)
        let codexAuth = CodexAuthRepository(credentialStore: credentials)

        let repository = ChatRepositoryTestSupport.makeRepository(
            dbQueue: dbQueue,
            settings: settings,
            conversations: conversations,
            credentials: credentials
        )
        return (repository, conversations)
    }
}
