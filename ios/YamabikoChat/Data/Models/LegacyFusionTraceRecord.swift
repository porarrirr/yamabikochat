import Foundation
import GRDB

struct LegacyFusionTraceRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "fusion_traces"

    var id: String
    var conversationId: Int64?
    var preset: String
    var startedAtMs: Int64
    var completedAtMs: Int64?
    var totalLatencyMs: Int64?
    var totalCostUsd: Double?
    var failedModelsJSON: String
    var traceJSON: String
    var status: String

    func fusionTrace() throws -> LegacyFusionTrace {
        let decoder = JSONDecoder()
        return try decoder.decode(LegacyFusionTrace.self, from: Data(traceJSON.utf8))
    }
}
