import Foundation
import Combine
import GRDB

final class ConversationRepository {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func createConversation(
        title: String,
        model: String,
        provider: String,
        systemPrompt: String? = nil,
        isSecret: Bool = false
    ) throws -> Int64 {
        try dbQueue.write { db in
            var conversation = Conversation(
                title: title,
                systemPrompt: systemPrompt,
                model: model,
                apiProvider: provider,
                isSecret: isSecret
            )
            try conversation.insert(db)
            return conversation.id ?? 0
        }
    }

    func upsertConversation(_ conversation: Conversation) throws -> Int64 {
        try dbQueue.write { db in
            var updated = conversation
            updated.updatedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
            try updated.save(db)
            return updated.id ?? 0
        }
    }

    func deleteConversation(id: Int64) throws {
        try dbQueue.write { db in
            _ = try Conversation.deleteOne(db, key: id)
        }
    }

    func fetchConversation(id: Int64) throws -> Conversation? {
        try dbQueue.read { db in
            try Conversation.fetchOne(db, key: id)
        }
    }

    func getOrCreateCodexSessionId(conversationId: Int64) throws -> String {
        try dbQueue.write { db in
            guard var conversation = try Conversation.fetchOne(db, key: conversationId) else {
                throw ProviderClientError.parseFailure("Conversation not found")
            }
            let existing = conversation.codexSessionId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !existing.isEmpty { return existing }

            let created = UUID().uuidString
            conversation.codexSessionId = created
            try conversation.update(db)
            return created
        }
    }

    func fetchLatestEmptyConversation(title: String) throws -> Conversation? {
        try dbQueue.read { db in
            try Conversation
                .filter(Column("title") == title)
                .order(Column("updatedAtMs").desc)
                .fetchAll(db)
                .first { conversation in
                    let messageCount = try? Int.fetchOne(
                        db,
                        sql: "SELECT COUNT(*) FROM chat_messages WHERE conversationId = ?",
                        arguments: [conversation.id ?? 0]
                    )
                    return (messageCount ?? 0) == 0
                }
        }
    }

