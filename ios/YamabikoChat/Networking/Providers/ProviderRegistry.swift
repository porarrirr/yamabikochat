import Foundation

struct ProviderRegistry {
    private let openAICompatible: OpenAICompatibleProviderClient
    private let anthropicCompatible: AnthropicCompatibleProviderClient
    private let openCodeGo: OpenCodeGoProviderClient
    private let gemini: GeminiProviderClient
    private let codex: CodexProviderClient
    private let appleIntelligence: AppleIntelligenceProviderClient

    init() {
        openAICompatible = OpenAICompatibleProviderClient()
        anthropicCompatible = AnthropicCompatibleProviderClient()
        openCodeGo = OpenCodeGoProviderClient()
        gemini = GeminiProviderClient()
        codex = CodexProviderClient()
        appleIntelligence = AppleIntelligenceProviderClient()
    }

    func client(for provider: LLMProvider) -> ProviderClient {
        switch provider {
        case .gemini, .geminiAuth:
            return gemini
        case .codexAuth:
            return codex
        case .appleIntelligence:
            return appleIntelligence
        case .openCodeGo:
            return openCodeGo
        case .alibabaCodingPlan:
            return anthropicCompatible
        case .qwenCode, .openRouter, .openAI, .openAICompat, .miniMax, .zai:
            return openAICompatible
        }
    }
}
