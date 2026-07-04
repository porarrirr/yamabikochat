import Foundation

struct ClinePassModel: Identifiable, Equatable, Sendable {
    let id: String
    let displayName: String
    let description: String
}

enum ClinePassModelCatalog {
    static let defaultModel = "cline-pass/glm-5.2"

    static let supportedModels: [ClinePassModel] = [
        ClinePassModel(id: "cline-pass/glm-5.2", displayName: "GLM 5.2", description: "Cline Pass chat/completions model."),
        ClinePassModel(id: "cline-pass/kimi-k2.7-code", displayName: "Kimi K2.7 Code", description: "Cline Pass chat/completions model."),
        ClinePassModel(id: "cline-pass/kimi-k2.6", displayName: "Kimi K2.6", description: "Cline Pass chat/completions model."),
        ClinePassModel(id: "cline-pass/deepseek-v4-pro", displayName: "DeepSeek V4 Pro", description: "Cline Pass chat/completions model."),
        ClinePassModel(id: "cline-pass/deepseek-v4-flash", displayName: "DeepSeek V4 Flash", description: "Cline Pass chat/completions model."),
        ClinePassModel(id: "cline-pass/mimo-v2.5", displayName: "MiMo V2.5", description: "Cline Pass chat/completions model."),
        ClinePassModel(id: "cline-pass/mimo-v2.5-pro", displayName: "MiMo V2.5 Pro", description: "Cline Pass chat/completions model."),
        ClinePassModel(id: "cline-pass/minimax-m3", displayName: "MiniMax M3", description: "Cline Pass chat/completions model."),
        ClinePassModel(id: "cline-pass/qwen3.7-max", displayName: "Qwen3.7 Max", description: "Cline Pass chat/completions model."),
        ClinePassModel(id: "cline-pass/qwen3.7-plus", displayName: "Qwen3.7 Plus", description: "Cline Pass chat/completions model.")
    ]

    static func normalizedModelID(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()
        if lower.hasPrefix("cline-pass/") {
            return trimmed
        }
        if trimmed.isEmpty {
            return trimmed
        }
        return "cline-pass/\(trimmed)"
    }

    static func model(for raw: String) -> ClinePassModel? {
        let normalized = normalizedModelID(raw).lowercased()
        return supportedModels.first { $0.id.lowercased() == normalized }
    }
}