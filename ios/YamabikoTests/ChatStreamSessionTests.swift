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

    func testRunPublishesAndPersistsToolActivity() async throws {
        let conversations = try makeConversations()
        let conversationId = try conversations.createConversation(title: "test", model: "gpt", provider: "OPENAI")
        let messageId = try conversations.insertMessage(
            ChatMessage(conversationId: conversationId, role: "model", text: "", createdAtMs: 1)
        )
        let call = ToolCall(id: "call-1", name: WebSearchTool.name, argumentsJSON: #"{"query":"live query"}"#)
        let result = ToolResult(
            callId: call.id,
            name: call.name,
            content: #"{"results":[]}"#,
            sources: [],
            artifacts: [ToolArtifact(path: "/tmp/generated.png", name: "generated.png", mime: "image/png", size: 12)]
        )
        let snapshots = StreamingSnapshotCollector()
        let stream = AsyncThrowingStream<ProviderStreamEvent, Error> { continuation in
            continuation.yield(.toolActivity(ToolActivityEvent(phase: .started, call: call, result: nil, createdAtMs: 1)))
            continuation.yield(.toolActivity(ToolActivityEvent(phase: .finished, call: call, result: result, createdAtMs: 1)))
            continuation.yield(.completed(ProviderResponse(text: "done", reasoningSummary: nil, raw: nil, usage: nil)))
            continuation.finish()
        }

        _ = try await ChatStreamSession.run(
            stream: stream,
            conversations: conversations,
            kind: .message(messageId: messageId),
            onStreamEvent: nil,
            onStreamingSnapshot: { snapshots.append($0) }
        )

        XCTAssertTrue(snapshots.values.contains { $0.toolActivity?.steps.first?.status == .running })
        let persisted = try conversations.fetchFullMessage(id: messageId)
        XCTAssertEqual(persisted?.toolActivity?.steps.first?.status, .completed)
        let attachmentData = try XCTUnwrap(persisted?.displayAttachmentsJSON.data(using: .utf8))
        XCTAssertEqual(try JSONDecoder().decode([String].self, from: attachmentData), ["/tmp/generated.png"])
    }

    private func makeConversations() throws -> ConversationRepository {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)
        return ConversationRepository(dbQueue: dbQueue)
    }
}

private final class StreamingSnapshotCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ChatStreamingSnapshot] = []

    func append(_ snapshot: ChatStreamingSnapshot) {
        lock.lock()
        storage.append(snapshot)
        lock.unlock()
    }

    var values: [ChatStreamingSnapshot] {
        lock.lock()
        let copy = storage
        lock.unlock()
        return copy
    }
}
