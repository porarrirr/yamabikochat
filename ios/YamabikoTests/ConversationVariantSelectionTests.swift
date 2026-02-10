import XCTest
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

    private func makeRepository() throws -> ConversationRepository {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)
        return ConversationRepository(dbQueue: dbQueue)
    }
}
