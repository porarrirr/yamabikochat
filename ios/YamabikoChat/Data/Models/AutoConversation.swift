import Foundation
import GRDB

struct AutoConversation: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "auto_conversations"

    var id: Int64?
    var title: String
    var modelA: String
    var modelB: String
    var providerA: String
    var providerB: String
    var systemPromptA: String
    var systemPromptB: String
    var maxTurns: Int
    var status: String
    var boundConversationId: Int64?
    var createdAtMs: Int64
    var updatedAtMs: Int64

    init(
        id: Int64? = nil,
        title: String,
        modelA: String,
        modelB: String,
        providerA: String,
        providerB: String,
        systemPromptA: String,
        systemPromptB: String,
        maxTurns: Int,
        status: String = "idle",
        boundConversationId: Int64? = nil,
        createdAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        updatedAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.title = title
        self.modelA = modelA
        self.modelB = modelB
        self.providerA = providerA
        self.providerB = providerB
        self.systemPromptA = systemPromptA
        self.systemPromptB = systemPromptB
        self.maxTurns = maxTurns
        self.status = status
        self.boundConversationId = boundConversationId
        self.createdAtMs = createdAtMs
        self.updatedAtMs = updatedAtMs
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}