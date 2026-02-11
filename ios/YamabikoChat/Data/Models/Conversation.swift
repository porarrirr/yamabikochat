import Foundation
import GRDB

struct Conversation: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "conversations"

    var id: Int64?
    var title: String
    var systemPrompt: String?
    var model: String
    var apiProvider: String
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var codexSessionId: String?
    var isSecret: Bool
    var projectId: Int64?

    init(
        id: Int64? = nil,
        title: String,
        systemPrompt: String? = nil,
        model: String,
        apiProvider: String = "GEMINI",
        createdAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        updatedAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        codexSessionId: String? = nil,
        isSecret: Bool = false,
        projectId: Int64? = nil
    ) {
        self.id = id
        self.title = title
        self.systemPrompt = systemPrompt
        self.model = model
        self.apiProvider = apiProvider
        self.createdAtMs = createdAtMs
        self.updatedAtMs = updatedAtMs
        self.codexSessionId = codexSessionId
        self.isSecret = isSecret
        self.projectId = projectId
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
