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

enum ProviderCatalog {
    static let options: [ProviderDisplay] = [
        ProviderDisplay(key: "GEMINI", title: "Google Gemini"),
        ProviderDisplay(key: "OPENROUTER", title: "OpenRouter"),
        ProviderDisplay(key: "OPENCODE_GO", title: "OpenCode Go"),
        ProviderDisplay(key: "CLINEPASS", title: "Cline Pass"),
        ProviderDisplay(key: "ALIBABA_CODING_PLAN", title: "Alibaba Coding Plan"),
        ProviderDisplay(key: "ZAI", title: "Z.ai"),
        ProviderDisplay(key: "MINIMAX", title: "MiniMax"),
        ProviderDisplay(key: "OPENAI", title: "OpenAI"),
        ProviderDisplay(key: "CODEX_AUTH", title: "Codex Auth"),
        ProviderDisplay(key: "APPLE_INTELLIGENCE", title: "Apple Intelligence"),
        ProviderDisplay(key: "OPENAI_COMPAT", title: "OpenAI (Custom)")
    ]

    /// Providers available in dual mode and auto conversation settings (Apple Intelligence excluded).
    static let dualAutoConversationOptions: [ProviderDisplay] = options.filter {
        $0.key != "APPLE_INTELLIGENCE"
    }

    static func displayName(for provider: String) -> String {
        let normalized = provider.uppercased()
        return options.first(where: { $0.key == normalized })?.title ?? options.first?.title ?? provider
    }
}
