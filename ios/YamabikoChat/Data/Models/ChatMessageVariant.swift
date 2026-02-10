import Foundation
import GRDB

struct ChatMessageVariant: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "chat_message_variants"

    var id: Int64?
    var baseMessageId: Int64
    var variantIndex: Int
    var text: String
    var attachmentsJSON: String
    var thinkingStream: String?
    var createdAtMs: Int64

    init(
        id: Int64? = nil,
        baseMessageId: Int64,
        variantIndex: Int,
        text: String,
        attachmentsJSON: String = "[]",
        thinkingStream: String? = nil,
        createdAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.baseMessageId = baseMessageId
        self.variantIndex = variantIndex
        self.text = text
        self.attachmentsJSON = attachmentsJSON
        self.thinkingStream = thinkingStream
        self.createdAtMs = createdAtMs
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
