import Foundation

enum LLMProvider: String, Codable, CaseIterable, Sendable {
    case gemini = "GEMINI"
    case openRouter = "OPENROUTER"
    case openCodeGo = "OPENCODE_GO"
    case clinePass = "CLINEPASS"
    case alibabaCodingPlan = "ALIBABA_CODING_PLAN"
    case openAI = "OPENAI"
    case openAICompat = "OPENAI_COMPAT"
    case miniMax = "MINIMAX"
    case codexAuth = "CODEX_AUTH"
    case superGrok = "SUPERGROK"
    case zai = "ZAI"
    case appleIntelligence = "APPLE_INTELLIGENCE"

    init(rawOrDefault value: String) {
        switch value.uppercased() {
        case "GEMINI_AUTH":
            self = .gemini
        case "QWEN_CODE":
            self = .openRouter
        default:
            self = LLMProvider(rawValue: value.uppercased()) ?? .gemini
        }
    }

    var supportsClientWebSearchTool: Bool {
        self != .appleIntelligence
    }
}
