import Foundation
import GRDB

struct DualChatMessage: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "dual_chat_messages"

    var id: Int64?
    var conversationId: Int64
    var userText: String
    var modelAText: String
    var modelBText: String
    var modelAName: String
    var modelBName: String
    var providerA: String
    var providerB: String
    var createdAtMs: Int64

    init(
        id: Int64? = nil,
        conversationId: Int64,
        userText: String,
        modelAText: String,
        modelBText: String,
        modelAName: String,
        modelBName: String,
        providerA: String,
        providerB: String,
        createdAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.conversationId = conversationId
        self.userText = userText
        self.modelAText = modelAText
        self.modelBText = modelBText
        self.modelAName = modelAName
        self.modelBName = modelBName
        self.providerA = providerA
        self.providerB = providerB
        self.createdAtMs = createdAtMs
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}