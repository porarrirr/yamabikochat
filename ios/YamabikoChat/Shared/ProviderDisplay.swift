import Foundation

struct ProviderDisplay: Identifiable, Equatable, Sendable {
    let id: String
    let key: String
    let title: String

    init(key: String, title: String) {
        self.id = key
        self.key = key
        self.title = title
    }
}

enum ZAICodingPlanModelCatalog {
    static let defaultModel = "glm-5.2"
    static let supportedModels = [
        "glm-5.2",
        "glm-5-turbo",
        "glm-4.7"
    ]

    static func isSupported(_ model: String) -> Bool {
        supportedModels.contains { $0.caseInsensitiveCompare(model.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame }
    }

    static func migrateLegacyModel(_ model: String) -> String {
        model.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("glm-5.1") == .orderedSame
            ? defaultModel
            : model
    }
}

enum ProviderCatalog {
    /// Providers implemented directly by YamabikoChat. Other API providers are supplied by models.dev.
    static let options: [ProviderDisplay] = [
        ProviderDisplay(key: "GEMINI", title: "Google Gemini"),
        ProviderDisplay(key: "OPENROUTER", title: "OpenRouter"),
        ProviderDisplay(key: "CODEX_AUTH", title: "Codex Auth"),
        ProviderDisplay(key: "SUPERGROK", title: "SuperGrok"),
        ProviderDisplay(key: "APPLE_INTELLIGENCE", title: "Apple Intelligence")
    ]

    /// Providers available in dual mode and auto conversation settings (Apple Intelligence excluded).
    static let dualAutoConversationOptions: [ProviderDisplay] = options.filter {
        $0.key != "APPLE_INTELLIGENCE"
    }

    static func displayName(for provider: String) -> String {
        let normalized = provider.uppercased()
        if let builtIn = options.first(where: { $0.key == normalized }) {
            return builtIn.title
        }
        if let modelsDevID = ProviderReference(persistedID: provider).modelsDevID {
            return modelsDevID
        }
        return provider
    }

    static func defaultModel(for provider: String) -> String {
        switch provider.uppercased() {
        case "GEMINI": "gemini-2.5-flash"
        case "OPENROUTER": "deepseek/deepseek-chat"
        case "OPENCODE_GO": OpenCodeGoModelCatalog.defaultModel
        case "SUPERGROK": SuperGrokModelCatalog.defaultModel
        case "CLINEPASS": ClinePassModelCatalog.defaultModel
        case "ALIBABA_CODING_PLAN": AlibabaCodingPlanModelCatalog.defaultModel
        case "ZAI": ZAICodingPlanModelCatalog.defaultModel
        case "MINIMAX": "MiniMax-M2.1"
        case "OPENAI": "gpt-4.1-mini"
        case "CODEX_AUTH": CodexModelCatalog.defaultModel()
        case "APPLE_INTELLIGENCE": AppleIntelligenceModelCatalog.displayModel
        default: ""
        }
    }

    static func constrainedModelIDs(for provider: String) -> [String]? {
        switch provider.uppercased() {
        case "OPENCODE_GO": OpenCodeGoModelCatalog.supportedModels.map(\.id)
        case "CLINEPASS": ClinePassModelCatalog.supportedModels.map(\.id)
        case "ALIBABA_CODING_PLAN": AlibabaCodingPlanModelCatalog.supportedModels
        case "ZAI": ZAICodingPlanModelCatalog.supportedModels
        default: nil
        }
    }

    static func migrateLegacyModelID(_ model: String, for provider: String) -> String {
        switch provider.uppercased() {
        case "ZAI": ZAICodingPlanModelCatalog.migrateLegacyModel(model)
        case "OPENCODE_GO": OpenCodeGoModelCatalog.normalizedModelID(model)
        default: model
        }
    }
}
