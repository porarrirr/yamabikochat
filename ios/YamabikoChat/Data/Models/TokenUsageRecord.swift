import Foundation
import GRDB

struct TokenUsageRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "token_usage_records"

    var id: Int64?
    var timestamp: Int64
    var provider: String
    var model: String
    var requestType: String
    var conversationId: Int64?
    var inputTokens: Int
    var outputTokens: Int
    var totalTokens: Int
    var reasoningTokens: Int?
    var cachedInputTokens: Int?
    var cacheCreationInputTokens: Int?
    var contextTokens: Int?
    var contextWindow: Int?
    var costUsd: Double?

    init(
        id: Int64? = nil,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        provider: String,
        model: String,
        requestType: String = "chat",
        conversationId: Int64? = nil,
        inputTokens: Int = 0,
        outputTokens: Int = 0,
        totalTokens: Int = 0,
        reasoningTokens: Int? = nil,
        cachedInputTokens: Int? = nil,
        cacheCreationInputTokens: Int? = nil,
        contextTokens: Int? = nil,
        contextWindow: Int? = nil,
        costUsd: Double? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.provider = provider
        self.model = model
        self.requestType = requestType
        self.conversationId = conversationId
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.reasoningTokens = reasoningTokens
        self.cachedInputTokens = cachedInputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.contextTokens = contextTokens
        self.contextWindow = contextWindow
        self.costUsd = costUsd
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
