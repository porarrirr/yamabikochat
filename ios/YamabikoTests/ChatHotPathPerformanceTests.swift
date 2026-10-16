import GRDB
import XCTest
@testable import YamabikoChat

/// Fixed workloads for before/after comparisons; no network or model execution.
final class ChatHotPathPerformanceTests: XCTestCase {
    func testMarkdownDocumentPerformance() {
        let source = String(repeating: """
        ## 日本語の回答

        本文には **強調** と `code` と通常の説明を含みます。読みやすい文章を表示します。

        - First item with **emphasis** and more text
        - Second item with `inline code`

        詳細は https://www.example.com/docs?q=chat を参照してください。


        """, count: 100)
        measure {
            XCTAssertEqual(NativeMarkdownParser.parse(source).count, 400)
        }
    }

    func testMessageSummaryHistoryPerformance() throws {
        let (repository, id) = try historyFixture()
        measure {
            do {
                let summaries = try repository.fetchMessageSummaries(conversationId: id)
                XCTAssertEqual(summaries.count, 500)
            } catch { XCTFail("History read failed: \(error)") }
        }
    }

    func testProviderHistoryPerformance() throws {
        let (repository, id) = try historyFixture()
        measure {
            do {
                let history = try repository.fetchProviderHistory(conversationId: id)
                XCTAssertEqual(history.count, 500)
            } catch { XCTFail("History read failed: \(error)") }
        }
    }

    func testFindingEmptyConversationPerformance() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue)
        let repository = ConversationRepository(dbQueue: queue)
        let emptyID = try repository.createConversation(title: "New Chat", model: "test", provider: "TEST")
        try queue.write { db in
            try db.execute(sql: "UPDATE conversations SET updatedAtMs = 0 WHERE id = ?", arguments: [emptyID])
            for index in 1...500 {
                var conversation = Conversation(title: "New Chat", model: "test", apiProvider: "TEST")
                conversation.updatedAtMs = Int64(index)
                try conversation.insert(db)
                var message = ChatMessage(conversationId: conversation.id!, role: "user", text: "Hello")
                try message.insert(db)
            }
        }
        measure {
            do {
                let conversation = try repository.fetchLatestEmptyConversation(title: "New Chat")
                XCTAssertEqual(conversation?.id, emptyID)
            } catch { XCTFail("Conversation lookup failed: \(error)") }
        }
    }

    @MainActor
    func testLongResponseStreamingPerformance() {
        let prefix = String(repeating: "## 見出し\n\n日本語の **段落** と `code`。\n\n", count: 100)
        let frames = (1...60).map { prefix + String(repeating: "追記。", count: $0) }
        measure {
            let parser = NativeMarkdownIncrementalParser()
            for source in frames {
                XCTAssertFalse(parser.streamingBlocks(for: source).isEmpty)
            }
        }
    }

    private func historyFixture() throws -> (ConversationRepository, Int64) {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue)
        let repository = ConversationRepository(dbQueue: queue)
        let id = try repository.createConversation(title: "Performance fixture", model: "test", provider: "TEST")
        // One transaction keeps fixture setup out of the measured work.
        try queue.write { db in
            for index in 0..<500 {
                var message = ChatMessage(
                    conversationId: id,
                    role: index.isMultiple(of: 2) ? "user" : "model",
                    text: String(repeating: "日本語の履歴と **Markdown**。 ", count: 20),
                    createdAtMs: Int64(index)
                )
                try message.insert(db)
            }
        }
        return (repository, id)
    }
}
