import Foundation
import GRDB

struct ModelPreset: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "model_presets"

    var id: Int64?
    var name: String
    var model: String
    var apiProvider: String
    var systemPrompt: String?
    var configJSON: String
    var createdAtMs: Int64

    init(
        id: Int64? = nil,
        name: String,
        model: String,
        apiProvider: String,
        systemPrompt: String? = nil,
        configJSON: String = "{}",
        createdAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.name = name
        self.model = model
        self.apiProvider = apiProvider
        self.systemPrompt = systemPrompt
        self.configJSON = configJSON
        self.createdAtMs = createdAtMs
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}