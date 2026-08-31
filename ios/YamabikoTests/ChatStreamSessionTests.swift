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

    func testRunReplacesIntermediateToolTurnTextWithFinalAnswer() async throws {
        let conversations = try makeConversations()
        let conversationId = try conversations.createConversation(
            title: "test",
            model: "deepseek-v4-flash",
            provider: "MODELS_DEV:OPENCODE-GO"
        )
        let messageId = try conversations.insertMessage(
            ChatMessage(conversationId: conversationId, role: "model", text: "", createdAtMs: 1)
        )
        let snapshots = StreamingSnapshotCollector()
        let stream = AsyncThrowingStream<ProviderStreamEvent, Error> { continuation in
            continuation.yield(.answerStart)
            continuation.yield(.reasoningDelta("search reasoning"))
            continuation.yield(.textDelta("検索結果が見つかりました。詳細を確認します。"))
            continuation.yield(.answerStart)
            continuation.yield(.reasoningDelta("\nfinal reasoning"))
            continuation.yield(.textDelta("最終回答"))
            continuation.yield(.completed(ProviderResponse(
                text: "最終回答",
                reasoningSummary: "search reasoning\nfinal reasoning",
                raw: nil,
                usage: nil
            )))
            continuation.finish()
        }

        let session = try await ChatStreamSession.run(
            stream: stream,
            conversations: conversations,
            kind: .message(messageId: messageId),
            onStreamEvent: nil,
            onStreamingSnapshot: { snapshots.append($0) }
        )

        XCTAssertEqual(session.text, "最終回答")
        XCTAssertEqual(session.reasoningText, "search reasoning\nfinal reasoning")
        XCTAssertTrue(snapshots.values.contains { $0.text.contains("検索結果が見つかりました") })
        XCTAssertEqual(snapshots.values.last?.text, "最終回答")
        let messages = try conversations.fetchMessages(conversationId: conversationId)
        XCTAssertEqual(messages.last?.text, "最終回答")
        XCTAssertEqual(
            try conversations.fetchFullMessage(id: messageId)?.thinkingStream,
            "search reasoning\nfinal reasoning"
        )
    }

    func testRunPersistsExactGroupedPiToolTranscriptFromCompletion() async throws {
        let conversations = try makeConversations()
        let conversationId = try conversations.createConversation(
            title: "test",
            model: "deepseek-v4-flash",
            provider: "MODELS_DEV:OPENCODE-GO"
        )
        let messageId = try conversations.insertMessage(
            ChatMessage(conversationId: conversationId, role: "model", text: "", createdAtMs: 1)
        )
        let first = ToolCall(id: "search-1", name: WebSearchTool.name, argumentsJSON: #"{"query":"東京"}"#)
        let second = ToolCall(id: "search-2", name: WebSearchTool.name, argumentsJSON: #"{"query":"大阪"}"#)
        let firstResult = ToolResult(callId: first.id, name: first.name, content: #"{"results":[]}"#)
        let secondResult = ToolResult(callId: second.id, name: second.name, content: #"{"results":[]}"#)
        let exactTranscript = [
            ProviderRequestMessage(role: "assistant", content: "", toolCalls: [first, second]),
            ProviderRequestMessage(
                role: "tool",
                content: firstResult.content,
                toolCallId: first.id,
                toolName: first.name,
                toolResultIsError: false
            ),
            ProviderRequestMessage(
                role: "tool",
                content: secondResult.content,
                toolCallId: second.id,
                toolName: second.name,
                toolResultIsError: false
            )
        ]
        let stream = AsyncThrowingStream<ProviderStreamEvent, Error> { continuation in
            for call in [first, second] {
                continuation.yield(.toolActivity(ToolActivityEvent(
                    phase: .started,
                    call: call,
                    result: nil,
                    createdAtMs: 1
                )))
            }
            continuation.yield(.toolActivity(ToolActivityEvent(
                phase: .finished,
                call: first,
                result: firstResult,
                createdAtMs: 2
            )))
            continuation.yield(.toolActivity(ToolActivityEvent(
                phase: .finished,
                call: second,
                result: secondResult,
                createdAtMs: 2
            )))
            continuation.yield(.completed(ProviderResponse(
                text: "done",
                reasoningSummary: nil,
                raw: nil,
                usage: nil,
                providerTranscript: exactTranscript
            )))
            continuation.finish()
        }

        let session = try await ChatStreamSession.run(
            stream: stream,
            conversations: conversations,
            kind: .message(messageId: messageId),
            onStreamEvent: nil,
            onStreamingSnapshot: nil
        )

        XCTAssertEqual(session.toolActivity?.providerTranscript, exactTranscript)
        let history = try conversations.fetchProviderHistory(conversationId: conversationId)
        XCTAssertEqual(history.last?.toolTranscript.map(\.role), ["assistant", "tool", "tool"])
        XCTAssertEqual(history.last?.toolTranscript.first?.toolCalls?.map(\.id), [first.id, second.id])
        XCTAssertEqual(history.last?.providerMessages.map(\.role), ["assistant", "tool", "tool", "assistant"])
        XCTAssertEqual(history.last?.providerMessages.first?.toolCalls?.count, 2)
    }

    func testRunTreatsCompletedTextAsAuthoritativeWithoutTurnBoundary() async throws {
        let conversations = try makeConversations()
        let conversationId = try conversations.createConversation(
            title: "test",
            model: "deepseek-v4-flash",
            provider: "MODELS_DEV:OPENCODE-GO"
        )
        let messageId = try conversations.insertMessage(
            ChatMessage(conversationId: conversationId, role: "model", text: "", createdAtMs: 1)
        )
        let stream = AsyncThrowingStream<ProviderStreamEvent, Error> { continuation in
            continuation.yield(.textDelta("途中経過"))
            continuation.yield(.textDelta("最終回答"))
            continuation.yield(.completed(ProviderResponse(
                text: "最終回答",
                reasoningSummary: nil,
                raw: nil,
                usage: nil
            )))
            continuation.finish()
        }

        let session = try await ChatStreamSession.run(
            stream: stream,
            conversations: conversations,
            kind: .message(messageId: messageId),
            onStreamEvent: nil,
            onStreamingSnapshot: nil
        )

        XCTAssertEqual(session.text, "最終回答")
        XCTAssertEqual(try conversations.fetchMessages(conversationId: conversationId).last?.text, "最終回答")
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

    func testRunPersistsPiExecutionSnapshotBeforeStreamFailure() async throws {
        let conversations = try makeConversations()
        let conversationId = try conversations.createConversation(
            title: "test",
            model: "gpt-4o-mini",
            provider: "OPENAI"
        )
        let messageId = try conversations.insertMessage(
            ChatMessage(conversationId: conversationId, role: "model", text: "", createdAtMs: 1)
        )
        let call = ToolCall(id: "search-1", name: WebSearchTool.name, argumentsJSON: #"{"query":"Tokyo"}"#)
        let transcript = [
            ProviderRequestMessage(role: "assistant", content: "", toolCalls: [call]),
            ProviderRequestMessage(
                role: "tool",
                content: #"{"results":[]}"#,
                toolCallId: call.id,
                toolName: call.name,
                toolResultIsError: false
            )
        ]
        let transcriptValue = try JSONDecoder().decode(
            JSONValue.self,
            from: JSONEncoder().encode(transcript)
        )
        let execution: JSONValue = .object([
            "format": .string("yamabiko.pi-agent-execution"),
            "providerTranscript": transcriptValue,
            "failure": .object(["message": .string("provider failed")])
        ])

        struct TestStreamError: Error {}
        let stream = AsyncThrowingStream<ProviderStreamEvent, Error> { continuation in
            continuation.yield(.executionSnapshot(execution))
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
            XCTAssertEqual(
                try conversations.fetchFullMessage(id: messageId)?.toolActivity?.piExecution,
                execution
            )
            XCTAssertEqual(
                try conversations.fetchProviderHistory(conversationId: conversationId).last?.toolTranscript.map(\.role),
                ["assistant", "tool"]
            )
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

    func testRunPublishesAndPersistsProviderRotationNotice() async throws {
        let conversations = try makeConversations()
        let conversationId = try conversations.createConversation(
            title: "test",
            model: "gemini-2.5-flash",
            provider: "GEMINI"
        )
        let messageId = try conversations.insertMessage(
            ChatMessage(conversationId: conversationId, role: "model", text: "", createdAtMs: 1)
        )
        let notice = ProviderRotationNotice(
            id: "rotation-1",
            provider: "GEMINI",
            fromModel: "gemini-2.5-flash",
            toModel: "gemini-2.5-flash-lite",
            fromKeyID: "default",
            toKeyID: "slot:secondary",
            reason: .rateLimited,
            createdAtMs: 2
        )
        let snapshots = StreamingSnapshotCollector()
        let stream = AsyncThrowingStream<ProviderStreamEvent, Error> { continuation in
            continuation.yield(.rotation(notice))
            continuation.yield(.completed(ProviderResponse(text: "done")))
            continuation.finish()
        }

        let result = try await ChatStreamSession.run(
            stream: stream,
            conversations: conversations,
            kind: .message(messageId: messageId),
            onStreamEvent: nil,
            onStreamingSnapshot: { snapshots.append($0) }
        )

        XCTAssertEqual(result.toolActivity?.rotationNotices, [notice])
        XCTAssertTrue(snapshots.values.contains { $0.toolActivity?.rotationNotices == [notice] })
        XCTAssertEqual(
            try conversations.fetchFullMessage(id: messageId)?.toolActivity?.rotationNotices,
            [notice]
        )
    }

    func testRunPersistsPiExecutionWithoutToolSteps() async throws {
        let conversations = try makeConversations()
        let conversationId = try conversations.createConversation(title: "test", model: "gpt", provider: "OPENAI")
        let messageId = try conversations.insertMessage(
            ChatMessage(conversationId: conversationId, role: "model", text: "", createdAtMs: 1)
        )
        let execution: JSONValue = .object([
            "format": .string("yamabiko.pi-agent-execution"),
            "state": .object(["messages": .array([])])
        ])
        let stream = AsyncThrowingStream<ProviderStreamEvent, Error> { continuation in
            continuation.yield(
                .completed(
                    ProviderResponse(
                        text: "done",
                        reasoningSummary: nil,
                        raw: nil,
                        usage: nil,
                        piExecution: execution
                    )
                )
            )
            continuation.finish()
        }

        let result = try await ChatStreamSession.run(
            stream: stream,
            conversations: conversations,
            kind: .message(messageId: messageId),
            onStreamEvent: nil,
            onStreamingSnapshot: nil
        )

        XCTAssertEqual(result.toolActivity?.piExecution, execution)
        XCTAssertEqual(try conversations.fetchFullMessage(id: messageId)?.toolActivity?.piExecution, execution)
    }

    func testStreamCheckpointDoesNotMutateObservedMessageUntilCommit() throws {
        let conversations = try makeConversations()
        let conversationId = try conversations.createConversation(
            title: "checkpoint",
            model: "model",
            provider: "OPENAI"
        )
        let messageId = try conversations.insertMessage(
            ChatMessage(conversationId: conversationId, role: "model", text: "", createdAtMs: 1)
        )
        let target = ChatStreamSessionTarget(conversations: conversations, kind: .message(messageId: messageId))

        try target.persistCheckpoint(text: "partial", thinking: "reasoning")

        XCTAssertEqual(try conversations.fetchMessages(conversationId: conversationId).last?.text, "")
        XCTAssertEqual(try conversations.streamCheckpoint(messageId: messageId, variantId: nil)?.text, "partial")

        try target.commitCheckpoint(text: "complete", thinking: "reasoning")

        XCTAssertEqual(try conversations.fetchMessages(conversationId: conversationId).last?.text, "complete")
        XCTAssertEqual(try conversations.fetchFullMessage(id: messageId)?.thinkingStream, "reasoning")
        XCTAssertNil(try conversations.streamCheckpoint(messageId: messageId, variantId: nil))
    }

    func testInterruptedStreamCheckpointRecoversOnColdLaunch() throws {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)
        let conversations = ConversationRepository(dbQueue: dbQueue)
        let conversationId = try conversations.createConversation(
            title: "recovery",
            model: "model",
            provider: "OPENAI"
        )
        let messageId = try conversations.insertMessage(
            ChatMessage(conversationId: conversationId, role: "model", text: "", createdAtMs: 1)
        )
        try conversations.saveStreamCheckpoint(
            messageId: messageId,
            variantId: nil,
            text: "recovered",
            thinking: "saved reasoning"
        )

        try AppDatabase.recoverStreamCheckpoints(in: dbQueue)

        XCTAssertEqual(try conversations.fetchMessages(conversationId: conversationId).last?.text, "recovered")
        XCTAssertEqual(try conversations.fetchFullMessage(id: messageId)?.thinkingStream, "saved reasoning")
        XCTAssertNil(try conversations.streamCheckpoint(messageId: messageId, variantId: nil))
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
