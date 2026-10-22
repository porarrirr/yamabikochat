import Foundation

// Read-only compatibility fields used to export historical Fusion diagnostics.
// The complete original payload is preserved in LegacyFusionTraceRecord.traceJSON.
struct LegacyFusionTrace: Decodable {
    struct Panel: Decodable {
        var modelId: String
        var toolActivity: ToolActivityPayload?
        var piExecution: JSONValue?
    }

    struct Judge: Decodable {
        var piExecutions: [JSONValue]?
    }

    struct Synthesis: Decodable {
        var piExecution: JSONValue?
    }

    var panelResults: [Panel]
    var judgeResult: Judge?
    var synthesisResult: Synthesis?
}
