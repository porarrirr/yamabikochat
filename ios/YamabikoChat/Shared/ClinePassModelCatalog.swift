import Foundation

struct ClinePassModel: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let description: String
}

enum ClinePassModelCatalog {
    static let defaultModel = "cline-pass/glm-5.2"

    static let supportedModels: [ClinePassModel] = [
        ClinePassModel(id: "cline-pass/glm-5.2", displayName: "GLM 5.2", description: "ClinePass chat/completions model."),
        ClinePassModel(id: "cline-pass/kimi-k3", displayName: "Kimi K3", description: "ClinePass chat/completions model."),
        ClinePassModel(id: "cline-pass/kimi-k2.7-code", displayName: "Kimi K2.7 Code", description: "ClinePass chat/completions model."),
        ClinePassModel(id: "cline-pass/kimi-k2.6", displayName: "Kimi K2.6", description: "ClinePass chat/completions model."),
        ClinePassModel(id: "cline-pass/deepseek-v4-pro", displayName: "DeepSeek V4 Pro", description: "ClinePass chat/completions model."),
        ClinePassModel(id: "cline-pass/deepseek-v4-flash", displayName: "DeepSeek V4 Flash", description: "ClinePass chat/completions model."),
        ClinePassModel(id: "cline-pass/mimo-v2.5", displayName: "MiMo V2.5", description: "ClinePass chat/completions model."),
        ClinePassModel(id: "cline-pass/mimo-v2.5-pro", displayName: "MiMo V2.5 Pro", description: "ClinePass chat/completions model."),
        ClinePassModel(id: "cline-pass/minimax-m3", displayName: "MiniMax M3", description: "ClinePass chat/completions model."),
        ClinePassModel(id: "cline-pass/qwen3.7-max", displayName: "Qwen3.7 Max", description: "ClinePass chat/completions model."),
        ClinePassModel(id: "cline-pass/qwen3.7-plus", displayName: "Qwen3.7 Plus", description: "ClinePass chat/completions model.")
    ]

    static func normalizedModelID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("cline-pass/") || trimmed.isEmpty {
            return trimmed
        }
        return "cline-pass/\(trimmed)"
    }

    static func model(for raw: String) -> ClinePassModel? {
        let normalized = normalizedModelID(raw).lowercased()
        return supportedModels.first { $0.id.lowercased() == normalized }
    }
}
