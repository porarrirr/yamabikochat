import XCTest
import GRDB
@testable import YamabikoChat

private final class DualTestCredentialStore: SecureCredentialStore {
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

final class ChatRepositoryDualTests: XCTestCase {
    func testSendDualMessageStoresUserAndModelRowsSeparately() async throws {
        let runtime = Self.responseRuntime()
        let fixture = try makeFixture(runtime: runtime) { settings in
            settings.dualProviderA = "OPENAI"
            settings.dualProviderB = "OPENAI"
            settings.dualModelA = "model-a"
            settings.dualModelB = "model-b"
            settings.isDualModeEnabled = true
            settings.isStreamingEnabled = false
        }
        try fixture.credentials.setCredential("test-api-key", for: .openAI)

        let conversationID = try fixture.repository.createConversation(title: "New Chat")
        let result = try await fixture.repository.sendDualMessage(
            conversationId: conversationID,
            text: "hello dual",
            attachments: ["file:///tmp/sample.txt"]
        )

        let rows = try fixture.conversations.fetchDualMessages(conversationId: conversationID)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].parsedRole, .user)
        XCTAssertEqual(rows[0].userText, "hello dual")
        XCTAssertEqual(rows[0].attachments, ["file:///tmp/sample.txt"])
        XCTAssertEqual(rows[1].parsedRole, .dualModel)
        XCTAssertEqual(rows[1].modelAText, "response-model-a")
        XCTAssertEqual(rows[1].modelBText, "response-model-b")
        XCTAssertEqual(rows[1].parsedModelAStatus, .completed)
        XCTAssertEqual(rows[1].parsedModelBStatus, .completed)
        XCTAssertEqual(result.parsedRole, .dualModel)
    }

    func testSendDualMessageBuildsIndependentHistoryPerSide() async throws {
        let runtime = Self.responseRuntime()
        let fixture = try makeFixture(runtime: runtime) { settings in
            settings.dualProviderA = "OPENAI"
            settings.dualProviderB = "OPENAI"
            settings.dualModelA = "model-a"
            settings.dualModelB = "model-b"
            settings.isDualModeEnabled = true
            settings.isStreamingEnabled = false
        }
        try fixture.credentials.setCredential("test-api-key", for: .openAI)

        let conversationID = try fixture.repository.createConversation(title: "New Chat")
        _ = try await fixture.repository.sendDualMessage(conversationId: conversationID, text: "first")
        _ = try await fixture.repository.sendDualMessage(conversationId: conversationID, text: "second")

        let modelARequests = runtime.calls.map(\.request).filter { $0.model == "model-a" }
        let modelBRequests = runtime.calls.map(\.request).filter { $0.model == "model-b" }
        XCTAssertGreaterThanOrEqual(modelARequests.count, 2)
        XCTAssertGreaterThanOrEqual(modelBRequests.count, 2)
        XCTAssertEqual(modelARequests.last?.metadata["editorSessionId"], String(conversationID))
        XCTAssertEqual(modelBRequests.last?.metadata["editorSessionId"], String(conversationID))

        let modelAJoined = modelARequests.last?.messages.map(\.content).joined(separator: "\n") ?? ""
        XCTAssertTrue(modelAJoined.contains("response-model-a"))
        XCTAssertFalse(modelAJoined.contains("response-model-b"))

        let modelBJoined = modelBRequests.last?.messages.map(\.content).joined(separator: "\n") ?? ""
        XCTAssertTrue(modelBJoined.contains("response-model-b"))
        XCTAssertFalse(modelBJoined.contains("response-model-a"))
    }

    func testSendDualMessageKeepsPartialSuccessWhenOneSideFails() async throws {
        let runtime = Self.responseRuntime(failingModels: ["model-b"])
        let fixture = try makeFixture(runtime: runtime) { settings in
            settings.dualProviderA = "OPENAI"
            settings.dualProviderB = "OPENAI"
            settings.dualModelA = "model-a"
            settings.dualModelB = "model-b"
            settings.isDualModeEnabled = true
            settings.isStreamingEnabled = false
        }
        try fixture.credentials.setCredential("test-api-key", for: .openAI)

        let conversationID = try fixture.repository.createConversation(title: "New Chat")
        let result = try await fixture.repository.sendDualMessage(conversationId: conversationID, text: "hello")

        XCTAssertEqual(result.modelAText, "response-model-a")
        XCTAssertEqual(result.modelBText, "")
        XCTAssertEqual(result.parsedModelAStatus, .completed)
        XCTAssertEqual(result.parsedModelBStatus, .failed)
        XCTAssertEqual(result.modelBError, "Response parse failed: forced failure")
        let rows = try fixture.conversations.fetchDualMessages(conversationId: conversationID)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.last?.parsedRole, .dualModel)
    }

    private func makeFixture(
        runtime: PiStreamSpy? = nil,
        configureSettings: ((inout AppSettings) -> Void)? = nil
    ) throws -> (
        repository: ChatRepository,
        conversations: ConversationRepository,
        credentials: DualTestCredentialStore
    ) {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)

        let settings = SettingsRepository(dbQueue: dbQueue)
        let conversations = ConversationRepository(dbQueue: dbQueue)
        let credentials = DualTestCredentialStore()
        if configureSettings != nil {
            var current = try settings.load()
            configureSettings?(&current)
            try settings.save(current)
        }

        let runtime = runtime ?? Self.responseRuntime()
        let repository = ChatRepositoryTestSupport.makeRepository(
            dbQueue: dbQueue,
            settings: settings,
            conversations: conversations,
            credentials: credentials,
            piStream: runtime.stream
        )
        return (repository, conversations, credentials)
    }

    private static func responseRuntime(failingModels: Set<String> = []) -> PiStreamSpy {
        PiStreamSpy { request, _ in
            if failingModels.contains(request.model) {
                throw ProviderClientError.parseFailure("forced failure")
            }
            return [.completed(ProviderResponse(text: "response-\(request.model)"))]
        }
    }
}
