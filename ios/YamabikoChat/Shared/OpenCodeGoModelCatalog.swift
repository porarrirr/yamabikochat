import Foundation

enum OpenCodeGoEndpointKind: String, Sendable {
    case chatCompletions
    case messages
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
        OpenCodeGoModel(id: "glm-5.1", displayName: "GLM-5.1", endpointKind: .chatCompletions, description: "OpenCode Go chat/completions model."),
        OpenCodeGoModel(id: "glm-5", displayName: "GLM-5", endpointKind: .chatCompletions, description: "OpenCode Go chat/completions model."),
        OpenCodeGoModel(id: "kimi-k2.6", displayName: "Kimi K2.6", endpointKind: .chatCompletions, description: "OpenCode Go chat/completions model."),
        OpenCodeGoModel(id: "kimi-k2.5", displayName: "Kimi K2.5", endpointKind: .chatCompletions, description: "OpenCode Go chat/completions model."),
        OpenCodeGoModel(id: "deepseek-v4-pro", displayName: "DeepSeek V4 Pro", endpointKind: .chatCompletions, description: "OpenCode Go chat/completions model."),
        OpenCodeGoModel(id: "deepseek-v4-flash", displayName: "DeepSeek V4 Flash", endpointKind: .chatCompletions, description: "OpenCode Go chat/completions model."),
        OpenCodeGoModel(id: "mimo-v2-pro", displayName: "MiMo-V2-Pro", endpointKind: .chatCompletions, description: "OpenCode Go chat/completions model."),
        OpenCodeGoModel(id: "mimo-v2-omni", displayName: "MiMo-V2-Omni", endpointKind: .chatCompletions, description: "OpenCode Go chat/completions model."),
        OpenCodeGoModel(id: "mimo-v2.5-pro", displayName: "MiMo-V2.5-Pro", endpointKind: .chatCompletions, description: "OpenCode Go chat/completions model."),
        OpenCodeGoModel(id: "mimo-v2.5", displayName: "MiMo-V2.5", endpointKind: .chatCompletions, description: "OpenCode Go chat/completions model."),
        OpenCodeGoModel(id: "qwen3.6-plus", displayName: "Qwen3.6 Plus", endpointKind: .messages, description: "OpenCode Go messages API model."),
        OpenCodeGoModel(id: "qwen3.5-plus", displayName: "Qwen3.5 Plus", endpointKind: .messages, description: "OpenCode Go messages API model."),
        OpenCodeGoModel(id: "minimax-m2.7", displayName: "MiniMax M2.7", endpointKind: .messages, description: "OpenCode Go messages API model."),
        OpenCodeGoModel(id: "minimax-m2.5", displayName: "MiniMax M2.5", endpointKind: .messages, description: "OpenCode Go messages API model.")
    ]

    static func normalizedModelID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("opencode-go/") {
            return String(trimmed.dropFirst("opencode-go/".count))
        }
        return trimmed
    }

    static func model(for raw: String) -> OpenCodeGoModel? {
        let normalized = normalizedModelID(raw).lowercased()
        return supportedModels.first { $0.id.lowercased() == normalized }
    }
}
