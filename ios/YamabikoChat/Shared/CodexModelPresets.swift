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
    private static let modernEfforts = [
        CodexReasoningEffortPreset(effort: "low", description: "Fast responses with lighter reasoning"),
        CodexReasoningEffortPreset(effort: "medium", description: "Balances speed and reasoning depth for everyday tasks"),
        CodexReasoningEffortPreset(effort: "high", description: "Greater reasoning depth for complex problems"),
        CodexReasoningEffortPreset(effort: "xhigh", description: "Extra high reasoning depth for complex problems")
    ]
    private static let maximumEfforts = modernEfforts + [
        CodexReasoningEffortPreset(effort: "max", description: "Maximum reasoning depth for the hardest problems")
    ]
    private static let delegatedEfforts = maximumEfforts + [
        CodexReasoningEffortPreset(effort: "ultra", description: "Maximum reasoning with automatic task delegation")
    ]
    private static let legacyEfforts = [
        CodexReasoningEffortPreset(effort: "low", description: "Balances speed with some reasoning; useful for straightforward queries and short explanations"),
        CodexReasoningEffortPreset(effort: "medium", description: "Provides a solid balance of reasoning depth and latency for general-purpose tasks"),
        CodexReasoningEffortPreset(effort: "high", description: "Maximizes reasoning depth for complex or ambiguous problems"),
        CodexReasoningEffortPreset(effort: "xhigh", description: "Extra high reasoning for complex problems")
    ]

    static let presets: [CodexModelPreset] = [
        preset("gpt-5.6-sol", "GPT-5.6-Sol", "Latest frontier agentic coding model.", "low", delegatedEfforts, isDefault: true),
        preset("gpt-5.6-terra", "GPT-5.6-Terra", "Balanced agentic coding model for everyday work.", "medium", delegatedEfforts),
        preset("gpt-5.6-luna", "GPT-5.6-Luna", "Fast and affordable agentic coding model.", "medium", maximumEfforts),
        preset("gpt-5.5", "GPT-5.5", "Frontier model for complex coding, research, and real-world work.", "medium", modernEfforts),
        preset("gpt-5.4", "GPT-5.4", "Strong model for everyday coding.", "medium", modernEfforts),
        preset("gpt-5.4-mini", "GPT-5.4-Mini", "Small, fast, and cost-efficient model for simpler coding tasks.", "medium", modernEfforts),
        preset("gpt-5.2", "GPT-5.2", "Optimized for professional work and long-running agents.", "medium", legacyEfforts)
    ]

    private static func preset(
        _ model: String,
        _ displayName: String,
        _ description: String,
        _ defaultEffort: String,
        _ efforts: [CodexReasoningEffortPreset],
        isDefault: Bool = false
    ) -> CodexModelPreset {
        CodexModelPreset(
            model: model,
            displayName: displayName,
            description: description,
            defaultReasoningEffort: defaultEffort,
            supportedReasoningEfforts: efforts,
            isDefault: isDefault,
            showInPicker: true
        )
    }

    static func visiblePresets() -> [CodexModelPreset] { presets.filter(\.showInPicker) }

    static func findPreset(_ model: String) -> CodexModelPreset? {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return presets.first { $0.model.lowercased() == normalized }
    }

    static func defaultModel() -> String { presets.first(where: \.isDefault)?.model ?? "gpt-5.6-sol" }

    static func supportsReasoningSummary(_ model: String) -> Bool {
        model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("gpt-5")
    }

    static func supportsTextVerbosity(_ model: String) -> Bool {
        model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("gpt-5")
    }
}
