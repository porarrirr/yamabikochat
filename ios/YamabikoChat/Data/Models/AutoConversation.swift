import Foundation
import GRDB

enum AutoConversationStatus: String, Codable, CaseIterable {
    case active = "ACTIVE"
    case paused = "PAUSED"
    case ended = "ENDED"
}

enum AutoConversationEndReason {
    static let userStop = "USER_STOP"
    static let maxTurns = "MAX_TURNS"
    static let endSignal = "END_SIGNAL"
    static let error = "ERROR"
    static let apiError = "API_ERROR"
}

struct AutoConversationConfig {
    var title: String
    var modelA: String
    var modelB: String
    var providerA: String
    var providerB: String
    var systemPromptA: String
    var systemPromptB: String
    var maxTurns: Int
    var endSignal: String
}

struct AutoConversation: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "auto_conversations"

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case modelA
        case modelB
        case providerA
        case providerB
        case systemPromptA
        case systemPromptB
        case statusRaw = "status"
        case maxTurns
        case currentTurn
        case createdAtMs
        case lastActiveAtMs
        case endReason
        case endSignal
        case boundChatConversationId
    }

    var id: Int64?
    var title: String
    var modelA: String
    var modelB: String
    var providerA: String
    var providerB: String
    var systemPromptA: String
    var systemPromptB: String
    var statusRaw: String
    var maxTurns: Int
    var currentTurn: Int
    var createdAtMs: Int64
    var lastActiveAtMs: Int64
    var endReason: String?
    var endSignal: String
    var boundChatConversationId: Int64?

    var status: AutoConversationStatus {
        get { AutoConversationStatus(rawValue: statusRaw.uppercased()) ?? .ended }
        set { statusRaw = newValue.rawValue }
    }

    init(
        id: Int64? = nil,
        title: String,
        modelA: String,
        modelB: String,
        providerA: String,
        providerB: String,
        systemPromptA: String,
        systemPromptB: String,
        status: AutoConversationStatus = .active,
        maxTurns: Int,
        currentTurn: Int = 0,
        createdAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        lastActiveAtMs: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        endReason: String? = nil,
        endSignal: String = "[END]",
        boundChatConversationId: Int64? = nil
    ) {
        self.id = id
        self.title = title
        self.modelA = modelA
        self.modelB = modelB
        self.providerA = providerA
        self.providerB = providerB
        self.systemPromptA = systemPromptA
        self.systemPromptB = systemPromptB
        statusRaw = status.rawValue
        self.maxTurns = maxTurns
        self.currentTurn = currentTurn
        self.createdAtMs = createdAtMs
        self.lastActiveAtMs = lastActiveAtMs
        self.endReason = endReason
        self.endSignal = endSignal
        self.boundChatConversationId = boundChatConversationId
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
