import XCTest
import GRDB
@testable import YamabikoChat

final class ContextCompactionTests: XCTestCase {
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
}
