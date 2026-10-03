import XCTest
import GRDB
@testable import YamabikoChat

final class SiriConversationTests: XCTestCase {
    private func repository() throws -> ConversationRepository {
        let db = try DatabaseQueue()
        try AppDatabase.migrator.migrate(db)
        return ConversationRepository(dbQueue: db)
    }

    func testSearchMatchesTitleAndEarlierMessageLiterallyAndExcludesSecret() throws {
        let repository = try repository()
        let titleID = try repository.createConversation(title: "Budget 100%_", model: "model", provider: "TEST")
        let bodyID = try repository.createConversation(title: "Travel", model: "model", provider: "TEST")
        _ = try repository.insertMessage(ChatMessage(conversationId: bodyID, role: "user", text: "Budget 100%_"))
        _ = try repository.insertMessage(ChatMessage(conversationId: bodyID, role: "model", text: "A later reply"))
        let secretID = try repository.createConversation(title: "Budget 100%_", model: "model", provider: "TEST", isSecret: true)
        _ = try repository.insertMessage(ChatMessage(conversationId: secretID, role: "user", text: "Budget 100%_"))
        let unrelatedID = try repository.createConversation(title: "Anything", model: "model", provider: "TEST")

        XCTAssertEqual(Set(try repository.siriConversations(matching: " BUDGET 100%_ ").compactMap(\.id)), [titleID, bodyID])
        XCTAssertFalse(try repository.siriConversations().contains { $0.id == secretID })
        XCTAssertEqual(Set(try repository.siriConversations(matching: "%_").compactMap(\.id)), [titleID, bodyID])
        XCTAssertEqual(try repository.siriConversations(ids: [unrelatedID]).first?.id, unrelatedID)
        XCTAssertTrue(try repository.siriConversations(ids: []).isEmpty)
    }

    func testResolutionRechecksDeletedAndSecretEntities() throws {
        let repository = try repository()
        let id = try repository.createConversation(title: "Visible", model: "model", provider: "TEST")
        XCTAssertEqual(try SiriConversationService.resolve(id: id, repository: repository).title, "Visible")
        _ = try repository.setSecretModeIfEmpty(id: id, enabled: true)
        XCTAssertThrowsError(try SiriConversationService.resolve(id: id, repository: repository))
        XCTAssertNil(ConversationEntity(try XCTUnwrap(repository.fetchConversation(id: id))))
        try repository.deleteConversation(id: id)
        XCTAssertThrowsError(try SiriConversationService.resolve(id: id, repository: repository))
    }

    func testSuggestionsOrderAndLimit() throws {
        let repository = try repository()
        let older = try repository.upsertConversation(Conversation(title: "Old", model: "model", updatedAtMs: 1))
        let newer = try repository.upsertConversation(Conversation(title: "New", model: "model", updatedAtMs: 10))
        XCTAssertEqual(try repository.siriConversations(limit: 1).compactMap(\.id), [newer])
        XCTAssertEqual(try repository.siriConversations(ids: [older]).compactMap(\.id), [older])
    }

    func testIndexRemovesDeletedAndSecretConversationsAndUpdatesRenames() {
        let first = ConversationListEntry(id: 1, title: "Old", updatedAtMs: 1, isSecret: false)
        let second = ConversationListEntry(id: 2, title: "Private", updatedAtMs: 1, isSecret: false)
        let deleted = ConversationListEntry(id: 3, title: "Deleted", updatedAtMs: 1, isSecret: false)
        var renamed = first
        renamed.title = "Renamed"
        var secret = second
        secret.isSecret = true
        let plan = ConversationIndexPlan(previous: [1: first, 2: second, 3: deleted], entries: [renamed, secret])
        XCTAssertEqual(Set(plan.removedIDs), [2, 3])
        XCTAssertEqual(plan.changed.map(\.title), ["Renamed"])
        XCTAssertEqual(Set(plan.current.keys), [1])
        let unchanged = ConversationIndexPlan(previous: plan.current, entries: [renamed, secret])
        XCTAssertTrue(unchanged.changed.isEmpty)
        XCTAssertTrue(unchanged.removedIDs.isEmpty)
    }

    func testConversationLinksAreStrictlyParsed() {
        XCTAssertEqual(SiriConversationService.conversationID(from: URL(string: "yamabikochat://conversation/42")!), 42)
        for link in ["https://conversation/42", "yamabikochat://import-share/42", "yamabikochat://conversation/-1", "yamabikochat://conversation/0", "yamabikochat://conversation/42/extra", "yamabikochat://conversation/42?secret=1"] {
            XCTAssertNil(SiriConversationService.conversationID(from: URL(string: link)!))
        }
    }

    @MainActor
    func testNavigationSurvivesColdLaunchAndIsConsumedOnce() {
        let navigation = SiriNavigation()
        navigation.request(.conversation(42))
        XCTAssertEqual(navigation.consume(), .conversation(42))
        XCTAssertNil(navigation.consume())
        navigation.request(.search("travel"))
        XCTAssertEqual(navigation.consume(), .search("travel"))
    }
}
