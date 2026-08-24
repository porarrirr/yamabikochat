import XCTest
import GRDB
@testable import YamabikoChat

private final class ProjectFeatureCredentialStore: SecureCredentialStore {
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

final class ProjectFeatureTests: XCTestCase {
    func testCreateConversationInProjectUsesProjectInstructions() throws {
        let fixture = try makeFixture()
        let projectId = try fixture.repository.createProject(title: "iOS移植", instructions: "プロジェクト固有の指示")

        let conversationId = try fixture.repository.createConversation(projectId: projectId)
        let conversation = try fixture.repository.conversation(id: conversationId)

        XCTAssertEqual(conversation?.projectId, projectId)
        XCTAssertEqual(conversation?.systemPrompt, "プロジェクト固有の指示")
    }

    func testAssignConversationToProjectCopiesInstructions() throws {
        let fixture = try makeFixture()
        let conversationId = try fixture.repository.createConversation()
        let projectId = try fixture.repository.createProject(title: "設計", instructions: "設計レビュー観点で回答")

        try fixture.repository.assignConversationToProject(conversationId: conversationId, projectId: projectId)
        let updated = try fixture.repository.conversation(id: conversationId)

        XCTAssertEqual(updated?.projectId, projectId)
        XCTAssertEqual(updated?.systemPrompt, "設計レビュー観点で回答")
    }

    func testSyncNewChatSkipsProjectConversation() throws {
        let fixture = try makeFixture()
        let projectId = try fixture.repository.createProject(title: "A", instructions: "project prompt")
        let conversationId = try fixture.repository.createConversation(projectId: projectId)

        let previous = try fixture.repository.loadSettings()
        var next = previous
        next.apiProvider = "OPENROUTER"
        next.defaultModel = "openai/gpt-4o-mini"
        next.providerDefaultModelsJSON = #"{"GEMINI":"gemini-2.5-flash","OPENROUTER":"openai/gpt-4o-mini"}"#
        next.systemPrompt = "global prompt"

        let synced = try fixture.repository.syncNewChatWithSettingsIfEmpty(
            conversationId: conversationId,
            settings: next,
            previousSettings: previous
        )

        XCTAssertEqual(synced?.projectId, projectId)
        XCTAssertEqual(synced?.systemPrompt, "project prompt")
    }

    func testDeleteProjectKeepsConversationsAndClearsProjectLink() throws {
        let fixture = try makeFixture()
        let projectId = try fixture.repository.createProject(title: "削除対象", instructions: "project prompt")
        let conversationId = try fixture.repository.createConversation(projectId: projectId)

        try fixture.repository.deleteProject(id: projectId, mode: .projectOnly)

        let project = try fixture.conversations.fetchProject(id: projectId)
        let conversation = try fixture.repository.conversation(id: conversationId)
        XCTAssertNil(project)
        XCTAssertNotNil(conversation)
        XCTAssertNil(conversation?.projectId)
    }

    func testDeleteProjectWithConversationsRemovesProjectConversationsOnly() throws {
        let fixture = try makeFixture()
        let projectId = try fixture.repository.createProject(title: "削除対象", instructions: nil)
        let projectConversationId = try fixture.repository.createConversation(projectId: projectId)
        let otherConversationId = try fixture.repository.createConversation()

        try fixture.repository.deleteProject(id: projectId, mode: .withConversations)

        let project = try fixture.conversations.fetchProject(id: projectId)
        let removedConversation = try fixture.repository.conversation(id: projectConversationId)
        let otherConversation = try fixture.repository.conversation(id: otherConversationId)

        XCTAssertNil(project)
        XCTAssertNil(removedConversation)
        XCTAssertNotNil(otherConversation)
    }

    func testPurgeSecretConversationsRemovesSecretDataOnly() throws {
        let fixture = try makeFixture()
        let secretConversationId = try fixture.repository.createSecretConversation()
        let regularConversationId = try fixture.repository.createConversation(title: "Persistent Chat")

        _ = try fixture.conversations.insertMessage(
            ChatMessage(conversationId: secretConversationId, role: "user", text: "secret", createdAtMs: 1)
        )
        _ = try fixture.conversations.insertMessage(
            ChatMessage(conversationId: regularConversationId, role: "user", text: "regular", createdAtMs: 2)
        )
        try insertTokenUsage(dbQueue: fixture.dbQueue, conversationId: secretConversationId)
        try insertTokenUsage(dbQueue: fixture.dbQueue, conversationId: regularConversationId)

        try fixture.repository.purgeSecretConversations()

        XCTAssertNil(try fixture.repository.conversation(id: secretConversationId))
        XCTAssertNotNil(try fixture.repository.conversation(id: regularConversationId))
        XCTAssertEqual(try tokenUsageCount(dbQueue: fixture.dbQueue, conversationId: secretConversationId), 0)
        XCTAssertEqual(try tokenUsageCount(dbQueue: fixture.dbQueue, conversationId: regularConversationId), 1)
    }

    func testDeleteSecretConversationIfNeededDeletesOnlySecretConversation() throws {
        let fixture = try makeFixture()
        let secretConversationId = try fixture.repository.createSecretConversation()
        let regularConversationId = try fixture.repository.createConversation(title: "Persistent Chat")

        let deletedSecret = try fixture.repository.deleteSecretConversationIfNeeded(id: secretConversationId)
        let deletedRegular = try fixture.repository.deleteSecretConversationIfNeeded(id: regularConversationId)

        XCTAssertTrue(deletedSecret)
        XCTAssertFalse(deletedRegular)
        XCTAssertNil(try fixture.repository.conversation(id: secretConversationId))
        XCTAssertNotNil(try fixture.repository.conversation(id: regularConversationId))
    }

