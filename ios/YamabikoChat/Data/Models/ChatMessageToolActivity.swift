import Foundation
import GRDB

struct ChatMessageToolActivity: Codable, FetchableRecord, MutablePersistableRecord, Equatable {
    static let databaseTableName = "chat_message_tool_activity"

    var id: Int64?
    var messageId: Int64?
    var variantId: Int64?
    var stepsJSON: String
    var providerTranscriptJSON: String?
    var attachmentPathsJSON: String?
    var piExecutionJSON: String?
    var rotationNoticesJSON: String?

    init(
        id: Int64? = nil,
        messageId: Int64? = nil,
        variantId: Int64? = nil,
        stepsJSON: String,
        providerTranscriptJSON: String? = nil,
        attachmentPathsJSON: String? = nil,
        piExecutionJSON: String? = nil,
        rotationNoticesJSON: String? = nil
    ) {
        self.id = id
        self.messageId = messageId
        self.variantId = variantId
        self.stepsJSON = stepsJSON
        self.providerTranscriptJSON = providerTranscriptJSON
        self.attachmentPathsJSON = attachmentPathsJSON
        self.piExecutionJSON = piExecutionJSON
        self.rotationNoticesJSON = rotationNoticesJSON
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var steps: [ToolActivityStep] {
        ToolActivityPayload(steps: decodedSteps, providerTranscript: providerTranscript ?? []).steps
    }

    private var decodedSteps: [ToolActivityStep] {
        guard let data = stepsJSON.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([ToolActivityStep].self, from: data)) ?? []
    }

    var providerTranscript: [ProviderRequestMessage]? {
        guard let providerTranscriptJSON,
              let data = providerTranscriptJSON.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode([ProviderRequestMessage].self, from: data)
    }

