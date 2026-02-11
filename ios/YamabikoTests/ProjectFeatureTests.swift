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

    private func makeFixture() throws -> (repository: ChatRepository, conversations: ConversationRepository) {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)

        let settings = SettingsRepository(dbQueue: dbQueue)
        let conversations = ConversationRepository(dbQueue: dbQueue)
        let credentials = ProjectFeatureCredentialStore()
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
