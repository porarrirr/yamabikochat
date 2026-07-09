import Foundation

enum ShortcutModelOptionsBuilder {
    static func providerOptions() -> [ProviderDisplay] {
        ProviderCatalog.options
    }

    static func modelOptions(
        provider: String,
        settings: AppSettings,
        openRouterModels: [SimpleModel]
    ) -> [String] {
        let normalizedProvider = provider.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        var options: [String] = []

        func appendUnique(_ value: String?) {
            guard let value else { return }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !options.contains(trimmed) else { return }
            options.append(trimmed)
        }

        if settings.apiProvider.uppercased() == normalizedProvider {
            appendUnique(settings.defaultModel)
        }

        appendUnique(settings.providerModelMap()[normalizedProvider])

        switch normalizedProvider {
        case "GEMINI":
            GeminiModelCatalog.suggestedModels.forEach { appendUnique($0) }
        case "OPENCODE_GO":
            OpenCodeGoModelCatalog.supportedModels.map(\.id).forEach { appendUnique($0) }
        case "SUPERGROK":
            SuperGrokModelCatalog.supportedModels.map(\.id).forEach { appendUnique($0) }
        case "CLINEPASS":
            ClinePassModelCatalog.supportedModels.forEach { appendUnique($0.id) }
        case "ALIBABA_CODING_PLAN":
            AlibabaCodingPlanModelCatalog.supportedModels.forEach { appendUnique($0) }
        case "CODEX_AUTH":
            CodexModelCatalog.visiblePresets().map(\.model).forEach { appendUnique($0) }
        case "APPLE_INTELLIGENCE":
            appendUnique(AppleIntelligenceModelCatalog.displayModel)
        case "OPENROUTER":
            if openRouterModels.isEmpty {
                openRouterFallbackModelIDs.forEach { appendUnique($0) }
            } else {
                openRouterModels.map(\.id).forEach { appendUnique($0) }
            }
        default:
            break
        }

        return options
    }

    private static let openRouterFallbackModelIDs: [String] = [
        "openai/gpt-4o",
        "anthropic/claude-3.5-sonnet",
        "meta-llama/llama-3.1-8b-instruct:free"
    ]
}
