import Foundation

enum LLMProvider: String, Codable, CaseIterable, Sendable {
    case gemini = "GEMINI"
    case geminiAuth = "GEMINI_AUTH"
    case qwenCode = "QWEN_CODE"
    case openRouter = "OPENROUTER"
    case alibabaCodingPlan = "ALIBABA_CODING_PLAN"
    case openAI = "OPENAI"
    case openAICompat = "OPENAI_COMPAT"
    case miniMax = "MINIMAX"
    case codexAuth = "CODEX_AUTH"
    case zai = "ZAI"

    init(rawOrDefault value: String) {
        self = LLMProvider(rawValue: value.uppercased()) ?? .gemini
    }
}
