import Foundation
import GRDB

struct ChatMessageToolActivity: Codable, FetchableRecord, MutablePersistableRecord, Equatable {
    static let databaseTableName = "chat_message_tool_activity"

    var id: Int64?
    var messageId: Int64?
    var variantId: Int64?
    var stepsJSON: String

    init(id: Int64? = nil, messageId: Int64? = nil, variantId: Int64? = nil, stepsJSON: String) {
        self.id = id
        self.messageId = messageId
        self.variantId = variantId
        self.stepsJSON = stepsJSON
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var steps: [ToolActivityStep] {
        guard let data = stepsJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ToolActivityStep].self, from: data)) ?? []
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

    static func started(call: ToolCall, round: Int) -> ToolActivityStep {
        let arguments = (try? ToolArguments.object(from: call.argumentsJSON)) ?? [:]
        let detail: String
        switch call.name {
        case WebSearchTool.name:
            detail = (arguments["query"] as? String)?.trimmedNonEmpty ?? call.argumentsJSON
        case FetchUrlTool.name:
            detail = (arguments["url"] as? String)?.trimmedNonEmpty ?? call.argumentsJSON
        default:
            detail = call.argumentsJSON
        }
        return ToolActivityStep(
            id: call.id,
            round: round,
            toolName: call.name,
            title: call.name == WebSearchTool.name
                ? L10n.text("Webを検索")
                : L10n.text("ページを取得"),
            detail: detail,
            status: .running,
            resultCount: nil,
            sources: [],
            errorMessage: nil,
            createdAtMs: Int64(Date().timeIntervalSince1970 * 1_000)
        )
    }

    mutating func finish(with result: ToolResult) {
        sources = result.sources
        if result.isError {
            status = .failed
            errorMessage = Self.errorMessage(from: result.content)
            return
        }
        status = .completed
        if toolName == WebSearchTool.name {
            resultCount = result.sources.count
        }
    }

    private static func errorMessage(from content: String) -> String {
        guard let data = content.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? String
        else {
            return content
        }
        return error
    }
}
