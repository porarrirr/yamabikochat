import Foundation

enum OpenCodeGoEndpointKind: String, Sendable {
    case chatCompletions
    case responses
    case messages

    var piAPI: String {
        switch self {
        case .chatCompletions: "openai-completions"
        case .responses: "openai-responses"
        case .messages: "anthropic-messages"
        }
    }
}

struct OpenCodeGoModel: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let endpointKind: OpenCodeGoEndpointKind
    let description: String
}

enum OpenCodeGoModelCatalog {
    static let defaultModel = "glm-5.1"

    static let supportedModels: [OpenCodeGoModel] = [
        OpenCodeGoModel(id: "grok-4.6", displayName: "Grok 4.6", endpointKind: .responses, description: "OpenCode Go Responses API model."),
        OpenCodeGoModel(id: "gpt-5.6-luna", displayName: "GPT-5.6 Luna", endpointKind: .responses, description: "OpenCode Go Responses API model."),
        OpenCodeGoModel(id: "glm-5.3-flash", displayName: "GLM-5.3 Flash", endpointKind: .chatCompletions, description: "OpenCode Go chat/completions model."),
        OpenCodeGoModel(id: "glm-5.3", displayName: "GLM-5.3", endpointKind: .chatCompletions, description: "OpenCode Go chat/completions model."),
        OpenCodeGoModel(id: "glm-5.2", displayName: "GLM-5.2", endpointKind: .chatCompletions, description: "OpenCode Go chat/completions model."),
        OpenCodeGoModel(id: "glm-5.1", displayName: "GLM-5.1", endpointKind: .chatCompletions, description: "OpenCode Go chat/completions model."),
        OpenCodeGoModel(id: "kimi-k3", displayName: "Kimi K3", endpointKind: .chatCompletions, description: "OpenCode Go chat/completions model."),
        OpenCodeGoModel(id: "kimi-k2.7-code", displayName: "Kimi K2.7 Code", endpointKind: .chatCompletions, description: "OpenCode Go chat/completions model."),
        OpenCodeGoModel(id: "kimi-k2.6", displayName: "Kimi K2.6", endpointKind: .chatCompletions, description: "OpenCode Go chat/completions model."),
        OpenCodeGoModel(id: "longcat-2.0", displayName: "LongCat 2.0", endpointKind: .chatCompletions, description: "OpenCode Go chat/completions model."),
        OpenCodeGoModel(id: "deepseek-v4-pro", displayName: "DeepSeek V4 Pro", endpointKind: .chatCompletions, description: "OpenCode Go chat/completions model."),
        OpenCodeGoModel(id: "deepseek-v4-flash", displayName: "DeepSeek V4 Flash", endpointKind: .chatCompletions, description: "OpenCode Go chat/completions model."),
        OpenCodeGoModel(id: "deepseek-v4-flash-vision-exp", displayName: "DeepSeek V4 Flash Vision Exp", endpointKind: .chatCompletions, description: "OpenCode Go chat/completions model."),
        OpenCodeGoModel(id: "mimo-v2.5-pro", displayName: "MiMo-V2.5-Pro", endpointKind: .chatCompletions, description: "OpenCode Go chat/completions model."),
        OpenCodeGoModel(id: "mimo-v2.5", displayName: "MiMo-V2.5", endpointKind: .chatCompletions, description: "OpenCode Go chat/completions model."),
        OpenCodeGoModel(id: "hy3", displayName: "HY 3", endpointKind: .chatCompletions, description: "OpenCode Go chat/completions model."),
        OpenCodeGoModel(id: "qwen3.8-max", displayName: "Qwen3.8 Max", endpointKind: .messages, description: "OpenCode Go messages API model."),
        OpenCodeGoModel(id: "qwen3.7-max", displayName: "Qwen3.7 Max", endpointKind: .messages, description: "OpenCode Go messages API model."),
        OpenCodeGoModel(id: "qwen3.7-plus", displayName: "Qwen3.7 Plus", endpointKind: .messages, description: "OpenCode Go messages API model."),
        OpenCodeGoModel(id: "qwen3.6-plus", displayName: "Qwen3.6 Plus", endpointKind: .messages, description: "OpenCode Go messages API model."),
        OpenCodeGoModel(id: "minimax-m3", displayName: "MiniMax M3", endpointKind: .messages, description: "OpenCode Go messages API model."),
        OpenCodeGoModel(id: "minimax-m2.7", displayName: "MiniMax M2.7", endpointKind: .messages, description: "OpenCode Go messages API model."),
        OpenCodeGoModel(id: "minimax-m2.5", displayName: "MiniMax M2.5", endpointKind: .messages, description: "OpenCode Go messages API model."),
        OpenCodeGoModel(id: "muse-spark-1.2-contributor", displayName: "Muse Spark 1.2 Contributor", endpointKind: .responses, description: "OpenCode Go Responses API model.")
    ]

    static func normalizedModelID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("opencode-go/") {
            return normalizedModelID(String(trimmed.dropFirst("opencode-go/".count)))
        }
        if lower == "muse-spark-1.2" { return "muse-spark-1.2-contributor" }
        return trimmed
    }

    static func model(for raw: String) -> OpenCodeGoModel? {
        let normalized = normalizedModelID(raw).lowercased()
        return supportedModels.first { $0.id.lowercased() == normalized }
    }
}
