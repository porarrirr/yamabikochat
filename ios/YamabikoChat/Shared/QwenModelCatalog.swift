import Foundation

enum QwenModelCatalog {
    static let defaultModel = "coder-model"

    static let supportedModels: [String] = [
        "coder-model",
        "qwen3-coder-plus",
        "qwen3-coder-flash",
        "qwen3-max",
        "qwen-plus-latest",
        "qwen3-235b-a22b",
        "qwen-flash"
    ]
}