    func observeConversationList() -> AnyPublisher<[ConversationListEntry], Never> {
        ValueObservation.tracking { db -> [ConversationListEntry] in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT c.id, c.title, c.updatedAtMs, c.isSecret,
                       (SELECT text FROM chat_messages m WHERE m.conversationId = c.id ORDER BY m.createdAtMs DESC LIMIT 1) AS lastMessagePreview
                FROM conversations c
                ORDER BY c.updatedAtMs DESC
                """
            )

            return rows.compactMap { row in
                guard let id: Int64 = row["id"] else { return nil }
                return ConversationListEntry(
                    id: id,
                    title: row["title"] ?? "New Chat",
                    updatedAtMs: row["updatedAtMs"] ?? 0,
                    lastMessagePreview: row["lastMessagePreview"],
                    isSecret: row["isSecret"] ?? false
                )
            }
        }
        .publisher(in: dbQueue)
        .replaceError(with: [])
        .eraseToAnyPublisher()
    }

    func observeMessages(conversationId: Int64) -> AnyPublisher<[ChatMessageSummary], Never> {
        ValueObservation.tracking { db -> [ChatMessageSummary] in
            try self.fetchMessageSummaries(db: db, conversationId: conversationId)
        }
        .publisher(in: dbQueue)
        .replaceError(with: [])
        .eraseToAnyPublisher()
    }

    func observeFullMessages(conversationId: Int64) -> AnyPublisher<[FullChatMessage], Never> {
        ValueObservation.tracking { db -> [FullChatMessage] in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT m.id, m.conversationId, m.role, m.text, m.attachmentsJSON, m.createdAtMs,
                       t.thinkingStream
                FROM chat_messages m
                LEFT JOIN chat_message_thinking t ON t.messageId = m.id
                WHERE m.conversationId = ?
                ORDER BY m.createdAtMs ASC
                """,
                arguments: [conversationId]
            )

            return rows.compactMap { row in
                guard let id: Int64 = row["id"] else { return nil }
                let messageConversationID: Int64 = row["conversationId"] ?? conversationId
                let role: String = row["role"] ?? "assistant"
                let text: String = row["text"] ?? ""
                let attachmentsJSON: String = row["attachmentsJSON"] ?? "[]"
                let createdAtMs: Int64 = row["createdAtMs"] ?? 0
                let message = ChatMessage(
                    id: id,
                    conversationId: messageConversationID,
                    role: role,
                    text: text,
                    attachmentsJSON: attachmentsJSON,
                    createdAtMs: createdAtMs
                )
                return FullChatMessage(
                    id: id,
                    message: message,
                    thinkingStream: row["thinkingStream"]
                )
            }
        }
        .publisher(in: dbQueue)
        .replaceError(with: [])
        .eraseToAnyPublisher()
    }

    func fetchMessageSummaries(conversationId: Int64) throws -> [ChatMessageSummary] {
        try dbQueue.read { db in
            try fetchMessageSummaries(db: db, conversationId: conversationId)
        }
    }

    func isConversationEmpty(conversationId: Int64) throws -> Bool {
        try dbQueue.read { db in
            let chatCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM chat_messages WHERE conversationId = ?",
                arguments: [conversationId]
            ) ?? 0
            if chatCount > 0 { return false }

            let dualCount = try Int.fetchOne(
                db,
                sql: "SELECT COUNT(*) FROM dual_chat_messages WHERE conversationId = ?",
                arguments: [conversationId]
            ) ?? 0
            return dualCount == 0
        }
    }

    func fetchMessages(conversationId: Int64) throws -> [ChatMessage] {
        try dbQueue.read { db in
            try ChatMessage
                .filter(Column("conversationId") == conversationId)
                .order(Column("createdAtMs").asc)
                .fetchAll(db)
        }
    }

    func fetchMessage(id: Int64) throws -> ChatMessage? {
        try dbQueue.read { db in
            try ChatMessage.fetchOne(db, key: id)
        }
    }

    func fetchFullMessage(id: Int64) throws -> FullChatMessage? {
        try dbQueue.read { db in
            guard let message = try ChatMessage.fetchOne(db, key: id), let messageId = message.id else { return nil }
            let thinking = try ChatMessageThinking
                .filter(Column("messageId") == messageId)
                .fetchOne(db)?.thinkingStream
            return FullChatMessage(id: messageId, message: message, thinkingStream: thinking)
        }
    }

    func insertMessage(_ message: ChatMessage) throws -> Int64 {
        try dbQueue.write { db in
            var mutable = message
            try mutable.insert(db)

            let now = Int64(Date().timeIntervalSince1970 * 1000)
            try db.execute(
                sql: "UPDATE conversations SET updatedAtMs = ? WHERE id = ?",
                arguments: [now, mutable.conversationId]
            )

            return mutable.id ?? 0
        }
    }

    func updateMessage(_ message: ChatMessage) throws {
        try dbQueue.write { db in
            var mutable = message
            try mutable.update(db)
        }
    }

    func updateMessageText(messageId: Int64, text: String) throws {
        try dbQueue.write { db in
            guard var mutable = try ChatMessage.fetchOne(db, key: messageId) else { return }
            mutable.text = text
            try mutable.update(db)
        }
    }

    func saveThinking(messageId: Int64, stream: String) throws {
        try dbQueue.write { db in
            if var existing = try ChatMessageThinking.filter(Column("messageId") == messageId).fetchOne(db) {
                existing.thinkingStream = stream
                try existing.update(db)
            } else {
                var thinking = ChatMessageThinking(messageId: messageId, thinkingStream: stream)
                try thinking.insert(db)
            }
        }
    }

    func insertDualMessage(_ message: DualChatMessage) throws -> Int64 {
        try dbQueue.write { db in
            var mutable = message
            try mutable.insert(db)
            return mutable.id ?? 0
        }
    }

    func observeDualMessages(conversationId: Int64) -> AnyPublisher<[DualChatMessage], Never> {
        ValueObservation.tracking { db in
            try DualChatMessage
                .filter(Column("conversationId") == conversationId)
                .order(Column("createdAtMs").asc)
                .fetchAll(db)
        }
        .publisher(in: dbQueue)
        .replaceError(with: [])
        .eraseToAnyPublisher()
    }

    func searchConversations(query: String, limit: Int = 200) throws -> [ConversationListEntry] {
        let like = "%\(query)%"
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                SELECT DISTINCT c.id, c.title, c.updatedAtMs, c.isSecret,
                    (SELECT text FROM chat_messages m2 WHERE m2.conversationId = c.id ORDER BY m2.createdAtMs DESC LIMIT 1) AS lastMessagePreview
                FROM conversations c
                LEFT JOIN chat_messages m ON m.conversationId = c.id
                WHERE c.title LIKE ? OR m.text LIKE ?
                ORDER BY c.updatedAtMs DESC
                LIMIT ?
                """,
                arguments: [like, like, limit]
            )

            return rows.compactMap { row in
                guard let id: Int64 = row["id"] else { return nil }
                return ConversationListEntry(
                    id: id,
                    title: row["title"] ?? "New Chat",
                    updatedAtMs: row["updatedAtMs"] ?? 0,
                    lastMessagePreview: row["lastMessagePreview"],
                    isSecret: row["isSecret"] ?? false
                )
            }
        }
    }

    private func fetchMessageSummaries(db: Database, conversationId: Int64) throws -> [ChatMessageSummary] {
        let rows = try Row.fetchAll(
            db,
            sql: """
            SELECT id, role, text, createdAtMs, attachmentsJSON
            FROM chat_messages
            WHERE conversationId = ?
            ORDER BY createdAtMs ASC
            """,
            arguments: [conversationId]
        )

        return rows.compactMap { row in
            guard let id: Int64 = row["id"] else { return nil }
            let text: String = row["text"] ?? ""
            return ChatMessageSummary(
                id: id,
                role: row["role"] ?? "assistant",
                textPreview: String(text.prefix(200)),
                createdAtMs: row["createdAtMs"] ?? 0,
                hasAttachments: ((row["attachmentsJSON"] as String?) ?? "[]") != "[]"
            )
        }
    }
}
