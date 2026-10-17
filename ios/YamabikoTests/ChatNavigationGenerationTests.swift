import Combine
import GRDB
import XCTest
@testable import YamabikoChat

@MainActor
final class ChatNavigationGenerationTests: XCTestCase {
    func testSwitchingChatsKeepsRunAliveAndReusesItsState() async throws {
        try await checkNavigationDuringGeneration(regenerating: false)
    }

    func testSwitchingChatsKeepsRegenerationAliveAndReusesItsState() async throws {
        try await checkNavigationDuringGeneration(regenerating: true)
    }

    private func checkNavigationDuringGeneration(regenerating: Bool) async throws {
        let (stream, continuation) = AsyncThrowingStream<ProviderStreamEvent, Error>.makeStream()
        defer { continuation.finish() }
        let connected = expectation(description: "Pi stream connected")
        let fixture = try makeFixture { _, _, _ in
            connected.fulfill()
            return stream
        }
        let firstID = try fixture.repository.createConversation(title: "First")
        let secondID = try fixture.repository.createConversation(title: "Second")
        if regenerating {
            _ = try fixture.conversations.insertMessage(ChatMessage(
                conversationId: firstID, role: "user", text: "Explain OAuth"
            ))
            _ = try fixture.conversations.insertMessage(ChatMessage(
                conversationId: firstID, role: "model", text: "Original answer"
            ))
        }
        let store = ChatViewModelStore()
        var first: ChatViewModel? = store.viewModel(conversationID: firstID)
        await bind(try XCTUnwrap(first), repository: fixture.repository)
        weak var runningModel = first

        if regenerating {
            let loaded = expectation(description: "Original messages loaded")
            let observation = first?.$fullMessages.filter { $0.count == 2 }.prefix(1)
                .sink { _ in loaded.fulfill() }
            await fulfillment(of: [loaded], timeout: 2)
            observation?.cancel()
            first?.regenerateLastAssistantVariant()
        } else {
            first?.inputText = "Explain OAuth"
            first?.sendMessage()
        }
        // Leave before the send task gets its first opportunity to execute.
        first?.handleWorkspaceDisappearance()
        first = nil
        let second = store.viewModel(conversationID: secondID)
        XCTAssertNotNil(runningModel)
        XCTAssertFalse(second.isSending)
        store.removeConversations(ids: [])
        await fulfillment(of: [connected], timeout: 10)

        let tool = ToolCall(id: "genui-1", name: GenUITool.name, argumentsJSON: "{}")
        continuation.yield(.toolActivity(ToolActivityEvent(
            phase: .started, call: tool, result: nil, createdAtMs: 1
        )))
        continuation.yield(.textDelta("OAuth explanation"))

        let returned = store.viewModel(conversationID: firstID)
        XCTAssertTrue(returned === runningModel)
        XCTAssertTrue(returned.isSending)
        // Sending again while the original run is active must remain blocked.
        returned.inputText = "Do not send twice"
        returned.sendMessage()

        let finished = expectation(description: "Generation finished after navigation")
        let observation = returned.$isSending.filter { !$0 }.prefix(1).sink { _ in finished.fulfill() }
        defer { observation.cancel() }
        continuation.yield(.toolActivity(ToolActivityEvent(
            phase: .finished,
            call: tool,
            result: ToolResult(callId: tool.id, name: tool.name, content: "rendered"),
            createdAtMs: 2
        )))
        continuation.yield(.completed(ProviderResponse(text: "OAuth explanation")))
        continuation.finish()
        await fulfillment(of: [finished], timeout: 10)

        let saved = try fixture.conversations.fetchMessages(conversationId: firstID)
        XCTAssertEqual(saved.map(\.role), ["user", "model"])
        let assistantID = try XCTUnwrap(saved.last?.id)
        let fullMessage = try XCTUnwrap(fixture.conversations.fetchFullMessage(id: assistantID))
        let activity: ChatMessageToolActivity?
        if regenerating {
            let variant = try XCTUnwrap(fullMessage.variants.last)
            XCTAssertEqual(variant.text, "OAuth explanation")
            XCTAssertEqual(saved.last?.text, "Original answer")
            activity = fullMessage.variantToolActivities[try XCTUnwrap(variant.id)]
        } else {
            XCTAssertEqual(saved.last?.text, "OAuth explanation")
            activity = fullMessage.toolActivity
        }
        XCTAssertEqual(activity?.steps.first?.status, .completed)
        XCTAssertNil(returned.errorMessage)
        XCTAssertTrue(try fixture.conversations.fetchMessages(conversationId: secondID).isEmpty)
    }

