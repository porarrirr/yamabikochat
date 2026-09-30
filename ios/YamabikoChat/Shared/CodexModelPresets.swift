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
    var isSupported: Bool = true
    var unsupportedReason: String? = nil
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
    static let presets: [CodexModelPreset] = [
        preset("gpt-6-sol", "GPT-6 Sol", "Complex coding and agentic workflows.", "medium", maximumEfforts, isDefault: true),
        preset("gpt-6-astra", "GPT-6 Astra", "Most capable model for complex work.", "low", maximumEfforts),
        preset("gpt-6-luna", "GPT-6 Luna", "Efficient model for focused work.", "high", maximumEfforts),
        preset("gpt-5.6-sol", "GPT-5.6 Sol", "Frontier agentic coding model.", "low", maximumEfforts),
        preset("gpt-5.6-terra", "GPT-5.6-Terra", "Balanced agentic coding model for everyday work.", "medium", maximumEfforts),
        preset("gpt-5.6-luna", "GPT-5.6-Luna", "Fast and affordable agentic coding model.", "medium", maximumEfforts),
        preset("gpt-5.5", "GPT-5.5", "Previous-generation flagship model.", "medium", modernEfforts)
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

    static func visiblePresets(from models: [PiCodexModel]) -> [CodexModelPreset] {
        models.map { model in
            let known = findPreset(model.id)
            let levels = model.supportedThinkingLevels ?? []
            return CodexModelPreset(
                model: model.id, displayName: model.name,
                description: model.reason ?? "ChatGPT account model",
                defaultReasoningEffort: levels.contains(known?.defaultReasoningEffort ?? "medium") ? known?.defaultReasoningEffort ?? "medium" : levels.first ?? "off",
                supportedReasoningEfforts: levels.map { CodexReasoningEffortPreset(effort: $0, description: "") },
                isDefault: known?.isDefault ?? false, showInPicker: true,
                isSupported: model.supported == true, unsupportedReason: model.reason
            )
        }
    }

    static func findPreset(_ model: String) -> CodexModelPreset? {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        return presets.first { $0.model.lowercased() == normalized }
    }

    static func findPreset(_ model: String, in models: [PiCodexModel]) -> CodexModelPreset? {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return visiblePresets(from: models).first { $0.model.lowercased() == normalized }
    }

    static func defaultModel() -> String { presets.first(where: \.isDefault)?.model ?? "gpt-6-sol" }

    static func resolvedReasoningEffort(_ requested: String, model: String) -> String {
        let normalized = requested.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let supported = (findPreset(model)?.supportedReasoningEfforts ?? modernEfforts).map(\.effort)
        return supported.contains(normalized) ? normalized : "medium"
    }

    static func supportsReasoningSummary(_ model: String) -> Bool {
        model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("gpt-5")
    }

    static func supportsTextVerbosity(_ model: String) -> Bool {
        model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("gpt-5")
    }
}
