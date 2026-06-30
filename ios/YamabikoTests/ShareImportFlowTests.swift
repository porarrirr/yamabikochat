import XCTest
import GRDB
@testable import YamabikoChat

@MainActor
final class ShareImportFlowTests: XCTestCase {
    private var tempContainerURL: URL!

    override func setUp() {
        super.setUp()
        tempContainerURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("share-import-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempContainerURL, withIntermediateDirectories: true)
        AppGroupShareStorage.testContainerURL = tempContainerURL
    }

    override func tearDown() {
        AppGroupShareStorage.testContainerURL = nil
        try? FileManager.default.removeItem(at: tempContainerURL)
        super.tearDown()
    }

    func testImportSharePayloadCreatesNewConversationAndDraft() throws {
        let repository = try makeRepository()
        let store = SharePayloadStore()
        SharePayloadPersister.save(text: "shared from Safari", sourceApp: "Safari")

        let appState = AppState()
        XCTAssertTrue(appState.importSharePayload(from: store, repository: repository))

        let draft = try XCTUnwrap(appState.shareImportDraft)
        XCTAssertEqual(draft.text, "shared from Safari")
        XCTAssertEqual(appState.selectedConversationID, draft.conversationID)

        let conversation = try repository.conversation(id: draft.conversationID)
        XCTAssertNotNil(conversation)

        XCTAssertEqual(appState.shareImportText(for: draft.conversationID), "shared from Safari")
        appState.clearShareImportDraft(for: draft.conversationID)
        XCTAssertNil(appState.shareImportDraft)
        XCTAssertNil(appState.shareImportText(for: draft.conversationID))
    }

    func testImportSharePayloadReturnsFalseWhenNoPayload() throws {
        let repository = try makeRepository()
        let store = SharePayloadStore()
        let appState = AppState()

        XCTAssertFalse(appState.importSharePayload(from: store, repository: repository))
        XCTAssertNil(appState.shareImportDraft)
    }

    private func makeRepository() throws -> ChatRepository {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)

        let settings = SettingsRepository(dbQueue: dbQueue)
        let conversations = ConversationRepository(dbQueue: dbQueue)
        let credentials = ShareImportTestCredentialStore()
        return ChatRepositoryTestSupport.makeRepository(
            dbQueue: dbQueue,
            settings: settings,
            conversations: conversations,
            credentials: credentials,
            httpClient: URLSessionHTTPClient()
        )
    }
}

private final class ShareImportTestCredentialStore: SecureCredentialStore {
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
