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
    var resultPreview: String? = nil
    var outputPreview: String? = nil
    var artifactNames: [String]? = nil
    var durationMs: Int64? = nil

    var isWebActivity: Bool {
        toolName == WebSearchTool.name || toolName == FetchUrlTool.name
    }
}

struct ToolActivityEvent: Sendable, Equatable {
    enum Phase: Sendable, Equatable {
        case started
        case finished
    }

    var phase: Phase
    var call: ToolCall
    var result: ToolResult?
    var createdAtMs: Int64
}

struct ToolActivityPayload: Codable, Sendable, Equatable {
    var steps: [ToolActivityStep] = []
    var providerTranscript: [ProviderRequestMessage] = []
    var attachmentPaths: [String] = []

    init(
        steps: [ToolActivityStep] = [],
        providerTranscript: [ProviderRequestMessage] = [],
        attachmentPaths: [String] = []
    ) {
        self.steps = steps
        self.providerTranscript = providerTranscript
        self.attachmentPaths = attachmentPaths
    }

    private enum CodingKeys: String, CodingKey {
        case steps, providerTranscript, attachmentPaths
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        steps = try container.decodeIfPresent([ToolActivityStep].self, forKey: .steps) ?? []
        providerTranscript = try container.decodeIfPresent([ProviderRequestMessage].self, forKey: .providerTranscript) ?? []
        attachmentPaths = try container.decodeIfPresent([String].self, forKey: .attachmentPaths) ?? []
    }

    mutating func apply(_ event: ToolActivityEvent) {
        var step = Self.step(for: event)
        if let index = steps.firstIndex(where: { $0.id == step.id }) {
            step.round = steps[index].round
            steps[index] = step
        } else {
            step.round = (steps.map(\.round).max() ?? 0) + 1
            steps.append(step)
        }
        steps.sort { $0.round < $1.round }

        guard event.phase == .finished, let result = event.result else { return }
        for path in result.artifacts.map(\.path) where !attachmentPaths.contains(path) {
            attachmentPaths.append(path)
        }
        providerTranscript.removeAll { message in
            message.toolCallId == event.call.id || message.toolCalls?.contains(where: { $0.id == event.call.id }) == true
        }
        providerTranscript.append(
            ProviderRequestMessage(role: "assistant", content: "", toolCalls: [event.call])
        )
        providerTranscript.append(
            ProviderRequestMessage(
                role: "tool",
                content: result.content,
                toolCallId: event.call.id,
                toolName: event.call.name,
                toolResultIsError: result.isError
            )
        )
    }

    mutating func failRunning(message: String) {
        for index in steps.indices where steps[index].status == .running {
            steps[index].status = .failed
            steps[index].errorMessage = message
        }
    }

    private static func step(for event: ToolActivityEvent) -> ToolActivityStep {
        let arguments = jsonObject(event.call.argumentsJSON)
        let query = (arguments?["query"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let goal = (arguments?["goal"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let rawURL = arguments?["url"] as? String
        let host = rawURL.flatMap { URL(string: $0)?.host }
        let isSearch = event.call.name == WebSearchTool.name
        let isFetch = event.call.name == FetchUrlTool.name
        let isPython = event.call.name == PythonExecuteTool.name
        let code = (arguments?["code"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = isPython
            ? L10n.text("Pythonを実行")
            : (isSearch
                ? L10n.text("Webを検索")
                : (isFetch ? L10n.text("ページを確認") : displayName(event.call.name)))
        let detail = isPython
            ? (code?.trimmedNonEmpty ?? L10n.text("コードを確認中"))
            : (isSearch
                ? (query?.trimmedNonEmpty ?? L10n.text("検索語を確認中"))
                : (isFetch
                    ? [host, goal?.trimmedNonEmpty].compactMap { $0 }.joined(separator: " — ").trimmedNonEmpty ?? L10n.text("ページを確認中")
                    : genericArgumentSummary(arguments, raw: event.call.argumentsJSON)))
        let result = event.result
        let resultObject = result.flatMap { jsonObject($0.content) }
        let resultCount = (resultObject?["results"] as? [Any])?.count
        let nestedError = (resultObject?["error"] as? [String: Any])?["message"] as? String
        let error = result?.isError == true
            ? (nestedError?.trimmedNonEmpty ?? (resultObject?["error"] as? String)?.trimmedNonEmpty ?? L10n.text("ツールの実行に失敗しました"))
            : nil
        let sources = deduplicatedSources(result?.sources ?? [])
        let stdout = (resultObject?["stdout"] as? String)?.trimmedNonEmpty
        let stderr = (resultObject?["stderr"] as? String)?.trimmedNonEmpty
        let outputPreview = [stdout, stderr].compactMap { $0 }.joined(separator: "\n").trimmedNonEmpty
        let resultPreview = (resultObject?["result_repr"] as? String)?.trimmedNonEmpty
        let artifactNames = result?.artifacts.map(\.name).filter { !$0.isEmpty }
        let durationMs = (resultObject?["duration_ms"] as? NSNumber)?.int64Value
        return ToolActivityStep(
            id: event.call.id,
            round: 0,
            toolName: event.call.name,
            title: title,
            detail: detail,
            status: event.phase == .started ? .running : (result?.isError == true ? .failed : .completed),
            resultCount: resultCount,
            sources: sources,
            errorMessage: error,
            createdAtMs: event.createdAtMs,
            resultPreview: resultPreview,
            outputPreview: outputPreview,
            artifactNames: artifactNames?.isEmpty == false ? artifactNames : nil,
            durationMs: durationMs
        )
    }

    private static func displayName(_ name: String) -> String {
        name.replacingOccurrences(of: "_", with: " ")
    }

    private static func genericArgumentSummary(_ object: [String: Any]?, raw: String) -> String {
        guard let object else { return raw }
        let values = object.keys.sorted().compactMap { key -> String? in
            switch object[key] {
            case let value as String:
                return "\(key): \(value)"
            case let value as NSNumber:
                return "\(key): \(value)"
            default:
                return nil
            }
        }
        return values.joined(separator: " · ").trimmedNonEmpty ?? raw
    }

    private static func jsonObject(_ value: String) -> [String: Any]? {
        guard let data = value.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func deduplicatedSources(_ sources: [ToolSource]) -> [ToolSource] {
        var seen: Set<String> = []
        return sources.filter { seen.insert($0.url).inserted }
    }
}
