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
        ProviderDisplay(key: "GEMINI_AUTH", title: "Gemini Auth (CLI)"),
        ProviderDisplay(key: "OPENROUTER", title: "OpenRouter"),
        ProviderDisplay(key: "ZAI", title: "Z.ai"),
        ProviderDisplay(key: "MINIMAX", title: "MiniMax"),
        ProviderDisplay(key: "OPENAI", title: "OpenAI"),
        ProviderDisplay(key: "CODEX_AUTH", title: "Codex Auth"),
        ProviderDisplay(key: "OPENAI_COMPAT", title: "OpenAI (Custom)")
    ]

    static func displayName(for provider: String) -> String {
        let normalized = provider.uppercased()
        return options.first(where: { $0.key == normalized })?.title ?? options.first?.title ?? provider
    }
}
