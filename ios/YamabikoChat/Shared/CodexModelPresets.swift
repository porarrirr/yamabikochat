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

/// ChatGPT plan model options are driven by the live account catalog (`PiCodexModel`)
/// returned by the Pi runtime. models.dev supplies the execution contract for account
/// slugs the bundled Pi release does not ship as built-ins.
enum CodexModelCatalog {
    /// Builds the models.dev contracts the Pi runtime uses to supplement account slugs
    /// that are not Pi built-ins. Keys are the catalog model IDs.
    static func modelsDevContracts(from provider: CatalogProvider?) -> [String: PiCatalogModelContract] {
        guard let provider else { return [:] }
        var contracts: [String: PiCatalogModelContract] = [:]
        for model in provider.models {
            contracts[model.id] = PiCatalogModelContract(
                providerName: provider.name,
                npm: model.providerContract?.npm,
                api: model.providerContract?.api,
                shape: model.providerContract?.shape,
                toolCall: model.toolCall,
                provenance: model.providerContract?.provenance,
                name: model.name,
                reasoning: model.reasoning,
                input: model.inputModalities,
                contextWindow: model.limits.context,
                maxTokens: model.limits.output,
                reasoningEfforts: model.supportedReasoningEfforts
            )
        }
        return contracts
    }

    static func visiblePresets(from models: [PiCodexModel]) -> [CodexModelPreset] {
        let defaultID = defaultModel()
        return models.map { model in
            let levels = model.supportedThinkingLevels ?? []
            return CodexModelPreset(
                model: model.id, displayName: model.name,
                description: model.reason ?? "ChatGPT account model",
                defaultReasoningEffort: levels.contains("medium") ? "medium" : levels.first ?? "off",
                supportedReasoningEfforts: levels.map { CodexReasoningEffortPreset(effort: $0, description: "") },
                isDefault: model.id == defaultID, showInPicker: true,
                isSupported: model.supported == true, unsupportedReason: model.reason
            )
        }
    }

    static func findPreset(_ model: String, in models: [PiCodexModel]) -> CodexModelPreset? {
        let normalized = model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return visiblePresets(from: models).first { $0.model.lowercased() == normalized }
    }

    /// Only the initial default for new settings; a saved model is never auto-replaced.
    static func defaultModel() -> String { "gpt-6.1-sol" }

    static func resolvedReasoningEffort(_ requested: String, model: String, models: [PiCodexModel]) -> String {
        let normalized = requested.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        // Pi clamps the requested level against the exact model metadata when the
        // account catalog has not been fetched yet.
        guard let preset = findPreset(model, in: models) else { return normalized }
        if preset.supportedReasoningEfforts.contains(where: { $0.effort == normalized }) {
            return normalized
        }
        DiagnosticsLogger.log(
            "ChatGPT reasoning effort adjusted to the account model's supported levels",
            category: .settings,
            metadata: [
                "model": model,
                "requested": normalized,
                "resolved": preset.defaultReasoningEffort
            ]
        )
        return preset.defaultReasoningEffort
    }

    static func supportsReasoningSummary(_ model: String) -> Bool {
        model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("gpt-5")
    }

    static func supportsTextVerbosity(_ model: String) -> Bool {
        model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("gpt-5")
    }
}
