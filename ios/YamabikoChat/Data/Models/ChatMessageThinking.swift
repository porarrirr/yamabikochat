import Foundation
import GRDB

struct ChatMessageThinking: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "chat_message_thinking"

    var id: Int64?
    var messageId: Int64
    var thinkingStream: String

    init(id: Int64? = nil, messageId: Int64, thinkingStream: String) {
        self.id = id
        self.messageId = messageId
        self.thinkingStream = thinkingStream
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}