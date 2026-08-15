import XCTest
import Combine
import GRDB
@testable import YamabikoChat

final class ConversationVariantSelectionTests: XCTestCase {
    func testProviderHistoryReplaysToolTranscriptBeforeFinalAnswerAndNextUserMessage() throws {
        let (repository, dbQueue) = try makeRepositoryWithQueue()
        let conversationId = try repository.createConversation(
            title: "Cache",
            model: "model",
            provider: "OPENAI"
        )
        _ = try repository.insertMessage(
            ChatMessage(conversationId: conversationId, role: "user", text: "search")
        )
        let assistantId = try repository.insertMessage(
            ChatMessage(conversationId: conversationId, role: "model", text: "final answer")
        )
        let call = ToolCall(
            id: "call-1",
            name: "web_search",
            argumentsJSON: #"{"query":"large query"}"#,
            providerMetadata: nil
        )
        try insertActivity(
            dbQueue: dbQueue,
            messageId: assistantId,
            step: toolActivityStep(id: "call-1", detail: "large query"),
            transcript: [
                ProviderRequestMessage(role: "assistant", content: "", toolCalls: [call]),
                ProviderRequestMessage(
                    role: "tool",
                    content: "large raw result",
                    toolCallId: "call-1",
                    toolName: "web_search"
                )
            ]
        )
        _ = try repository.insertMessage(
            ChatMessage(conversationId: conversationId, role: "user", text: "thanks")
        )

        let messages = try repository.fetchProviderHistory(conversationId: conversationId)
            .flatMap(\.providerMessages)
        XCTAssertEqual(messages.map(\.role), ["user", "assistant", "tool", "assistant", "user"])
        XCTAssertEqual(messages[1].toolCalls?.first?.argumentsJSON, #"{"query":"large query"}"#)
        XCTAssertEqual(messages[2].content, "large raw result")
        XCTAssertEqual(messages[3].content, "final answer")
        XCTAssertEqual(messages[4].content, "thanks")
    }

    func testFetchProviderHistoryUsesSelectedVariantContent() throws {
        let repository = try makeRepository()
        let conversationId = try repository.createConversation(
            title: "New Chat",
            model: "gpt-4o-mini",
            provider: "OPENAI"
        )

        _ = try repository.insertMessage(
            ChatMessage(
                conversationId: conversationId,
                role: "user",
                text: "question"
            )
        )
        let assistantId = try repository.insertMessage(
            ChatMessage(
                conversationId: conversationId,
                role: "model",
                text: "wrong answer"
            )
        )
        _ = try repository.insertMessageVariant(
            baseMessageId: assistantId,
            text: "fixed answer"
        )

        let history = try repository.fetchProviderHistory(conversationId: conversationId)
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].role, "user")
        XCTAssertEqual(history[1].role, "assistant")
        XCTAssertEqual(history[1].text, "fixed answer")
    }

    func testFetchProviderHistoryIncludesSelectedThinkingContent() throws {
        let repository = try makeRepository()
        let conversationId = try repository.createConversation(
            title: "New Chat",
            model: "deepseek-v4-flash",
            provider: "OPENCODE_GO"
        )

        _ = try repository.insertMessage(
            ChatMessage(
                conversationId: conversationId,
                role: "user",
                text: "question"
            )
        )
        let assistantId = try repository.insertMessage(
            ChatMessage(
                conversationId: conversationId,
                role: "model",
                text: "base answer"
            )
        )
        try repository.saveThinking(messageId: assistantId, stream: "base reasoning")
        let variant = try repository.insertMessageVariant(
            baseMessageId: assistantId,
            text: "variant answer",
            thinkingStream: "variant reasoning"
        )

        try repository.updateMessageSelectedVariantIndex(messageId: assistantId, variantIndex: variant.variantIndex)
        let history = try repository.fetchProviderHistory(conversationId: conversationId)

        XCTAssertEqual(history.last?.text, "variant answer")
        XCTAssertEqual(history.last?.thinkingStream, "variant reasoning")
    }

    func testChangingSelectedVariantIndexUpdatesHistoryAndSummaryPreview() throws {
        let repository = try makeRepository()
        let conversationId = try repository.createConversation(
            title: "New Chat",
            model: "gpt-4o-mini",
            provider: "OPENAI"
        )

        _ = try repository.insertMessage(
            ChatMessage(
                conversationId: conversationId,
                role: "user",
                text: "question"
            )
        )
        let assistantId = try repository.insertMessage(
            ChatMessage(
                conversationId: conversationId,
                role: "model",
                text: "base answer"
            )
        )
        _ = try repository.insertMessageVariant(baseMessageId: assistantId, text: "answer A")
        _ = try repository.insertMessageVariant(baseMessageId: assistantId, text: "answer B")

        try repository.updateMessageSelectedVariantIndex(messageId: assistantId, variantIndex: 1)
        XCTAssertEqual(try repository.fetchProviderHistory(conversationId: conversationId).last?.text, "answer A")
        XCTAssertEqual(try repository.fetchMessageSummaries(conversationId: conversationId).last?.textPreview, "answer A")

        try repository.updateMessageSelectedVariantIndex(messageId: assistantId, variantIndex: 0)
        XCTAssertEqual(try repository.fetchProviderHistory(conversationId: conversationId).last?.text, "base answer")
        XCTAssertEqual(try repository.fetchMessageSummaries(conversationId: conversationId).last?.textPreview, "base answer")
    }

    func testSelectedVariantUsesVariantToolActivity() throws {
        let (repository, dbQueue) = try makeRepositoryWithQueue()
        let conversationId = try repository.createConversation(
            title: "New Chat",
            model: "gpt-4o-mini",
            provider: "OPENAI"
        )
        let assistantId = try repository.insertMessage(
            ChatMessage(
                conversationId: conversationId,
                role: "model",
                text: "base answer"
            )
        )
        let variant = try repository.insertMessageVariant(
            baseMessageId: assistantId,
            text: "variant answer"
        )
        let variantId = try XCTUnwrap(variant.id)

        try insertActivity(
            dbQueue: dbQueue,
            messageId: assistantId,
            step: toolActivityStep(id: "base", detail: "base search"),
            transcript: [ProviderRequestMessage(role: "tool", content: "base result")]
        )
        try insertActivity(
            dbQueue: dbQueue,
            variantId: variantId,
            step: toolActivityStep(id: "variant", detail: "variant search"),
            transcript: [ProviderRequestMessage(role: "tool", content: "variant result")]
        )

        try repository.updateMessageSelectedVariantIndex(messageId: assistantId, variantIndex: variant.variantIndex)
        XCTAssertEqual(
            try repository.fetchFullMessage(id: assistantId)?.displayToolActivity?.steps.first?.detail,
            "variant search"
        )
        XCTAssertEqual(
            try repository.fetchProviderHistory(conversationId: conversationId).last?.toolTranscript.first?.content,
            "variant result"
        )

        try repository.updateMessageSelectedVariantIndex(messageId: assistantId, variantIndex: 0)
        XCTAssertEqual(
            try repository.fetchFullMessage(id: assistantId)?.displayToolActivity?.steps.first?.detail,
            "base search"
        )
        XCTAssertEqual(
            try repository.fetchProviderHistory(conversationId: conversationId).last?.toolTranscript.first?.content,
            "base result"
        )
    }

    func testFetchLatestEmptyConversationSkipsConversationWithDualMessages() throws {
        let repository = try makeRepository()
        let conversationId = try repository.createConversation(
            title: "New Chat",
            model: "gpt-4o-mini",
            provider: "OPENAI"
        )
        _ = try repository.insertDualMessage(
            DualChatMessage(
                conversationId: conversationId,
                userText: "hi",
                modelAText: "A",
                modelBText: "B",
                modelAName: "mA",
                modelBName: "mB",
                providerA: "OPENAI",
                providerB: "OPENAI"
            )
        )

        let empty = try repository.fetchLatestEmptyConversation(title: "New Chat", projectId: nil)
        XCTAssertNil(empty)
    }

    func testObserveConversationListHidesEmptyConversations() throws {
        let repository = try makeRepository()
        let conversationId = try repository.createConversation(
            title: "New Chat",
            model: "gpt-4o-mini",
            provider: "OPENAI"
        )

        let expectation = expectation(description: "conversation list emits without empty conversation")
        var cancellable: AnyCancellable?
        cancellable = repository.observeConversationList()
            .sink { entries in
                XCTAssertFalse(entries.contains(where: { $0.id == conversationId }))
                expectation.fulfill()
                cancellable?.cancel()
            }

        wait(for: [expectation], timeout: 2.0)
    }

    func testInsertDualMessageUpdatesConversationTimestamp() throws {
        let repository = try makeRepository()
        let conversationId = try repository.createConversation(
            title: "New Chat",
            model: "gpt-4o-mini",
            provider: "OPENAI"
        )

        guard let before = try repository.fetchConversation(id: conversationId)?.updatedAtMs else {
            XCTFail("Missing conversation")
            return
        }
        Thread.sleep(forTimeInterval: 0.01)
        _ = try repository.insertDualMessage(
            DualChatMessage(
                conversationId: conversationId,
                userText: "test",
                modelAText: "A",
                modelBText: "B",
                modelAName: "mA",
                modelBName: "mB",
                providerA: "OPENAI",
                providerB: "OPENAI"
            )
        )

        guard let after = try repository.fetchConversation(id: conversationId)?.updatedAtMs else {
            XCTFail("Missing conversation")
            return
        }
        XCTAssertGreaterThan(after, before)
    }

    func testSearchConversationsIncludesDualMessageText() throws {
        let repository = try makeRepository()
        let conversationId = try repository.createConversation(
            title: "New Chat",
            model: "gpt-4o-mini",
            provider: "OPENAI"
        )
        _ = try repository.insertDualMessage(
            DualChatMessage(
                conversationId: conversationId,
                userText: "question",
                modelAText: "dual searchable token",
                modelBText: "alternate",
                modelAName: "mA",
                modelBName: "mB",
                providerA: "OPENAI",
                providerB: "OPENAI"
            )
        )

        let results = try repository.searchConversations(query: "searchable token")
        XCTAssertTrue(results.contains(where: { $0.id == conversationId }))
    }

    func testSearchConversationsExcludesEmptyTitleOnlyMatches() throws {
        let repository = try makeRepository()
        let conversationId = try repository.createConversation(
            title: "New Chat",
            model: "gpt-4o-mini",
            provider: "OPENAI"
        )

        let results = try repository.searchConversations(query: "New Chat")

        XCTAssertFalse(results.contains(where: { $0.id == conversationId }))
    }

    func testObserveConversationListUsesDualPreviewWhenNoChatMessages() throws {
        let repository = try makeRepository()
        let conversationId = try repository.createConversation(
            title: "New Chat",
            model: "gpt-4o-mini",
            provider: "OPENAI"
        )
        _ = try repository.insertDualMessage(
            DualChatMessage(
                conversationId: conversationId,
                userText: "question",
                modelAText: "dual preview text",
                modelBText: "alternate",
                modelAName: "mA",
                modelBName: "mB",
                providerA: "OPENAI",
                providerB: "OPENAI"
            )
        )

        let expectation = expectation(description: "conversation list emits dual preview")
        var cancellable: AnyCancellable?
        cancellable = repository.observeConversationList()
            .sink { entries in
                guard let entry = entries.first(where: { $0.id == conversationId }) else { return }
                XCTAssertEqual(entry.lastMessagePreview, "dual preview text")
                expectation.fulfill()
                cancellable?.cancel()
            }

        wait(for: [expectation], timeout: 2.0)
    }

    func testObserveConversationListUsesLatestPreviewAcrossChatAndDual() throws {
        let repository = try makeRepository()
        let conversationId = try repository.createConversation(
            title: "New Chat",
            model: "gpt-4o-mini",
            provider: "OPENAI"
        )
        _ = try repository.insertMessage(
            ChatMessage(
                conversationId: conversationId,
                role: "model",
                text: "older chat text"
            )
        )
        Thread.sleep(forTimeInterval: 0.01)
        _ = try repository.insertDualMessage(
            DualChatMessage(
                conversationId: conversationId,
                userText: "question",
                modelAText: "newest dual preview",
                modelBText: "alternate",
                modelAName: "mA",
                modelBName: "mB",
                providerA: "OPENAI",
                providerB: "OPENAI"
            )
        )

        let expectation = expectation(description: "conversation list emits latest preview")
        var cancellable: AnyCancellable?
        cancellable = repository.observeConversationList()
            .sink { entries in
                guard let entry = entries.first(where: { $0.id == conversationId }) else { return }
                XCTAssertEqual(entry.lastMessagePreview, "newest dual preview")
                expectation.fulfill()
                cancellable?.cancel()
            }

        wait(for: [expectation], timeout: 2.0)
    }

    private func makeRepository() throws -> ConversationRepository {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)
        return ConversationRepository(dbQueue: dbQueue)
    }

    private func makeRepositoryWithQueue() throws -> (ConversationRepository, DatabaseQueue) {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)
        return (ConversationRepository(dbQueue: dbQueue), dbQueue)
    }

    /// Inserts a tool activity row directly. `saveToolActivities` was removed with the
    /// pre-Pi streaming pipeline; the read-side transcript replay still serves legacy rows.
    private func insertActivity(
        dbQueue: DatabaseQueue,
        messageId: Int64? = nil,
        variantId: Int64? = nil,
        step: ToolActivityStep,
        transcript: [ProviderRequestMessage]
    ) throws {
        let stepsData = try JSONEncoder().encode([step])
        var activity = ChatMessageToolActivity(
            messageId: messageId,
            variantId: variantId,
            stepsJSON: String(data: stepsData, encoding: .utf8) ?? "[]",
            providerTranscriptJSON: {
                guard let data = try? JSONEncoder().encode(transcript) else { return nil }
                return String(data: data, encoding: .utf8)
            }()
        )
        try dbQueue.write { db in
            try activity.insert(db)
        }
    }

    private func toolActivityStep(id: String, detail: String) -> ToolActivityStep {
        ToolActivityStep(
            id: id,
            round: 1,
            toolName: WebSearchTool.name,
            title: "Web",
            detail: detail,
            status: .completed,
            resultCount: 1,
            sources: [ToolSource(title: detail, url: "https://example.com/\(id)")],
            errorMessage: nil,
            createdAtMs: 1
        )
    }
}
