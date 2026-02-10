import Foundation
import GRDB

struct AutoConversationMessage: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "auto_conversation_messages"

    var id: Int64?
    var autoConversationId: Int64
    var speaker: String
    var content: String
    var turnIndex: Int
    var createdAtMs: Int64

    init(
        id: Int64? = nil,
        autoConversationId: Int64,
        speaker: String,
        content: String,
        turnIndex: Int,
        createdAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.autoConversationId = autoConversationId
        self.speaker = speaker
        self.content = content
        self.turnIndex = turnIndex
        self.createdAtMs = createdAtMs
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}