    func testUpdateProjectInstructionsUpdatesProjectAndConversations() throws {
        let fixture = try makeFixture()
        let projectId = try fixture.repository.createProject(title: "テストプロジェクト", instructions: "初期の指示")
        let conversationId = try fixture.repository.createConversation(projectId: projectId)

        let initialConv = try fixture.repository.conversation(id: conversationId)
        XCTAssertEqual(initialConv?.systemPrompt, "初期の指示")

        try fixture.repository.updateProjectInstructions(id: projectId, instructions: "更新後の指示")

        let project = try fixture.repository.fetchProject(id: projectId)
        XCTAssertEqual(project?.instructions, "更新後の指示")

        let updatedConv = try fixture.repository.conversation(id: conversationId)
        XCTAssertEqual(updatedConv?.systemPrompt, "更新後の指示")
    }

    func testUpdateProjectTitleAndProperties() throws {
        let fixture = try makeFixture()
        let projectId = try fixture.repository.createProject(title: "旧タイトル", instructions: "指示")

        try fixture.repository.updateProject(
            id: projectId,
            title: "新タイトル",
            instructions: "新しい指示",
            iconName: "folder.fill",
            colorHex: "#FF3B30"
        )

        let project = try fixture.repository.fetchProject(id: projectId)
        XCTAssertEqual(project?.title, "新タイトル")
        XCTAssertEqual(project?.instructions, "新しい指示")
        XCTAssertEqual(project?.iconName, "folder.fill")
        XCTAssertEqual(project?.colorHex, "#FF3B30")
    }

    func testUpdateProjectTitleDoesNotResetCustomConversationPrompt() throws {
        let fixture = try makeFixture()
        let projectId = try fixture.repository.createProject(title: "旧タイトル", instructions: "プロジェクト指示")
        let conversationId = try fixture.repository.createConversation(projectId: projectId)

        try fixture.repository.updateConversationSystemPrompt(
            conversationId: conversationId,
            systemPrompt: "会話固有の指示"
        )

        try fixture.repository.updateProject(
            id: projectId,
            title: "新タイトル",
            instructions: "プロジェクト指示",
            iconName: "folder.fill",
            colorHex: "#FF3B30"
        )

        let project = try fixture.repository.fetchProject(id: projectId)
        let conversation = try fixture.repository.conversation(id: conversationId)
        XCTAssertEqual(project?.title, "新タイトル")
        XCTAssertEqual(project?.colorHex, "#FF3B30")
        XCTAssertEqual(conversation?.systemPrompt, "会話固有の指示")
    }

    func testClearingProjectInstructionsFallsBackToDefaultPrompt() throws {
        let fixture = try makeFixture()
        let projectId = try fixture.repository.createProject(title: "テスト", instructions: "プロジェクト指示")
        let conversationId = try fixture.repository.createConversation(projectId: projectId)

        try fixture.repository.updateProjectInstructions(id: projectId, instructions: nil)

        let project = try fixture.repository.fetchProject(id: projectId)
        let conversation = try fixture.repository.conversation(id: conversationId)
        XCTAssertNil(project?.instructions)
        XCTAssertNil(conversation?.systemPrompt)
    }

    func testPendingInitialMessagePersistsUntilUserTurnIsCommitted() throws {
        let fixture = try makeFixture()
        let projectId = try fixture.repository.createProject(title: "テスト", instructions: nil)
        let conversationId = try fixture.repository.createConversationWithPendingInitialMessage(
            "  こんにちは  ",
            projectId: projectId
        )

        XCTAssertEqual(
            try fixture.repository.pendingInitialMessage(conversationId: conversationId),
            "こんにちは"
        )

        _ = try fixture.conversations.insertMessage(
            ChatMessage(conversationId: conversationId, role: "model", text: "準備中")
        )
        XCTAssertEqual(
            try fixture.repository.pendingInitialMessage(conversationId: conversationId),
            "こんにちは"
        )

        _ = try fixture.conversations.insertMessage(
            ChatMessage(conversationId: conversationId, role: "user", text: "こんにちは")
        )
        XCTAssertNil(try fixture.repository.pendingInitialMessage(conversationId: conversationId))
    }

    private func makeFixture() throws -> (
        repository: ChatRepository,
        conversations: ConversationRepository,
        dbQueue: DatabaseQueue
    ) {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)

        let settings = SettingsRepository(dbQueue: dbQueue)
        let conversations = ConversationRepository(dbQueue: dbQueue)
        let credentials = ProjectFeatureCredentialStore()
        let providers = ProviderGateway(settingsRepository: settings, credentialStore: credentials)
        let modelService = OpenRouterModelService(credentialStore: credentials)
        let codexAuth = CodexAuthRepository(credentialStore: credentials)

        let repository = ChatRepositoryTestSupport.makeRepository(
            dbQueue: dbQueue,
            settings: settings,
            conversations: conversations,
            credentials: credentials
        )
        return (repository, conversations, dbQueue)
    }

    private func insertTokenUsage(dbQueue: DatabaseQueue, conversationId: Int64) throws {
        try dbQueue.write { db in
            var record = TokenUsageRecord(
                provider: "GEMINI",
                model: "gemini-2.5-flash",
                conversationId: conversationId,
                inputTokens: 1,
                outputTokens: 1,
                totalTokens: 2
            )
            try record.insert(db)
        }
    }

    private func tokenUsageCount(dbQueue: DatabaseQueue, conversationId: Int64) throws -> Int {
        try dbQueue.read { db in
            try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM token_usage_records WHERE conversationId = ?",
                arguments: [conversationId]
            ) ?? 0
        }
    }
}
