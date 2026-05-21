import XCTest
import GRDB
@testable import YamabikoChat

private final class ConversationListTestCredentialStore: SecureCredentialStore {
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
final class ConversationListViewModelTests: XCTestCase {
    func testResetProjectFilterClearsSelectionForNonProjectConversation() throws {
        let repository = try makeFixture()
        let projectId = try repository.createProject(title: "Project A", instructions: nil)
        _ = try repository.createConversation(projectId: projectId)
        let nonProjectConversationId = try repository.createConversation()

        let viewModel = ConversationListViewModel()
        viewModel.bind(repository: repository)
        viewModel.selectProject(projectId)

        viewModel.resetProjectFilterForNonProjectConversation(conversationId: nonProjectConversationId)

        XCTAssertNil(viewModel.selectedProjectId)
    }

    func testResetProjectFilterKeepsSelectionForProjectConversation() throws {
        let repository = try makeFixture()
        let projectId = try repository.createProject(title: "Project A", instructions: nil)
        let projectConversationId = try repository.createConversation(projectId: projectId)

        let viewModel = ConversationListViewModel()
        viewModel.bind(repository: repository)
        viewModel.selectProject(projectId)

        viewModel.resetProjectFilterForNonProjectConversation(conversationId: projectConversationId)

        XCTAssertEqual(viewModel.selectedProjectId, projectId)
    }

    func testResetProjectFilterNoopWhenProjectFilterIsNotSelected() throws {
        let repository = try makeFixture()
        let nonProjectConversationId = try repository.createConversation()
        let viewModel = ConversationListViewModel()
        viewModel.bind(repository: repository)

        viewModel.resetProjectFilterForNonProjectConversation(conversationId: nonProjectConversationId)

        XCTAssertNil(viewModel.selectedProjectId)
    }

    func testResetProjectFilterKeepsSelectionWhenConversationIsUnknown() throws {
        let repository = try makeFixture()
        let projectId = try repository.createProject(title: "Project A", instructions: nil)
        _ = try repository.createConversation(projectId: projectId)
        let viewModel = ConversationListViewModel()
        viewModel.bind(repository: repository)
        viewModel.selectProject(projectId)

        viewModel.resetProjectFilterForNonProjectConversation(conversationId: 999_999)

        XCTAssertEqual(viewModel.selectedProjectId, projectId)
    }

    private func makeFixture() throws -> ChatRepository {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)

        let settings = SettingsRepository(dbQueue: dbQueue)
        let conversations = ConversationRepository(dbQueue: dbQueue)
        let credentials = ConversationListTestCredentialStore()
        let providers = ProviderGateway(settingsRepository: settings, credentialStore: credentials)
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

        return repository
    }
}
