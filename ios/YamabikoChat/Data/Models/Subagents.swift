import Foundation

struct SubagentModelProfile: Codable, Hashable, Identifiable, Sendable {
    var id: String = UUID().uuidString
    var name: String = "サブエージェント"
    var provider: String = "GEMINI"
    var model: String = ""
    var effort: String = "off"
    var endpointPresetName: String? = nil

    init(id: String = UUID().uuidString, name: String = "サブエージェント",
         provider: String = "GEMINI", model: String = "", effort: String? = nil,
         endpointPresetName: String? = nil) {
        self.id = id
        self.name = name
        self.provider = provider
        self.model = model
        self.effort = effort ?? (AppleIntelligenceModelCatalog.isPCC(provider: provider, model: model) ? "medium" : "off")
        self.endpointPresetName = endpointPresetName
    }

    var isPCC: Bool { AppleIntelligenceModelCatalog.isPCC(provider: provider, model: model) }

    /// Called only when the user explicitly selects PCC, never while loading saved profiles.
    mutating func initializePCCEffortIfNeeded() {
        if isPCC, AppleIntelligenceModelCatalog.pccReasoningLevel(forPiThinkingLevel: effort) == nil {
            effort = "medium"
        }
    }

    var validationError: String? {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "名前を入力してください" }
        guard !provider.isEmpty, !model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return "プロバイダーとモデルを指定してください" }
        guard ["off", "minimal", "low", "medium", "high", "xhigh", "max"].contains(effort) else { return "unsupported_reasoning_effort: \(effort)" }
        return nil
    }
}

struct SubagentSettings: Codable, Equatable, Sendable {
    var enabled = true
    /// nil explicitly inherits the parent model and effort; unavailable saved IDs stay saved.
    var defaultModelID: String? = nil
    var models: [SubagentModelProfile] = []
}

extension AppSettings {
    var subagents: SubagentSettings {
        get {
            guard let data = extraJSON.data(using: .utf8),
                  let root = try? JSONDecoder().decode([String: JSONValue].self, from: data),
                  let value = root["subagents"], let encoded = try? JSONEncoder().encode(value),
                  let settings = try? JSONDecoder().decode(SubagentSettings.self, from: encoded) else { return SubagentSettings() }
            return settings
        }
        set {
            var root = extraJSON.data(using: .utf8).flatMap { try? JSONDecoder().decode([String: JSONValue].self, from: $0) } ?? [:]
            guard let data = try? JSONEncoder().encode(newValue), let value = try? JSONDecoder().decode(JSONValue.self, from: data) else { return }
            root["subagents"] = value
            if let data = try? JSONEncoder().encode(root) { extraJSON = String(decoding: data, as: UTF8.self) }
        }
    }
}

struct SubagentRun: Codable, Sendable, Equatable, Identifiable {
    enum Status: String, Codable, Sendable { case running, completed, failed, cancelled }
    struct Event: Codable, Sendable, Equatable, Identifiable {
        var id: String
        var kind: String
        var title: String
        var detail: String
        var createdAtMs: Int64
    }
    var id: String
    var agent: String
    var task: String
    var provider: String
    var model: String
    var effort: String
    var status: Status
    var activity: String
    var startedAtMs: Int64
    var updatedAtMs: Int64
    var finishedAtMs: Int64?
    var output: String
    var outputTruncated: Bool
    var events: [Event]
    var eventsTruncated: Bool
    var usage: ProviderUsage?
    var error: String?
    var artifacts: [ToolArtifact]? = nil

    var step: ToolActivityStep {
        ToolActivityStep(id: "subagent-\(id)", round: 0, toolName: "subagent", title: agent,
            detail: activity, status: status == .running ? .running : status == .completed ? .completed : .failed,
            resultCount: nil, sources: [], errorMessage: error, createdAtMs: startedAtMs,
            durationMs: finishedAtMs.map { max(0, $0 - startedAtMs) }, subagent: self)
    }
}
