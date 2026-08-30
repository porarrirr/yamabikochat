import Foundation
import GRDB

struct FusionTraceRecord: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Equatable {
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

    init(
        id: String,
        conversationId: Int64?,
        preset: String,
        startedAtMs: Int64,
        completedAtMs: Int64?,
        totalLatencyMs: Int64?,
        totalCostUsd: Double?,
        failedModels: [String],
        trace: FusionTrace,
        status: String
    ) throws {
        self.id = id
        self.conversationId = conversationId
        self.preset = preset
        self.startedAtMs = startedAtMs
        self.completedAtMs = completedAtMs
        self.totalLatencyMs = totalLatencyMs
        self.totalCostUsd = totalCostUsd
        self.status = status
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        failedModelsJSON = String(data: try encoder.encode(failedModels), encoding: .utf8) ?? "[]"
        traceJSON = String(data: try encoder.encode(trace), encoding: .utf8) ?? "{}"
    }

    func fusionTrace() throws -> FusionTrace {
        let decoder = JSONDecoder()
        return try decoder.decode(FusionTrace.self, from: Data(traceJSON.utf8))
    }
}

final class FusionTraceStore {
    private let dbQueue: DatabaseQueue

    init(dbQueue: DatabaseQueue) {
        self.dbQueue = dbQueue
    }

    func save(trace: FusionTrace, conversationId: Int64?) throws {
        if let conversationId,
           try dbQueue.read({ db in
               try Bool.fetchOne(
                   db,
                   sql: "SELECT isSecret FROM conversations WHERE id = ?",
                   arguments: [conversationId]
               ) ?? false
           }) {
            return
        }
        var record = try FusionTraceRecord(
            id: trace.requestId,
            conversationId: conversationId,
            preset: trace.preset,
            startedAtMs: trace.startedAtMs,
            completedAtMs: trace.completedAtMs,
            totalLatencyMs: trace.totalLatencyMs,
            totalCostUsd: trace.totalCost,
            failedModels: trace.failedModels,
            trace: trace,
            status: trace.status
        )
        try dbQueue.write { db in
            try record.insert(db, onConflict: .replace)
        }
        logTraceSummary(trace: trace, conversationId: conversationId)
    }

    func fetch(id: String) throws -> FusionTrace? {
        try dbQueue.read { db in
            guard let record = try FusionTraceRecord.fetchOne(db, key: id) else { return nil }
            return try record.fusionTrace()
        }
    }

    private func logTraceSummary(trace: FusionTrace, conversationId: Int64?) {
        var metadata: [String: String] = [
            "traceId": trace.requestId,
            "preset": trace.preset,
            "status": trace.status,
            "panelCount": String(trace.panelResults.count),
            "failedCount": String(trace.failedModels.count)
        ]
        if let conversationId {
            metadata["conversationId"] = String(conversationId)
        }
        if let totalLatencyMs = trace.totalLatencyMs {
            metadata["totalLatencyMs"] = String(totalLatencyMs)
        }
        if let totalCost = trace.totalCost {
            metadata["totalCostUsd"] = String(format: "%.6f", totalCost)
        }
        if let judge = trace.judgeResult {
            metadata["judgeParseSucceeded"] = String(judge.parseSucceeded)
        }
        for panel in trace.panelResults {
            metadata["panel.\(panel.modelId).success"] = String(panel.success)
            metadata["panel.\(panel.modelId).latencyMs"] = String(panel.latencyMs)
        }
        DiagnosticsLogger.log(
            "Fusion trace saved",
            category: .fusion,
            requestID: trace.requestId,
            metadata: metadata
        )
    }
}
