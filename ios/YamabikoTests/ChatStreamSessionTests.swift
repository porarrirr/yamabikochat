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

    func testRunReplacesEarlierTextWithLatestProviderSnapshot() async throws {
        let conversations = try makeConversations()
        let conversationId = try conversations.createConversation(
            title: "snapshot",
            model: AppleIntelligenceModelCatalog.pccModel,
            provider: "APPLE_INTELLIGENCE"
        )
        let messageId = try conversations.insertMessage(
            ChatMessage(conversationId: conversationId, role: "model", text: "", createdAtMs: 1)
        )
        let snapshots = StreamingSnapshotCollector()
        let stream = AsyncThrowingStream<ProviderStreamEvent, Error> { continuation in
            continuation.yield(.textSnapshot("ABC"))
            continuation.yield(.textSnapshot("ABD"))
            continuation.yield(.textSnapshot("ABD final"))
            continuation.finish()
        }

        let session = try await ChatStreamSession.run(
            stream: stream,
            conversations: conversations,
            kind: .message(messageId: messageId),
            onStreamEvent: nil,
            onStreamingSnapshot: { snapshots.append($0) }
        )

        XCTAssertEqual(session.text, "ABD final")
        XCTAssertEqual(snapshots.values.last?.text, "ABD final")
        let messages = try conversations.fetchMessages(conversationId: conversationId)
        XCTAssertEqual(messages.last?.text, "ABD final")
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

    func testRunAppendsErrorAfterPartialStreamOnFailure() async throws {
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
            continuation.yield(.reasoningDelta("thinking"))
            continuation.yield(.textDelta("partial"))
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
                "partial\n\n" + UserFacingErrorFormatter.placeholder(for: streamError)
            )
            XCTAssertEqual(try conversations.fetchFullMessage(id: messageId)?.thinkingStream, "thinking")
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
            "version": .number(4),
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
            "version": .number(4),
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

    func testCancellationCommitsPartialMessageOrVariantAndStopsRunningTools() async throws {
        for useVariant in [false, true] {
            let conversations = try makeConversations()
            let conversationID = try conversations.createConversation(title: "Cancellation", model: "model", provider: "OPENAI")
            let messageID = try conversations.insertMessage(
                ChatMessage(conversationId: conversationID, role: "model", text: useVariant ? "original answer" : "")
            )
            let variantID = useVariant
                ? try XCTUnwrap(conversations.insertMessageVariant(baseMessageId: messageID, text: "").id)
                : nil
            let kind: ChatStreamPersistenceKind = variantID.map {
                .variant(variantId: $0, snapshotMessageId: messageID)
            } ?? .message(messageId: messageID)
            let (stream, continuation) = AsyncThrowingStream<ProviderStreamEvent, Error>.makeStream()
            defer { continuation.finish() }
            let toolStarted = expectation(description: "Partial answer and running tool are visible")
            let snapshots = StreamingSnapshotCollector()
            let task = Task {
                try await ChatStreamSession.run(
                    stream: stream,
                    conversations: conversations,
                    kind: kind,
                    onStreamEvent: nil,
                    onStreamingSnapshot: { snapshot in
                        snapshots.append(snapshot)
                        if !snapshot.isFinal, snapshot.toolActivity?.steps.first?.status == .running {
                            toolStarted.fulfill()
                        }
                    }
                )
            }
            continuation.yield(.textDelta("partial answer"))
            continuation.yield(.reasoningDelta("saved reasoning"))
            continuation.yield(.toolActivity(ToolActivityEvent(
                phase: .started,
                call: ToolCall(id: "pending-tool", name: WebSearchTool.name, argumentsJSON: #"{"query":"test"}"#),
                result: nil,
                createdAtMs: 1
            )))
            await fulfillment(of: [toolStarted], timeout: 2)

            task.cancel()
            do {
                _ = try await task.value
                XCTFail("User cancellation must not report a successful response")
            } catch is CancellationError {} catch {
                XCTFail("Unexpected failure: \(error)")
            }

            let saved = try XCTUnwrap(conversations.fetchFullMessage(id: messageID))
            let text = useVariant ? try XCTUnwrap(saved.variants.first).text : saved.message.text
            let thinking = useVariant ? saved.variants.first?.thinkingStream : saved.thinkingStream
            let activity = variantID.map { saved.variantToolActivities[$0] } ?? saved.toolActivity
            XCTAssertTrue(text.hasPrefix("partial answer"))
            XCTAssertEqual(thinking, "saved reasoning")
            XCTAssertEqual(activity?.steps.first?.status, .failed)
            if useVariant { XCTAssertEqual(saved.message.text, "original answer") }
            XCTAssertNil(try conversations.streamCheckpoint(messageId: useVariant ? nil : messageID, variantId: variantID))
            XCTAssertEqual(snapshots.values.last?.isFinal, true)
            XCTAssertEqual(snapshots.values.last?.targetId, messageID)
            XCTAssertEqual(snapshots.values.last?.text, text)
        }
    }

    func testInterruptedMessageAndVariantCheckpointsRecoverAfterDatabaseReopens() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("recovery.sqlite").path
        let dbQueue = try DatabaseQueue(path: path)
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
        let originalID = try conversations.insertMessage(
            ChatMessage(conversationId: conversationId, role: "model", text: "original answer", createdAtMs: 2)
        )
        let variantID = try XCTUnwrap(conversations.insertMessageVariant(baseMessageId: originalID, text: "").id)
        try conversations.saveStreamCheckpoint(
            messageId: nil, variantId: variantID, text: "recovered variant", thinking: "variant reasoning"
        )
        try dbQueue.close()

        let reopened = try DatabaseQueue(path: path)
        defer { try? reopened.close() }
        try AppDatabase.migrator.migrate(reopened)
        try AppDatabase.recoverStreamCheckpoints(in: reopened)
        let recovered = ConversationRepository(dbQueue: reopened)

        XCTAssertEqual(try recovered.fetchFullMessage(id: messageId)?.message.text, "recovered")
        XCTAssertEqual(try recovered.fetchFullMessage(id: messageId)?.thinkingStream, "saved reasoning")
        let original = try XCTUnwrap(recovered.fetchFullMessage(id: originalID))
        XCTAssertEqual(original.message.text, "original answer")
        XCTAssertEqual(original.variants.first?.text, "recovered variant")
        XCTAssertEqual(original.variants.first?.thinkingStream, "variant reasoning")
        XCTAssertNil(try recovered.streamCheckpoint(messageId: messageId, variantId: nil))
        XCTAssertNil(try recovered.streamCheckpoint(messageId: nil, variantId: variantID))
        try AppDatabase.recoverStreamCheckpoints(in: reopened)
        XCTAssertEqual(try recovered.fetchFullMessage(id: originalID), original)
    }

    func testRecoveryWriteFailuresAreLoggedWithoutReplacingStreamError() async throws {
        struct ExecutionFailure: Error {}
        for isVariant in [false, true] {
            for partialText in ["", "partial"] {
                let dbQueue = try DatabaseQueue()
                try AppDatabase.migrator.migrate(dbQueue)
                let conversations = ConversationRepository(dbQueue: dbQueue)
                let conversationID = try conversations.createConversation(title: "Recovery", model: "test", provider: "OPENAI")
                let messageID = try conversations.insertMessage(
                    ChatMessage(conversationId: conversationID, role: "model", text: "", createdAtMs: 1)
                )
                let variantID = isVariant
                    ? try XCTUnwrap(conversations.insertMessageVariant(baseMessageId: messageID, text: "").id) : nil
                try await dbQueue.write { db in
                    // Checkpoint writes remain available until the execution fails.
                    for table in ["chat_messages", "chat_message_variants"] {
                        try db.execute(sql: "CREATE TRIGGER fail_\(table) BEFORE UPDATE ON \(table) BEGIN SELECT RAISE(ABORT, 'recovery write rejected'); END")
                    }
                    try db.execute(sql: "CREATE TRIGGER fail_checkpoint BEFORE DELETE ON chat_stream_checkpoints BEGIN SELECT RAISE(ABORT, 'recovery delete rejected'); END")
                    try db.execute(sql: "CREATE TRIGGER fail_activity BEFORE INSERT ON \(ChatMessageToolActivity.databaseTableName) BEGIN SELECT RAISE(ABORT, 'recovery activity rejected'); END")
                }
                // A saved checkpoint ensures the DELETE trigger fires on empty output too.
                try conversations.saveStreamCheckpoint(messageId: isVariant ? nil : messageID, variantId: variantID, text: "", thinking: "")
                let stream = AsyncThrowingStream<ProviderStreamEvent, Error> { continuation in
                    continuation.yield(.toolActivity(ToolActivityEvent(
                        phase: .started, call: ToolCall(id: "test", name: "test", argumentsJSON: "{}"),
                        result: nil, createdAtMs: 1
                    )))
                    if !partialText.isEmpty { continuation.yield(.textDelta(partialText)) }
                    continuation.finish(throwing: ExecutionFailure())
                }
                // read() combines app and runtime files, so its previous length is not an append offset.
                let logMarker = "Recovery test start: \(UUID().uuidString)"
                DiagnosticsLogger.log(logMarker)
                do {
                    _ = try await ChatStreamSession.run(
                        stream: stream, conversations: conversations,
                        kind: variantID.map { .variant(variantId: $0, snapshotMessageId: messageID) } ?? .message(messageId: messageID),
                        onStreamEvent: nil, onStreamingSnapshot: nil
                    )
                    XCTFail("Expected execution failure")
                } catch is ExecutionFailure {
                    let allLogs = DiagnosticsLogger.read()
                    let markerRange = try XCTUnwrap(allLogs.range(of: logMarker))
                    let logs = String(allLogs[markerRange.upperBound...])
                    let identity = variantID.map { "variantId=\($0)" } ?? "messageId=\(messageID)"
                    XCTAssertTrue(logs.contains(identity))
                    XCTAssertTrue(logs.contains("operation=persistToolActivity"))
                    if partialText.isEmpty {
                        XCTAssertTrue(logs.contains("operation=writeErrorPlaceholder"))
                        XCTAssertTrue(logs.contains("operation=discardCheckpoint"))
                    } else {
                        XCTAssertTrue(logs.contains("operation=commitCheckpoint"))
                    }
                }
            }
        }
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
