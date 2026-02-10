import Foundation
import GRDB

struct ChatMessage: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "chat_messages"

    var id: Int64?
    var conversationId: Int64
    var role: String
    var text: String
    var attachmentsJSON: String
    var createdAtMs: Int64

    init(
        id: Int64? = nil,
        conversationId: Int64,
        role: String,
        text: String,
        attachmentsJSON: String = "[]",
        createdAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.text = text
        self.attachmentsJSON = attachmentsJSON
        self.createdAtMs = createdAtMs
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}