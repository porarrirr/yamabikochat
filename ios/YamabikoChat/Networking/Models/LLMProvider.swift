import Foundation

enum LLMProvider: String, Codable, CaseIterable, Sendable {
    case gemini = "GEMINI"
    case geminiAuth = "GEMINI_AUTH"
    case openRouter = "OPENROUTER"
    case openAI = "OPENAI"
    case openAICompat = "OPENAI_COMPAT"
    case miniMax = "MINIMAX"
    case codexAuth = "CODEX_AUTH"
    case zai = "ZAI"

    init(rawOrDefault value: String) {
        self = LLMProvider(rawValue: value.uppercased()) ?? .gemini
    }
}