import XCTest
import GRDB
@testable import YamabikoChat

final class ContextCompactionTests: XCTestCase {
    // The compaction completion wire shape emitted by Pi, decoded rather than
    // constructing ProviderResponse so required JSON fields are exercised.
    private static let compactionJSON = #"{"text":"Pi summary","toolCalls":[],"usage":{"inputTokens":73000,"outputTokens":100,"totalTokens":73100,"contextTokens":120,"contextWindow":272000},"providerTranscript":[{"role":"user","content":"Pi summary","attachments":[]}]}"#

    @MainActor
    func testCompactionUpdatesMeterAndReplaysSummaryAfterReloadAndNextSend() async throws {
        let runtime = PiStreamSpy { request, _ in
            if request.metadata["contextOperation"] == "compact" {
                XCTAssertTrue(request.tools.isEmpty)
                return [.completed(try JSONDecoder().decode(ProviderResponse.self, from: Data(Self.compactionJSON.utf8)))]
            }
            return [.completed(ProviderResponse(text: "Hi!", usage: ProviderUsage(
                inputTokens: 200, outputTokens: 10, totalTokens: 210,
                contextTokens: 210, contextWindow: 272000
            )))]
        }
        let fixture = try makeFixture(runtime: runtime)
        let viewModel = ChatViewModel(conversationID: fixture.id)
        viewModel.bind(repository: fixture.repository, attachmentRepository: AttachmentRepository())
        try await waitUntil { viewModel.canCompactContext }
        XCTAssertEqual(viewModel.visibleContextUsage?.usedTokens, 73554)

        viewModel.compactContext()
        try await waitUntil { !viewModel.isCompacting }
        XCTAssertNil(viewModel.errorMessage)
        XCTAssertNil(viewModel.compactionErrorMessage)
        XCTAssertEqual(viewModel.visibleContextUsage, ContextUsage(
            usedTokens: 120, contextWindow: 272000, isCompactedEstimate: true
        ))
        let reloaded = try XCTUnwrap(ConversationRepository(dbQueue: fixture.queue).contextCheckpoint(conversationId: fixture.id))
        XCTAssertEqual(reloaded.messages.map(\.content), ["Pi summary"])
        XCTAssertEqual(try fixture.conversations.fetchMessages(conversationId: fixture.id).count, 2)

        let repository = try makeRepository(queue: fixture.queue, runtime: runtime)
        _ = try await repository.sendMessage(conversationId: fixture.id, text: "hi", attachments: [])
        XCTAssertEqual(runtime.calls.count, 2)
        XCTAssertEqual(runtime.calls.last?.request.messages.map(\.content), ["Pi summary", "hi"])
        XCTAssertEqual(runtime.calls.last?.configuration.model, runtime.calls.first?.configuration.model)
        XCTAssertEqual(runtime.calls.last?.configuration.provider, runtime.calls.first?.configuration.provider)
        try await waitUntil { viewModel.visibleContextUsage?.usedTokens == 210 }
        XCTAssertEqual(viewModel.visibleContextUsage?.isCompactedEstimate, false)
        XCTAssertNil(try repository.compactedContextUsage(conversationId: fixture.id))
        let usage = try await fixture.queue.read {
            try TokenUsageRecord.filter(Column("conversationId") == fixture.id).order(Column("id")).fetchAll($0)
        }
        XCTAssertEqual(usage.filter { $0.requestType == "compaction" }.map(\.contextTokens), [120])
    }