    var piExecution: JSONValue? {
        guard let piExecutionJSON,
              let data = piExecutionJSON.data(using: .utf8)
        else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    var attachmentPaths: [String] {
        guard let attachmentPathsJSON,
              let data = attachmentPathsJSON.data(using: .utf8)
        else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    var rotationNotices: [ProviderRotationNotice] {
        guard let rotationNoticesJSON,
              let data = rotationNoticesJSON.data(using: .utf8)
        else { return [] }
        return (try? JSONDecoder().decode([ProviderRotationNotice].self, from: data)) ?? []
    }

    var payload: ToolActivityPayload {
        ToolActivityPayload(
            steps: decodedSteps,
            providerTranscript: providerTranscript ?? [],
            attachmentPaths: attachmentPaths,
            piExecution: piExecution,
            rotationNotices: rotationNotices
        )
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
    var genUIDocument: GenUIDocument? = nil
    var subagent: SubagentRun? = nil

    var isWebActivity: Bool {
        toolName == WebSearchTool.name || toolName == FetchUrlTool.name
    }
}

struct ToolActivityEvent: Sendable, Equatable {
    enum Phase: Sendable, Equatable {
        case generating
        case started
        case finished
    }

    static func reportsActivity(for name: String) -> Bool {
        [WebSearchTool.name, FetchUrlTool.name, PythonExecuteTool.name,
         StrReplaceEditorTool.name, GenUITool.name, GenUIReferenceTool.name].contains(name)
    }

    var phase: Phase
    var call: ToolCall
    var result: ToolResult?
    var createdAtMs: Int64
    var subagent: SubagentRun? = nil
    var ownerSubagentID: String? = nil
}

struct ToolActivityPayload: Codable, Sendable, Equatable {
    var steps: [ToolActivityStep] = []
    var providerTranscript: [ProviderRequestMessage] = []
    var attachmentPaths: [String] = []
    var piExecution: JSONValue? = nil
    var rotationNotices: [ProviderRotationNotice] = []

    init(
        steps: [ToolActivityStep] = [],
        providerTranscript: [ProviderRequestMessage] = [],
        attachmentPaths: [String] = [],
        piExecution: JSONValue? = nil,
        rotationNotices: [ProviderRotationNotice] = []
    ) {
        self.steps = steps
        self.providerTranscript = providerTranscript
        self.attachmentPaths = attachmentPaths
        self.piExecution = piExecution
        self.rotationNotices = rotationNotices
        restoreMissingGenUISteps()
    }

    private enum CodingKeys: String, CodingKey {
        case steps, providerTranscript, attachmentPaths, piExecution, rotationNotices
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        steps = try container.decodeIfPresent([ToolActivityStep].self, forKey: .steps) ?? []
        providerTranscript = try container.decodeIfPresent([ProviderRequestMessage].self, forKey: .providerTranscript) ?? []
        attachmentPaths = try container.decodeIfPresent([String].self, forKey: .attachmentPaths) ?? []
        piExecution = try container.decodeIfPresent(JSONValue.self, forKey: .piExecution)
        rotationNotices = try container.decodeIfPresent([ProviderRotationNotice].self, forKey: .rotationNotices) ?? []
        restoreMissingGenUISteps()
    }

    var hasPersistableContent: Bool {
        !steps.isEmpty || !providerTranscript.isEmpty || !attachmentPaths.isEmpty
            || piExecution != nil || !rotationNotices.isEmpty
    }

    var subagents: [SubagentRun] { steps.compactMap(\.subagent) }

    var parentAttachmentPaths: [String] {
        let childPaths = Set(subagents.flatMap { ($0.artifacts ?? []).map(\.path) })
        return attachmentPaths.filter { !childPaths.contains($0) }
    }

    mutating func applySubagent(_ run: SubagentRun) {
        var step = run.step
        if let index = steps.firstIndex(where: { $0.id == step.id }) {
            // Terminal records cannot regress when a delayed running snapshot arrives.
            if let previous = steps[index].subagent,
               previous.updatedAtMs > run.updatedAtMs || (previous.status != .running && run.status == .running) { return }
            step.round = steps[index].round
            if step.subagent?.artifacts == nil { step.subagent?.artifacts = steps[index].subagent?.artifacts }
            steps[index] = step
        } else {
            step.round = (steps.map(\.round).max() ?? 0) + 1
            steps.append(step)
        }
    }

    mutating func apply(_ event: ToolActivityEvent) {
        if let run = event.subagent {
            applySubagent(run)
            return
        }
        if let ownerID = event.ownerSubagentID {
            if event.phase == .finished, let result = event.result,
               let index = steps.firstIndex(where: { $0.subagent?.id == ownerID }) {
                var artifacts = steps[index].subagent?.artifacts ?? []
                for artifact in result.artifacts {
                    artifacts.removeAll { $0.name == artifact.name }
                    artifacts.append(artifact)
                    if !attachmentPaths.contains(artifact.path) { attachmentPaths.append(artifact.path) }
                }
                steps[index].subagent?.artifacts = artifacts
            }
            return
        }
        var step = Self.step(for: event)
        if let index = steps.firstIndex(where: { $0.id == step.id }) {
            step.round = steps[index].round
            if event.phase != .finished, step.genUIDocument == nil { step.genUIDocument = steps[index].genUIDocument }
            steps[index] = step
        } else {
            step.round = (steps.map(\.round).max() ?? 0) + 1
            steps.append(step)
        }
        steps.sort { $0.round < $1.round }

        guard event.phase == .finished, let result = event.result else { return }
        for artifact in result.artifacts {
            // Python's persisted path gains a numeric suffix when the same logical
            // output is generated again. Keep only the path and activity badge for
            // the newest version of that named artifact.
            attachmentPaths.removeAll { Self.isPersistedVersion($0, of: artifact.name) }
            for index in steps.indices where steps[index].id != event.call.id {
                guard var names = steps[index].artifactNames else { continue }
                names.removeAll { $0 == artifact.name }
                steps[index].artifactNames = names.isEmpty ? nil : names
            }
            attachmentPaths.append(artifact.path)
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
                attachments: result.artifacts.filter { $0.mime.lowercased().hasPrefix("image/") }.map(\.path),
                toolCallId: event.call.id,
                toolName: event.call.name,
                toolResultIsError: result.isError
            )
        )
    }

    // Older Pi bridge builds executed GenUI but persisted only its transcript.
    // Recover validated results locally without executing the tool or model again.
    private mutating func restoreMissingGenUISteps() {
        var calls: [String: ToolCall] = [:]
        var existingIDs = Set(steps.map(\.id))
        for message in providerTranscript {
            if message.role == "assistant" {
                for call in message.toolCalls ?? [] where call.name == GenUITool.name {
                    calls[call.id] = call
                }
            }
            guard message.role == "tool", message.toolName == GenUITool.name,
                  message.toolResultIsError == false,
                  let id = message.toolCallId, let call = calls[id],
                  !existingIDs.contains(id) else { continue }
            let result = ToolResult(callId: id, name: call.name, content: message.content)
            var step = Self.step(for: ToolActivityEvent(
                phase: .finished, call: call, result: result, createdAtMs: 0
            ))
            guard step.genUIDocument != nil else { continue }
            step.round = (steps.map(\.round).max() ?? 0) + 1
            steps.append(step)
            existingIDs.insert(id)
        }
    }

    mutating func failRunning(message: String) {
        for index in steps.indices where steps[index].status == .running {
            if var run = steps[index].subagent {
                run.status = .cancelled
                run.activity = "中断"
                run.error = message
                run.finishedAtMs = Int64(Date().timeIntervalSince1970 * 1_000)
                steps[index].subagent = run
            }
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
        let isGenUI = event.call.name == GenUITool.name
        let code = (arguments?["code"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let title = isGenUI ? L10n.text("インタラクティブUIを作成") : isPython
            ? L10n.text("Pythonを実行")
            : (isSearch
                ? L10n.text("Webを検索")
                : (isFetch ? L10n.text("ページを確認") : displayName(event.call.name)))
        let detail = isGenUI ? ((arguments?["title"] as? String) ?? "GenUI") : isPython
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
            status: event.phase != .finished ? .running : (result?.isError == true ? .failed : .completed),
            resultCount: resultCount,
            sources: sources,
            errorMessage: error,
            createdAtMs: event.createdAtMs,
            resultPreview: resultPreview,
            outputPreview: outputPreview,
            artifactNames: artifactNames?.isEmpty == false ? artifactNames : nil,
            durationMs: durationMs,
            genUIDocument: isGenUI
                ? (event.phase == .finished
                   ? (result?.isError == false ? result.flatMap { try? GenUIDocument.validated(from: $0.content) } : nil)
                   : try? GenUITool.previewDocument(from: event.call.argumentsJSON)) : nil
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

    private static func isPersistedVersion(_ path: String, of artifactName: String) -> Bool {
        let candidate = URL(fileURLWithPath: path).lastPathComponent
        let artifactURL = URL(fileURLWithPath: artifactName)
        let candidateURL = URL(fileURLWithPath: candidate)
        guard candidateURL.pathExtension == artifactURL.pathExtension else { return false }
        let expectedStem = artifactURL.deletingPathExtension().lastPathComponent
        let candidateStem = candidateURL.deletingPathExtension().lastPathComponent
        return candidateStem == expectedStem
            || candidateStem.range(
                of: #"^\#(NSRegularExpression.escapedPattern(for: expectedStem)) \([0-9]+\)$"#,
                options: .regularExpression
            ) != nil
    }
}
