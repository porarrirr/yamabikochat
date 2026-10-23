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
    @MainActor
    func testTechnicalFailureIsHiddenAndInputGuidanceRemainsVisible() {
        let viewModel = ConversationListViewModel()
        let error = NSError(domain: "DiagnosticOnly", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "Response parse failed: timeout"])
        viewModel.recordFailure(error)
        XCTAssertEqual(viewModel.errorMessage, error.localizedDescription)
        XCTAssertNil(viewModel.visibleErrorMessage)

        viewModel.errorMessage = "APIキーを入力してください"
        XCTAssertEqual(viewModel.visibleErrorMessage, viewModel.errorMessage)
        viewModel.errorMessage = nil
        XCTAssertNil(viewModel.visibleErrorMessage)
    }

    func testColdLaunchSelectsEmptyNewChatInsteadOfExistingHistory() throws {
        let repository = try makeFixture()
        let historyID = try repository.createConversation(title: "Previous conversation")
        let appState = AppState()

        XCTAssertTrue(try appState.initializeConversationSelectionIfNeeded(repository: repository))

        let selectedID = try XCTUnwrap(appState.selectedConversationID)
        XCTAssertNotEqual(selectedID, historyID)
        XCTAssertEqual(try repository.conversation(id: selectedID)?.title, "New Chat")
        XCTAssertNotNil(try repository.conversation(id: historyID))

        let resolution = ConversationListSelectionResolver.resolve(
            visibleConversationIDs: [historyID],
            selectedConversationID: selectedID,
            selectedConversationExists: true,
            keepSidebarAfterSecretDiscard: false
        )
        XCTAssertEqual(resolution, .keepCurrentSelection)
    }

    func testLaunchReusesExistingEmptyNewChat() throws {
        let repository = try makeFixture()
        let emptyID = try repository.ensureInitialConversation()
        _ = try repository.createConversation(title: "Latest conversation")
        let appState = AppState()

        XCTAssertTrue(try appState.initializeConversationSelectionIfNeeded(repository: repository))

        XCTAssertEqual(appState.selectedConversationID, emptyID)
    }

    func testForegroundKeepsSelectionButNewAppStateOpensNewChat() throws {
        let repository = try makeFixture()
        let historyID = try repository.createConversation(title: "Previous conversation")
        let appState = AppState()
        try appState.initializeConversationSelectionIfNeeded(repository: repository)
        appState.selectedConversationID = historyID

        XCTAssertFalse(try appState.initializeConversationSelectionIfNeeded(repository: repository))
        XCTAssertEqual(appState.selectedConversationID, historyID)

        appState.selectedConversationID = nil
        XCTAssertFalse(try appState.initializeConversationSelectionIfNeeded(repository: repository))
        XCTAssertNil(appState.selectedConversationID)

        let relaunchedState = AppState()
        XCTAssertTrue(try relaunchedState.initializeConversationSelectionIfNeeded(repository: repository))
        XCTAssertNotNil(relaunchedState.selectedConversationID)
        XCTAssertNotEqual(relaunchedState.selectedConversationID, historyID)
    }

    func testLaunchPreservesExplicitNavigationSelection() throws {
        let repository = try makeFixture()
        let linkedID = try repository.createConversation(title: "Linked conversation")
        let appState = AppState()
        appState.selectedConversationID = linkedID

        XCTAssertFalse(try appState.initializeConversationSelectionIfNeeded(repository: repository))
        XCTAssertEqual(appState.selectedConversationID, linkedID)
    }

    func testRootNavigationUsesCompactColumnOnlyInCompactSizeClass() {
        XCTAssertTrue(
            RootNavigationPresentationPolicy.usesCompactColumnNavigation(horizontalSizeClass: .compact)
        )
        XCTAssertFalse(
            RootNavigationPresentationPolicy.usesCompactColumnNavigation(horizontalSizeClass: .regular)
        )
        XCTAssertFalse(
            RootNavigationPresentationPolicy.usesCompactColumnNavigation(horizontalSizeClass: nil)
        )
    }

    func testSelectionResolverKeepsValidSelectedConversationEvenIfNotInVisibleList() {
        let resolution = ConversationListSelectionResolver.resolve(
            visibleConversationIDs: [10, 9],
            selectedConversationID: 42,
            selectedConversationExists: true,
            keepSidebarAfterSecretDiscard: false
        )

        XCTAssertEqual(resolution, .keepCurrentSelection)
    }

    func testSelectionResolverSelectsLatestVisibleConversationWhenSelectedConversationWasDeleted() {
        let resolution = ConversationListSelectionResolver.resolve(
            visibleConversationIDs: [10, 9],
            selectedConversationID: 42,
            selectedConversationExists: false,
            keepSidebarAfterSecretDiscard: false
        )

        XCTAssertEqual(resolution, .select(10))
    }

    func testSelectionResolverKeepsSidebarOpenAfterSecretConversationDiscard() {
        let resolution = ConversationListSelectionResolver.resolve(
            visibleConversationIDs: [10, 9],
            selectedConversationID: nil,
            selectedConversationExists: false,
            keepSidebarAfterSecretDiscard: true
        )

        XCTAssertEqual(resolution, .keepCurrentSelection)
    }

    func testSelectionResolverClearsSelectionWhenNoVisibleOrSelectedConversationExists() {
        let resolution = ConversationListSelectionResolver.resolve(
            visibleConversationIDs: [],
            selectedConversationID: nil,
            selectedConversationExists: false,
            keepSidebarAfterSecretDiscard: false
        )

        XCTAssertEqual(resolution, .clearSelection)
    }

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

    func testCreateProjectDoesNotActivateProjectFilter() throws {
        let repository = try makeFixture()
        let viewModel = ConversationListViewModel()
        viewModel.bind(repository: repository)

        let projectId = viewModel.createProject(title: "Project A", instructions: nil)

        XCTAssertNotNil(projectId)
        XCTAssertNil(viewModel.selectedProjectId)
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

        let repository = ChatRepositoryTestSupport.makeRepository(
            dbQueue: dbQueue,
            settings: settings,
            conversations: conversations,
            credentials: credentials
        )

        return repository
    }
}