    @MainActor
    func testMalformedCompactionResponseKeepsHistoryAndShowsFailure() async throws {
        let runtime = PiStreamSpy { _, _ in
            // Reproduce the original runtime response: synthesized Codable does
            // not use the default [] when a nonoptional toolCalls key is absent.
            let malformed = Self.compactionJSON.replacingOccurrences(of: #""toolCalls":[],"#, with: "")
            return [.completed(try JSONDecoder().decode(ProviderResponse.self, from: Data(malformed.utf8)))]
        }
        let fixture = try makeFixture(runtime: runtime)
        let viewModel = ChatViewModel(conversationID: fixture.id)
        viewModel.bind(repository: fixture.repository, attachmentRepository: AttachmentRepository())
        try await waitUntil { viewModel.canCompactContext }
        let original = try fixture.conversations.fetchProviderHistory(conversationId: fixture.id).flatMap(\.providerMessages)

        viewModel.compactContext()
        try await waitUntil { !viewModel.isCompacting }
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertNotNil(viewModel.compactionErrorMessage)
        XCTAssertNil(viewModel.visibleErrorMessage, "Technical details remain in diagnostics")
        XCTAssertEqual(viewModel.visibleContextUsage?.usedTokens, 73554)
        XCTAssertNil(try fixture.conversations.contextCheckpoint(conversationId: fixture.id))
        let current = try fixture.conversations.fetchProviderHistory(conversationId: fixture.id).flatMap(\.providerMessages)
        XCTAssertEqual(try ConversationContextCheckpoint.digest(current), try ConversationContextCheckpoint.digest(original))
        XCTAssertEqual(runtime.calls.count, 1, "A failure must not retry through another provider or model")
        XCTAssertFalse(viewModel.isSending)
        XCTAssertTrue(viewModel.canCompactContext)

        viewModel.compactContext()
        XCTAssertNil(viewModel.compactionErrorMessage, "A new attempt clears the previous operation status")
        try await waitUntil { !viewModel.isCompacting }
    }

    func testCheckpointReplaysAfterReloadAndAppendsOnlyNewMessages() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue)
        let repository = ConversationRepository(dbQueue: queue)
        let id = try repository.createConversation(title: "Test", model: "model", provider: "TEST")
        let conversation = try XCTUnwrap(repository.fetchConversation(id: id))
        let source = [ProviderRequestMessage(role: "user", content: "question"),
                      ProviderRequestMessage(role: "assistant", content: "answer")]
        let checkpoint = try makeCheckpoint(source: source, conversation: conversation)
        try repository.saveContextCheckpoint(checkpoint, conversationId: id)
        let reloaded = try XCTUnwrap(ConversationRepository(dbQueue: queue).contextCheckpoint(conversationId: id))
        let next = ProviderRequestMessage(role: "user", content: "next question")
        let applied = try XCTUnwrap(reloaded.applying(to: source + [next], conversation: conversation))
        XCTAssertEqual(applied.map(\.content), ["Pi summary", "next question"])
        XCTAssertEqual(try reloaded.applying(to: source, conversation: conversation)?.map(\.content), ["Pi summary"])
        try repository.deleteConversation(id: id)
        XCTAssertEqual(try queue.read { try Int.fetchOne($0, sql: "SELECT COUNT(*) FROM conversation_context_checkpoints") }, 0)
    }

    func testCheckpointRejectsEditedHistoryVariantsAndRegeneration() throws {
        let conversation = Conversation(title: "Test", model: "model", apiProvider: "TEST")
        let source = [ProviderRequestMessage(role: "user", content: "question"),
                      ProviderRequestMessage(role: "assistant", content: "original answer")]
        let checkpoint = try makeCheckpoint(source: source, conversation: conversation)
        var edited = source
        edited[1].content = "selected variant"
        XCTAssertNil(try checkpoint.applying(to: edited, conversation: conversation))
        XCTAssertNil(try checkpoint.applying(to: Array(source.dropLast()), conversation: conversation))
        edited = source
        edited[1].piMessage = .object(["providerSpecific": .string("changed")])
        XCTAssertNil(try checkpoint.applying(to: edited, conversation: conversation))
        for key in ["model", "provider", "prompt"] {
            var changed = conversation
            if key == "model" { changed.model = "other" }
            if key == "provider" { changed.apiProvider = "OTHER" }
            if key == "prompt" { changed.systemPrompt = "Changed instructions" }
            XCTAssertNil(try checkpoint.applying(to: source, conversation: changed))
        }
    }

    func testSecretCheckpointIsEncryptedAtRest() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue)
        let repository = ConversationRepository(dbQueue: queue)
        let id = try repository.createConversation(title: "Secret", model: "model", provider: "TEST", isSecret: true)
        defer { try? repository.deleteConversation(id: id) }
        let conversation = try XCTUnwrap(repository.fetchConversation(id: id))
        let source = [ProviderRequestMessage(role: "user", content: "private question")]
        try repository.saveContextCheckpoint(makeCheckpoint(source: source, conversation: conversation), conversationId: id)
        let stored = try queue.read { try String.fetchOne($0, sql: "SELECT payload FROM conversation_context_checkpoints") }
        XCTAssertFalse(try XCTUnwrap(stored).contains("Pi summary"))
        XCTAssertEqual(try repository.contextCheckpoint(conversationId: id)?.messages.first?.content, "Pi summary")
    }

    private func makeCheckpoint(source: [ProviderRequestMessage], conversation: Conversation) throws -> ConversationContextCheckpoint {
        ConversationContextCheckpoint(provider: conversation.apiProvider, model: conversation.model,
                                      systemPrompt: conversation.systemPrompt, sourceCount: source.count,
                                      sourceDigest: try ConversationContextCheckpoint.digest(source),
                                      messages: [ProviderRequestMessage(role: "user", content: "Pi summary")],
                                      usage: ProviderUsage(contextTokens: 20, contextWindow: 128000))
    }

    private func makeFixture(runtime: PiStreamSpy) throws -> (
        queue: DatabaseQueue, repository: ChatRepository, conversations: ConversationRepository, id: Int64
    ) {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue)
        let conversations = ConversationRepository(dbQueue: queue)
        let id = try conversations.createConversation(title: "Compaction", model: "openai/gpt-4o-mini", provider: "OPENROUTER")
        _ = try conversations.insertMessage(ChatMessage(conversationId: id, role: "user", text: "original question", createdAtMs: 1))
        let assistantID = try conversations.insertMessage(ChatMessage(conversationId: id, role: "model", text: "original answer", createdAtMs: 2))
        try conversations.saveToolActivity(messageId: assistantID, variantId: nil, payload: ToolActivityPayload(providerTranscript: [
            ProviderRequestMessage(role: "assistant", content: "", toolCalls: [ToolCall(id: "call", name: "web_search", argumentsJSON: "{}")]),
            ProviderRequestMessage(role: "tool", content: "large search result", toolCallId: "call", toolName: "web_search"),
            ProviderRequestMessage(role: "assistant", content: "original answer", piMessage: .object([
                "role": .string("assistant"), "content": .array([.object(["type": .string("text"), "text": .string("original answer")])])
            ]))
        ]))
        try conversations.insertTokenUsage(TokenUsageRecord(
            provider: "OPENROUTER", model: "openai/gpt-4o-mini", conversationId: id,
            inputTokens: 73320, outputTokens: 234, totalTokens: 73554, contextTokens: 73554, contextWindow: 272000
        ))
        return (queue, try makeRepository(queue: queue, runtime: runtime), conversations, id)
    }

    private func makeRepository(queue: DatabaseQueue, runtime: PiStreamSpy) throws -> ChatRepository {
        let credentials = CompactionCredentialStore()
        try credentials.setCredential("test-key", for: .openRouter)
        return ChatRepositoryTestSupport.makeRepository(
            dbQueue: queue, settings: SettingsRepository(dbQueue: queue),
            conversations: ConversationRepository(dbQueue: queue), credentials: credentials, piStream: runtime.stream
        )
    }

    @MainActor
    private func waitUntil(_ condition: () -> Bool, file: StaticString = #filePath, line: UInt = #line) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Compaction state did not settle", file: file, line: line)
    }
}

private final class CompactionCredentialStore: SecureCredentialStore {
    private var values: [String: String] = [:]
    func saveSecret(_ value: String?, key: String) throws { values[key] = value }
    func readSecret(key: String) throws -> String? { values[key] }
    func deleteSecret(key: String) throws { values.removeValue(forKey: key) }
}
