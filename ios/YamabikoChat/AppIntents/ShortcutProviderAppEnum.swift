import AppIntents
import Foundation

enum ShortcutProviderAppEnum: String, AppEnum {
    case gemini = "GEMINI"
    case openRouter = "OPENROUTER"
    case openCodeGo = "OPENCODE_GO"
    case superGrok = "SUPERGROK"
    case clinePass = "CLINEPASS"
    case alibabaCodingPlan = "ALIBABA_CODING_PLAN"
    case zai = "ZAI"
    case miniMax = "MINIMAX"
    case openAI = "OPENAI"
    case codexAuth = "CODEX_AUTH"
    case appleIntelligence = "APPLE_INTELLIGENCE"
    case openAICompat = "OPENAI_COMPAT"

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: LocalizedStringResource("Shortcuts: プロバイダ"))

    static var caseDisplayRepresentations: [ShortcutProviderAppEnum: DisplayRepresentation] = [
        .gemini: DisplayRepresentation(title: "Google Gemini"),
        .openRouter: DisplayRepresentation(title: "OpenRouter"),
        .openCodeGo: DisplayRepresentation(title: "OpenCode Go"),
        .superGrok: DisplayRepresentation(title: "SuperGrok"),
        .clinePass: DisplayRepresentation(title: "Cline Pass"),
        .alibabaCodingPlan: DisplayRepresentation(title: "Alibaba Coding Plan"),
        .zai: DisplayRepresentation(title: "Z.ai"),
        .miniMax: DisplayRepresentation(title: "MiniMax"),
        .openAI: DisplayRepresentation(title: "OpenAI"),
        .codexAuth: DisplayRepresentation(title: "Codex Auth"),
        .appleIntelligence: DisplayRepresentation(title: "Apple Intelligence"),
        .openAICompat: DisplayRepresentation(title: "OpenAI (Custom)")
    ]

    var providerKey: String { rawValue }
}
