import Foundation
import GRDB

struct DualChatMessage: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "dual_chat_messages"

    enum Role: String, Codable {
        case user
        case dualModel = "dual_model"
        case legacy
    }

    var id: Int64?
    var conversationId: Int64
    var role: String
    var userText: String
    var modelAText: String
    var modelBText: String
    var modelAName: String
    var modelBName: String
    var providerA: String
    var providerB: String
    var modelAThinking: String?
    var modelBThinking: String?
    var attachmentsJSON: String
    var modelAToolActivityJSON: String?
    var modelBToolActivityJSON: String?
    var createdAtMs: Int64

    init(
        id: Int64? = nil,
        conversationId: Int64,
        role: String = Role.legacy.rawValue,
        userText: String,
        modelAText: String,
        modelBText: String,
        modelAName: String,
        modelBName: String,
        providerA: String,
        providerB: String,
        modelAThinking: String? = nil,
        modelBThinking: String? = nil,
        attachmentsJSON: String = "[]",
        modelAToolActivityJSON: String? = nil,
        modelBToolActivityJSON: String? = nil,
        createdAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    ) {
        self.id = id
        self.conversationId = conversationId
        self.role = role
        self.userText = userText
        self.modelAText = modelAText
        self.modelBText = modelBText
        self.modelAName = modelAName
        self.modelBName = modelBName
        self.providerA = providerA
        self.providerB = providerB
        self.modelAThinking = modelAThinking
        self.modelBThinking = modelBThinking
        self.attachmentsJSON = attachmentsJSON
        self.modelAToolActivityJSON = modelAToolActivityJSON
        self.modelBToolActivityJSON = modelBToolActivityJSON
        self.createdAtMs = createdAtMs
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var parsedRole: Role {
        Role(rawValue: role) ?? .legacy
    }

    var attachments: [String] {
        guard
            let data = attachmentsJSON.data(using: .utf8),
            let values = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return values
    }

    var modelAToolActivity: ToolActivityPayload? { Self.decodeToolActivity(modelAToolActivityJSON) }
    var modelBToolActivity: ToolActivityPayload? { Self.decodeToolActivity(modelBToolActivityJSON) }

    static func encodeToolActivity(_ payload: ToolActivityPayload?) -> String? {
        guard let payload, payload.hasPersistableContent, let data = try? JSONEncoder().encode(payload) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func decodeToolActivity(_ raw: String?) -> ToolActivityPayload? {
        guard let data = raw?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(ToolActivityPayload.self, from: data)
    }
}
