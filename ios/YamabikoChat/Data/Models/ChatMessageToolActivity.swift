import Foundation
import GRDB

struct ChatMessageToolActivity: Codable, FetchableRecord, MutablePersistableRecord, Equatable {
    static let databaseTableName = "chat_message_tool_activity"

    var id: Int64?
    var messageId: Int64?
    var variantId: Int64?
    var stepsJSON: String
    var providerTranscriptJSON: String?

    init(
        id: Int64? = nil,
        messageId: Int64? = nil,
        variantId: Int64? = nil,
        stepsJSON: String,
        providerTranscriptJSON: String? = nil
    ) {
        self.id = id
        self.messageId = messageId
        self.variantId = variantId
        self.stepsJSON = stepsJSON
        self.providerTranscriptJSON = providerTranscriptJSON
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var steps: [ToolActivityStep] {
        guard let data = stepsJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ToolActivityStep].self, from: data)) ?? []
    }

    var providerTranscript: [ProviderRequestMessage]? {
        guard let providerTranscriptJSON,
              let data = providerTranscriptJSON.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode([ProviderRequestMessage].self, from: data)
    }
}

struct ToolActivityStep: Codable, Sendable, Equatable, Identifiable {
    enum Status: String, Codable, Sendable {
        case running
        case completed
        case failed
    }

    var id: String
    var round: Int
    var toolName: String
    var title: String
    var detail: String
    var status: Status
    var resultCount: Int?
    var sources: [ToolSource]
    var errorMessage: String?
    var createdAtMs: Int64
}
