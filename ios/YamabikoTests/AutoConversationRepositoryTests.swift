import XCTest
import GRDB
@testable import YamabikoChat

final class AutoConversationRepositoryTests: XCTestCase {
    func testCreateAutoConversationAndFetch() throws {
        let repository = try makeRepository()
        let conversationID = try repository.createConversation(
            title: "New Chat",
            model: "gemini-2.5-flash",
            provider: "GEMINI"
        )
        let autoConversationID = try repository.createAutoConversation(
            config: AutoConversationConfig(
                title: "自動会話テスト",
                modelA: "gemini-2.5-flash",
                modelB: "deepseek/deepseek-chat",
                providerA: "GEMINI",
                providerB: "OPENROUTER",
                systemPromptA: "A prompt",
                systemPromptB: "B prompt",
                maxTurns: 20,
                endSignal: "[END]"
            ),
            boundChatConversationId: conversationID
        )

        let auto = try repository.fetchAutoConversation(id: autoConversationID)
        XCTAssertEqual(auto?.title, "自動会話テスト")
        XCTAssertEqual(auto?.status, .active)
        XCTAssertEqual(auto?.maxTurns, 20)
        XCTAssertEqual(auto?.boundChatConversationId, conversationID)
    }

    func testInsertAutoConversationMessagesKeepsReasoningAndEndFlag() throws {
        let repository = try makeRepository()
        let conversationID = try repository.createConversation(
            title: "New Chat",
            model: "gemini-2.5-flash",
            provider: "GEMINI"
        )
        let autoConversationID = try repository.createAutoConversation(
            config: AutoConversationConfig(
                title: "自動会話テスト",
                modelA: "model-a",
                modelB: "model-b",
                providerA: "OPENAI",
                providerB: "OPENAI",
                systemPromptA: "A prompt",
                systemPromptB: "B prompt",
                maxTurns: 0,
                endSignal: "[END]"
            ),
            boundChatConversationId: conversationID
        )

        _ = try repository.insertAutoConversationMessage(
            AutoConversationMessage(
                autoConversationId: autoConversationID,
                speakerModel: .user,
                content: "seed",
                turnNumber: 0
            )
        )
        _ = try repository.insertAutoConversationMessage(
            AutoConversationMessage(
                autoConversationId: autoConversationID,
                speakerModel: .a,
                content: "answer",
                reasoning: "thinking trace",
                turnNumber: 1,
                isEndSignal: true
            )
        )

        let messages = try repository.fetchAutoConversationMessages(autoConversationId: autoConversationID)
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].speakerModel, .user)
        XCTAssertEqual(messages[1].speakerModel, .a)
        XCTAssertEqual(messages[1].reasoning, "thinking trace")
        XCTAssertTrue(messages[1].isEndSignal)
    }

    func testUpdateAutoConversationStatus() throws {
        let repository = try makeRepository()
        let conversationID = try repository.createConversation(
            title: "New Chat",
            model: "gemini-2.5-flash",
            provider: "GEMINI"
        )
        let autoConversationID = try repository.createAutoConversation(
            config: AutoConversationConfig(
                title: "自動会話テスト",
                modelA: "model-a",
                modelB: "model-b",
                providerA: "OPENAI",
                providerB: "OPENAI",
                systemPromptA: "A prompt",
                systemPromptB: "B prompt",
                maxTurns: 10,
                endSignal: "[END]"
            ),
            boundChatConversationId: conversationID
        )

        guard var auto = try repository.fetchAutoConversation(id: autoConversationID) else {
            XCTFail("Missing auto conversation")
            return
        }
        auto.status = .paused
        auto.currentTurn = 5
        auto.endReason = AutoConversationEndReason.userStop
        try repository.updateAutoConversation(auto)

        let updated = try repository.fetchAutoConversation(id: autoConversationID)
        XCTAssertEqual(updated?.status, .paused)
        XCTAssertEqual(updated?.currentTurn, 5)
        XCTAssertEqual(updated?.endReason, AutoConversationEndReason.userStop)
    }

    func testFormatAutoConversationDisplayIncludesThinkingFence() {
        let display = formatAutoConversationDisplay(content: "answer", reasoning: "internal reasoning")
        XCTAssertTrue(display.contains("answer"))
        XCTAssertTrue(display.contains("```thinking"))
        XCTAssertTrue(display.contains("internal reasoning"))
    }

    private func makeRepository() throws -> ConversationRepository {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)
        return ConversationRepository(dbQueue: dbQueue)
    }
}
