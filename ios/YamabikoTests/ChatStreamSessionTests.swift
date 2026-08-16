import XCTest
import GRDB
@testable import YamabikoChat

final class ChatStreamSessionTests: XCTestCase {
    func testRunPersistsTextDeltasToMessage() async throws {
        let conversations = try makeConversations()
        let conversationId = try conversations.createConversation(
            title: "test",
            model: "gpt-4o-mini",
            provider: "OPENAI"
        )
        let messageId = try conversations.insertMessage(
            ChatMessage(conversationId: conversationId, role: "model", text: "", createdAtMs: 1)
        )

        let stream = AsyncThrowingStream<ProviderStreamEvent, Error> { continuation in
            continuation.yield(.textDelta("Hel"))
            continuation.yield(.textDelta("lo"))
            continuation.finish()
        }

        let session = try await ChatStreamSession.run(
            stream: stream,
            conversations: conversations,
            kind: .message(messageId: messageId),
            onStreamEvent: nil,
            onStreamingSnapshot: nil
        )

        XCTAssertEqual(session.text, "Hello")
        let messages = try conversations.fetchMessages(conversationId: conversationId)
        XCTAssertEqual(messages.last?.text, "Hello")
    }

    func testRunWritesErrorPlaceholderWhenStreamFailsBeforeContent() async throws {
        let conversations = try makeConversations()
        let conversationId = try conversations.createConversation(
            title: "test",
            model: "gpt-4o-mini",
            provider: "OPENAI"
        )
        let messageId = try conversations.insertMessage(
            ChatMessage(conversationId: conversationId, role: "model", text: "", createdAtMs: 1)
        )

        struct TestStreamError: Error {}
        let streamError = TestStreamError()
        let stream = AsyncThrowingStream<ProviderStreamEvent, Error> { continuation in
            continuation.finish(throwing: streamError)
        }

        do {
            _ = try await ChatStreamSession.run(
                stream: stream,
                conversations: conversations,
                kind: .message(messageId: messageId),
                onStreamEvent: nil,
                onStreamingSnapshot: nil
            )
            XCTFail("Expected stream error")
        } catch is TestStreamError {
            let messages = try conversations.fetchMessages(conversationId: conversationId)
            XCTAssertEqual(
                messages.last?.text,
                UserFacingErrorFormatter.placeholder(for: streamError)
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testRunDoesNotOverwritePartialStreamOnFailure() async throws {
        let conversations = try makeConversations()
        let conversationId = try conversations.createConversation(
            title: "test",
            model: "gpt-4o-mini",
            provider: "OPENAI"
        )
        let messageId = try conversations.insertMessage(
            ChatMessage(conversationId: conversationId, role: "model", text: "", createdAtMs: 1)
        )

        struct TestStreamError: Error {}
        let stream = AsyncThrowingStream<ProviderStreamEvent, Error> { continuation in
            continuation.yield(.textDelta("partial"))
            continuation.finish(throwing: TestStreamError())
        }

        do {
            _ = try await ChatStreamSession.run(
                stream: stream,
                conversations: conversations,
                kind: .message(messageId: messageId),
                onStreamEvent: nil,
                onStreamingSnapshot: nil
            )
            XCTFail("Expected stream error")
        } catch is TestStreamError {
            let messages = try conversations.fetchMessages(conversationId: conversationId)
            XCTAssertEqual(messages.last?.text, "partial")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func makeConversations() throws -> ConversationRepository {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)
        return ConversationRepository(dbQueue: dbQueue)
    }
}
