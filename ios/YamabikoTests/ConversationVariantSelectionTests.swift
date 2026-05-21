import XCTest
import Combine
import GRDB
@testable import YamabikoChat

final class ConversationVariantSelectionTests: XCTestCase {
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
}