    func testStoreDoesNotRetainIdleConversationTimelines() {
        let store = ChatViewModelStore()
        var model: ChatViewModel? = store.viewModel(conversationID: 1)
        weak var releasedModel = model
        XCTAssertTrue(store.viewModel(conversationID: 1) === model)

        model = nil

        XCTAssertNil(releasedModel)
        XCTAssertFalse(store.viewModel(conversationID: 1) === store.viewModel(conversationID: 2))
    }

    func testDeletingConversationCancelsItsRun() async throws {
        let (stream, continuation) = AsyncThrowingStream<ProviderStreamEvent, Error>.makeStream()
        defer { continuation.finish() }
        let connected = expectation(description: "Pi stream connected")
        let terminated = expectation(description: "Deleted conversation stream cancelled")
        continuation.onTermination = { _ in terminated.fulfill() }
        let fixture = try makeFixture { _, _, _ in
            connected.fulfill()
            return stream
        }
        let id = try fixture.repository.createConversation(title: "Delete while running")
        let store = ChatViewModelStore()
        let model = store.viewModel(conversationID: id)
        await bind(model, repository: fixture.repository)
        model.inputText = "Generate"
        model.sendMessage()
        await fulfillment(of: [connected], timeout: 10)

        try fixture.repository.deleteConversation(id: id)
        store.removeConversations(ids: [id])

        await fulfillment(of: [terminated], timeout: 2)
        XCTAssertNil(try fixture.repository.conversation(id: id))
    }

    func testLeavingSecretChatStillClearsSensitiveState() async throws {
        let fixture = try makeFixture(piStream: PiStreamSpy().stream)
        let id = try fixture.repository.createSecretConversation()
        let model = ChatViewModelStore().viewModel(conversationID: id)
        await bind(model, repository: fixture.repository)
        model.inputText = "Private draft"

        model.handleWorkspaceDisappearance()

        XCTAssertEqual(model.inputText, "")
        XCTAssertTrue(model.fullMessages.isEmpty)
        XCTAssertTrue(model.messageSummaries.isEmpty)
    }

    private func bind(_ model: ChatViewModel, repository: ChatRepository) async {
        let ready = expectation(description: "Settings loaded")
        let observation = model.$settings.filter { $0.apiProvider == "OPENAI" }.prefix(1)
            .sink { _ in ready.fulfill() }
        model.bind(repository: repository, attachmentRepository: AttachmentRepository())
        await fulfillment(of: [ready], timeout: 2)
        observation.cancel()
    }

    private func makeFixture(piStream: @escaping PiAgentStream) throws -> (
        repository: ChatRepository, conversations: ConversationRepository
    ) {
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database)
        let settings = SettingsRepository(dbQueue: database)
        var value = AppSettings()
        value.apiProvider = "OPENAI"
        value.defaultModel = "gpt-4o-mini"
        value.isStreamingEnabled = true
        try settings.save(value)
        let conversations = ConversationRepository(dbQueue: database)
        let credentials = PiAuthTestCredentialStore()
        try credentials.setCredential("test-key", for: .openAI)
        let repository = ChatRepositoryTestSupport.makeRepository(
            dbQueue: database, settings: settings, conversations: conversations,
            credentials: credentials, piStream: piStream
        )
        return (repository, conversations)
    }
}
