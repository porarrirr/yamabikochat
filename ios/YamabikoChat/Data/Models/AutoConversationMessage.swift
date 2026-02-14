import Foundation
import GRDB

enum AutoConversationSpeakerModel: String, Codable {
    case user = "USER"
    case a = "A"
    case b = "B"
}

struct AutoConversationMessage: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "auto_conversation_messages"

    enum CodingKeys: String, CodingKey {
        case id
        case autoConversationId
        case speakerModelRaw = "speaker"
        case content
        case reasoning
        case turnNumber = "turnIndex"
        case timestamp = "createdAtMs"
        case isEndSignal
    }

    var id: Int64?
    var autoConversationId: Int64
    var speakerModelRaw: String
    var content: String
    var reasoning: String?
    var turnNumber: Int
    var timestamp: Int64
    var isEndSignal: Bool

    var speakerModel: AutoConversationSpeakerModel {
        get { AutoConversationSpeakerModel(rawValue: speakerModelRaw.uppercased()) ?? .user }
        set { speakerModelRaw = newValue.rawValue }
    }

    init(
        id: Int64? = nil,
        autoConversationId: Int64,
        speakerModel: AutoConversationSpeakerModel,
        content: String,
        reasoning: String? = nil,
        turnNumber: Int,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        isEndSignal: Bool = false
    ) {
        self.id = id
        self.autoConversationId = autoConversationId
        speakerModelRaw = speakerModel.rawValue
        self.content = content
        self.reasoning = reasoning
        self.turnNumber = turnNumber
        self.timestamp = timestamp
        self.isEndSignal = isEndSignal
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
