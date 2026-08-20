import XCTest
import GRDB
@testable import YamabikoChat

private final class ChatViewModelAttachmentCredentialStore: SecureCredentialStore {
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
final class ChatViewModelAttachmentTests: XCTestCase {
    func testAddAttachmentShowsErrorWhenRepositoryNotBound() throws {
        let viewModel = ChatViewModel(conversationID: 1)
        let file = try makeTemporaryFile(name: "unbound.txt", text: "draft")
        defer { try? FileManager.default.removeItem(at: file) }

        XCTAssertFalse(viewModel.addAttachment(url: file))

        XCTAssertEqual(viewModel.attachments.count, 0)
        XCTAssertEqual(viewModel.errorMessage, L10n.text("チャット初期化中です。少し待ってから再試行してください。"))
    }

    func testAddAttachmentAddsDraftWhenBoundAndFileIsValid() throws {
        let fixture = try makeFixture()
        let conversationId = try fixture.repository.createConversation(title: "Attachment Test")
        let viewModel = ChatViewModel(conversationID: conversationId)
        viewModel.bind(
            repository: fixture.repository,
            attachmentRepository: AttachmentRepository()
        )

        let source = try makeTemporaryFile(name: "valid.txt", text: "attachment body")
        defer { try? FileManager.default.removeItem(at: source) }

        XCTAssertTrue(viewModel.addAttachment(url: source))

        XCTAssertEqual(viewModel.attachments.count, 1)
        XCTAssertEqual(viewModel.attachments.first?.displayName, "valid.txt")
        XCTAssertNil(viewModel.errorMessage)

        if let persisted = viewModel.attachments.first?.url {
            try? FileManager.default.removeItem(at: persisted)
        }
    }

    func testAddAttachmentDeletesOwnedTemporarySourceAfterImport() throws {
        let fixture = try makeFixture()
        let conversationId = try fixture.repository.createConversation(title: "Attachment Cleanup Test")
        let viewModel = ChatViewModel(conversationID: conversationId)
        viewModel.bind(
            repository: fixture.repository,
            attachmentRepository: AttachmentRepository()
        )

        let source = try makeTemporaryFile(name: "owned.txt", text: "temporary attachment")

        XCTAssertTrue(viewModel.addAttachment(url: source, deleteSourceWhenHandled: true))

        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(viewModel.attachments.count, 1)

        if let persisted = viewModel.attachments.first?.url {
            try? FileManager.default.removeItem(at: persisted)
        }
    }

    private func makeTemporaryFile(name: String, text: String) throws -> URL {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try text.data(using: .utf8)?.write(to: file)
        return file
    }

    private func makeFixture() throws -> (
        repository: ChatRepository,
        conversations: ConversationRepository
    ) {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)

        let settings = SettingsRepository(dbQueue: dbQueue)
        let conversations = ConversationRepository(dbQueue: dbQueue)
        let credentials = ChatViewModelAttachmentCredentialStore()
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

final class RecentPhotoSelectionTests: XCTestCase {
    func testTogglePreservesSelectionOrderAndRenumbersAfterDeselection() {
        var selection = RecentPhotoSelection(limit: 3)

        XCTAssertTrue(selection.toggle("first"))
        XCTAssertTrue(selection.toggle("second"))
        XCTAssertEqual(selection.orderedIDs, ["first", "second"])
        XCTAssertEqual(selection.selectionIndex(for: "first"), 1)
        XCTAssertEqual(selection.selectionIndex(for: "second"), 2)

        XCTAssertTrue(selection.toggle("first"))
        XCTAssertEqual(selection.orderedIDs, ["second"])
        XCTAssertNil(selection.selectionIndex(for: "first"))
        XCTAssertEqual(selection.selectionIndex(for: "second"), 1)
    }

    func testToggleRejectsNewSelectionAtLimitButStillAllowsDeselection() {
        var selection = RecentPhotoSelection(limit: 2)

        XCTAssertTrue(selection.toggle("first"))
        XCTAssertTrue(selection.toggle("second"))
        XCTAssertTrue(selection.isAtLimit)
        XCTAssertFalse(selection.toggle("third"))
        XCTAssertEqual(selection.orderedIDs, ["first", "second"])

        XCTAssertTrue(selection.toggle("first"))
        XCTAssertFalse(selection.isAtLimit)
        XCTAssertEqual(selection.orderedIDs, ["second"])
    }

    func testRemoveAllClearsSelection() {
        var selection = RecentPhotoSelection(limit: 2)
        selection.toggle("first")

        selection.removeAll()

        XCTAssertTrue(selection.isEmpty)
        XCTAssertEqual(selection.count, 0)
    }
}

final class RecentPhotoThumbnailTests: XCTestCase {
    func testDegradedImageWaitsForFinalResult() {
        let decision = RecentPhotoThumbnailResultDecision.resolve(
            isCancelled: false,
            isDegraded: true,
            hasImage: true,
            hasError: false
        )

        XCTAssertEqual(decision, .waitForFinalImage)
    }

    func testFinalImageIsAcceptedAndTerminalFailuresReturnNil() {
        let finalImageDecision = RecentPhotoThumbnailResultDecision.resolve(
            isCancelled: false,
            isDegraded: false,
            hasImage: true,
            hasError: false
        )
        let missingImageDecision = RecentPhotoThumbnailResultDecision.resolve(
            isCancelled: false,
            isDegraded: false,
            hasImage: false,
            hasError: false
        )
        let errorDecision = RecentPhotoThumbnailResultDecision.resolve(
            isCancelled: false,
            isDegraded: false,
            hasImage: true,
            hasError: true
        )
        let cancelledDecision = RecentPhotoThumbnailResultDecision.resolve(
            isCancelled: true,
            isDegraded: false,
            hasImage: true,
            hasError: false
        )

        XCTAssertEqual(finalImageDecision, .returnImage)
        XCTAssertEqual(missingImageDecision, .returnNil)
        XCTAssertEqual(errorDecision, .returnNil)
        XCTAssertEqual(cancelledDecision, .returnNil)
    }
}
