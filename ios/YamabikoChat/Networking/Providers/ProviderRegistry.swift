import Foundation

struct ProviderRegistry {
    private let openAICompatible: OpenAICompatibleProviderClient
    private let gemini: GeminiProviderClient
    private let codex: CodexProviderClient

    init() {
        openAICompatible = OpenAICompatibleProviderClient()
        gemini = GeminiProviderClient()
        codex = CodexProviderClient()
    }

    func client(for provider: LLMProvider) -> ProviderClient {
        switch provider {
        case .gemini, .geminiAuth:
            return gemini
        case .codexAuth:
            return codex
        case .openRouter, .alibabaCodingPlan, .openAI, .openAICompat, .miniMax, .zai:
            return openAICompatible
        }
    }
}
