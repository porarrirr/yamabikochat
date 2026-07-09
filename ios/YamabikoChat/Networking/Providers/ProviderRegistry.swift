import Foundation

struct ProviderRegistry {
    private let openAICompatible: OpenAICompatibleProviderClient
    private let anthropicCompatible: AnthropicCompatibleProviderClient
    private let openCodeGo: OpenCodeGoProviderClient
    private let gemini: GeminiProviderClient
    private let codex: CodexProviderClient
    private let superGrok: SuperGrokProviderClient
    private let appleIntelligence: AppleIntelligenceProviderClient

    init() {
        openAICompatible = OpenAICompatibleProviderClient()
        anthropicCompatible = AnthropicCompatibleProviderClient()
        openCodeGo = OpenCodeGoProviderClient()
        gemini = GeminiProviderClient()
        codex = CodexProviderClient()
        superGrok = SuperGrokProviderClient()
        appleIntelligence = AppleIntelligenceProviderClient()
    }

    func client(for provider: LLMProvider) -> ProviderClient {
        switch provider {
        case .gemini:
            return gemini
        case .codexAuth:
            return codex
        case .superGrok:
            return superGrok
        case .appleIntelligence:
            return appleIntelligence
        case .openCodeGo:
            return openCodeGo
        case .alibabaCodingPlan:
            return anthropicCompatible
        case .openRouter, .openAI, .openAICompat, .miniMax, .zai, .clinePass:
            return openAICompatible
        }
    }
}
