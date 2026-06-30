import Foundation

protocol LocalToolExecutor: Sendable {
    var definition: ToolDefinition { get }
    func execute(call: ToolCall) async throws -> ToolResult
}

struct LocalToolRegistry: Sendable {
    private let executors: [String: any LocalToolExecutor]

    init(executors: [any LocalToolExecutor]) {
        self.executors = Dictionary(
            executors.map { ($0.definition.name, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    var definitions: [ToolDefinition] {
        executors.values.map(\.definition).sorted { $0.name < $1.name }
    }

    func execute(call: ToolCall) async -> ToolResult {
        guard let executor = executors[call.name] else {
            return ToolResult(
                callId: call.id,
                name: call.name,
                content: Self.errorContent("Unknown local tool: \(call.name)"),
                isError: true
            )
        }

        do {
            return try await executor.execute(call: call)
        } catch {
            if call.name != WebSearchTool.name {
                DiagnosticsLogger.log(
                    "Local tool execution failed",
                    category: .network,
                    metadata: ["tool": call.name],
                    error: error
                )
            }
            return ToolResult(
                callId: call.id,
                name: call.name,
                content: Self.errorContent(error.localizedDescription),
                isError: true
            )
        }
    }

    static func errorContent(_ message: String) -> String {
        let object = ["error": message]
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let json = String(data: data, encoding: .utf8)
        else {
            return #"{"error":"Local tool execution failed"}"#
        }
        return json
    }
}
