import Combine
import GRDB
import XCTest
@testable import YamabikoChat

final class ConversationReadPolicyTests: XCTestCase {
    func testBatchReadsResolveSecretStatusOnceAndPreserveSelectedContent() throws {
        for secret in [false, true] {
            let queue = try DatabaseQueue()
            try AppDatabase.migrator.migrate(queue)
            let repository = ConversationRepository(dbQueue: queue)
            let id = try repository.createConversation(title: "History", model: "test", provider: "TEST", isSecret: secret)
            defer { SecretConversationVault.shared.destroy(conversationID: id) }
            for index in 0..<20 {
                let messageID = try repository.insertMessage(ChatMessage(
                    conversationId: id, role: "model", text: "本文 \(index)", createdAtMs: Int64(index)
                ))
                try repository.saveThinking(messageId: messageID, stream: "思考 \(index)")
                _ = try repository.insertMessageVariant(
                    baseMessageId: messageID, text: "別案 \(index)", thinkingStream: "別の思考 \(index)"
                )
                _ = try repository.insertDualMessage(DualChatMessage(
                    conversationId: id, userText: "質問 \(index)", modelAText: "A", modelBText: "B",
                    modelAName: "a", modelBName: "b", providerA: "TEST", providerB: "TEST"
                ))
            }
            let reads: [() throws -> Void] = [
                {
                    XCTAssertEqual(try repository.fetchMessages(conversationId: id).map(\.text), (0..<20).map { "本文 \($0)" })
                },
                {
                    XCTAssertEqual(try repository.fetchMessageSummaries(conversationId: id).map(\.textPreview), (0..<20).map { "別案 \($0)" })
                },
                {
                    let history = try repository.fetchProviderHistory(conversationId: id)
                    XCTAssertEqual(history.map(\.text), (0..<20).map { "別案 \($0)" })
                    XCTAssertEqual(history.map(\.thinkingStream), (0..<20).map { "別の思考 \($0)" })
                },
                {
                    XCTAssertEqual(try repository.fetchDualMessages(conversationId: id).count, 20)
                },
                {
                    let received = self.expectation(description: "Full messages")
                    let token = repository.observeFullMessages(conversationId: id).sink { messages in
                        XCTAssertEqual(messages.count, 20)
                        XCTAssertEqual(messages.first?.displayText, "別案 0")
                        XCTAssertEqual(messages.first?.thinkingStream, "思考 0")
                        received.fulfill()
                    }
                    self.wait(for: [received], timeout: 3)
                    withExtendedLifetime(token) {}
                },
                {
                    let received = self.expectation(description: "Dual messages")
                    let token = repository.observeDualMessages(conversationId: id).sink { messages in
                        XCTAssertEqual(messages.count, 20)
                        XCTAssertTrue(messages.allSatisfy { $0.modelAText == "A" && $0.modelBText == "B" })
                        received.fulfill()
                    }
                    self.wait(for: [received], timeout: 3)
                    withExtendedLifetime(token) {}
                }
            ]
            for read in reads {
                let recorder = SQLRecorder()
                try queue.write { db in
                    db.trace { event in
                        if case let .statement(statement) = event { recorder.record(statement.sql) }
                    }
                }
                try read()
                try queue.write { $0.trace(nil) }
                XCTAssertEqual(recorder.statements.filter { $0.hasPrefix("SELECT isSecret FROM conversations") }.count, 1)
            }
        }
    }

    func testReadAfterEnablingSecretModeDoesNotReuseEarlierPlaintextPolicy() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue)
        let repository = ConversationRepository(dbQueue: queue)
        let id = try repository.createConversation(title: "New Chat", model: "test", provider: "TEST")
        defer { SecretConversationVault.shared.destroy(conversationID: id) }
        XCTAssertTrue(try repository.fetchMessages(conversationId: id).isEmpty)
        _ = try repository.setSecretModeIfEmpty(id: id, enabled: true)
        _ = try repository.insertMessage(ChatMessage(conversationId: id, role: "user", text: "秘密"))
        XCTAssertEqual(try repository.fetchMessages(conversationId: id).first?.text, "秘密")
        XCTAssertEqual(try repository.fetchMessageSummaries(conversationId: id).first?.textPreview, "秘密")
        XCTAssertEqual(try repository.fetchProviderHistory(conversationId: id).first?.text, "秘密")
    }

    func testEmptyConversationLookupFiltersProjectsPendingDraftsAndNonemptyChats() throws {
        let queue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(queue)
        let repository = ConversationRepository(dbQueue: queue)
        let project = try repository.createProject(title: "Project", instructions: nil)
        let expected = try repository.createConversation(title: "New Chat", model: "test", provider: "TEST")
        let inProject = try repository.createConversation(title: "New Chat", model: "test", provider: "TEST", projectId: project)
        _ = try repository.createConversation(title: "New Chat", model: "test", provider: "TEST", pendingInitialMessage: "")
        let nonempty = try repository.createConversation(title: "New Chat", model: "test", provider: "TEST")
        _ = try repository.insertMessage(ChatMessage(conversationId: nonempty, role: "user", text: "Hi"))
        XCTAssertEqual(try repository.fetchLatestEmptyConversation(title: "New Chat")?.id, expected)
        XCTAssertEqual(try repository.fetchLatestEmptyConversation(title: "New Chat", projectId: project)?.id, inProject)
        XCTAssertNil(try repository.fetchLatestEmptyConversation(title: "Missing"))
    }
}

private final class SQLRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []
    var statements: [String] { lock.withLock { recorded } }
    func record(_ sql: String) { lock.withLock { recorded.append(sql) } }
}
