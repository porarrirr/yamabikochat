import Foundation

struct CodexReasoningEffortPreset: Identifiable, Equatable, Sendable {
    var id: String { effort }
    let effort: String
    let description: String
}

struct CodexModelPreset: Identifiable, Equatable, Sendable {
    var id: String { model }
    let model: String
    let displayName: String
    let description: String
    let defaultReasoningEffort: String
    let supportedReasoningEfforts: [CodexReasoningEffortPreset]
    let isDefault: Bool
    let showInPicker: Bool
}

enum CodexModelCatalog {
    static let presets: [CodexModelPreset] = [
        CodexModelPreset(
            model: "gpt-5.4",
            displayName: "gpt-5.4",
            description: "Frontier model with strong knowledge, reasoning, and coding.",
            defaultReasoningEffort: "medium",
            supportedReasoningEfforts: [
                CodexReasoningEffortPreset(effort: "low", description: "Balances speed with some reasoning; useful for straightforward queries and short explanations"),
                CodexReasoningEffortPreset(effort: "medium", description: "Provides a solid balance of reasoning depth and latency for general-purpose tasks"),
                CodexReasoningEffortPreset(effort: "high", description: "Maximizes reasoning depth for complex or ambiguous problems"),
                CodexReasoningEffortPreset(effort: "xhigh", description: "Extra high reasoning depth for complex problems")
            ],
            isDefault: false,
            showInPicker: true
        ),
        CodexModelPreset(
            model: "gpt-5.5",
            displayName: "gpt-5.5",
            description: "Latest frontier model with improvements across knowledge, reasoning, and coding.",
            defaultReasoningEffort: "medium",
            supportedReasoningEfforts: [
                CodexReasoningEffortPreset(effort: "low", description: "Balances speed with some reasoning; useful for straightforward queries and short explanations"),
                CodexReasoningEffortPreset(effort: "medium", description: "Provides a solid balance of reasoning depth and latency for general-purpose tasks"),
                CodexReasoningEffortPreset(effort: "high", description: "Maximizes reasoning depth for complex or ambiguous problems"),
                CodexReasoningEffortPreset(effort: "xhigh", description: "Extra high reasoning depth for complex problems")
            ],
            isDefault: true,
            showInPicker: true
        ),
        CodexModelPreset(
            model: "gpt-5.3-codex-spark",
            displayName: "gpt-5.3-codex-spark",
            description: "Codex Spark model optimized for faster coding assistance.",
            defaultReasoningEffort: "medium",
            supportedReasoningEfforts: [
                CodexReasoningEffortPreset(effort: "medium", description: "Dynamically adjusts reasoning based on the task"),
                CodexReasoningEffortPreset(effort: "high", description: "Maximizes reasoning depth for complex or ambiguous problems")
            ],
            isDefault: false,
            showInPicker: true
        ),
        CodexModelPreset(
            model: "gpt-5.4-mini",
            displayName: "gpt-5.4-mini",
            description: "Optimized for codex. Cheaper, faster, but less capable.",
            defaultReasoningEffort: "medium",
            supportedReasoningEfforts: [
                CodexReasoningEffortPreset(effort: "medium", description: "Dynamically adjusts reasoning based on the task"),
                CodexReasoningEffortPreset(effort: "high", description: "Maximizes reasoning depth for complex or ambiguous problems")
            ],
            isDefault: false,
            showInPicker: true
        )
    ]

    static func visiblePresets() -> [CodexModelPreset] {
        presets.filter(\.showInPicker)
    }

    static func findPreset(_ model: String) -> CodexModelPreset? {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return presets.first { $0.model.lowercased() == normalized }
    }

    static func defaultModel() -> String {
        presets.first(where: \.isDefault)?.model ?? "gpt-5.5"
    }

    static func supportsReasoningSummary(_ model: String) -> Bool {
        model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("gpt-5")
    }

    static func supportsTextVerbosity(_ model: String) -> Bool {
        model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("gpt-5")
    }
}
