import Foundation

struct ProviderRegistry {
    private let openAICompatible: OpenAICompatibleProviderClient
    private let anthropicCompatible: AnthropicCompatibleProviderClient
    private let gemini: GeminiProviderClient
    private let codex: CodexProviderClient

    init() {
        openAICompatible = OpenAICompatibleProviderClient()
        anthropicCompatible = AnthropicCompatibleProviderClient()
        gemini = GeminiProviderClient()
        codex = CodexProviderClient()
    }

    func client(for provider: LLMProvider) -> ProviderClient {
        switch provider {
        case .gemini, .geminiAuth:
            return gemini
        case .codexAuth:
            return codex
        case .alibabaCodingPlan:
            return anthropicCompatible
        case .openRouter, .openAI, .openAICompat, .miniMax, .zai:
            return openAICompatible
        }
    }
}
