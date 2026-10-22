import Foundation

enum AppleIntelligenceModelCatalog {
    static let displayModel = "Apple Intelligence"
    static let pccModel = "PrivateCloudComputeLanguageModel"
    static let supportedModels = [displayModel, pccModel]
    static let pccReasoningLevels = ["light", "moderate", "deep"]
    static let defaultPCCReasoningLevel = "moderate"

    static func displayName(_ model: String) -> String {
        model == pccModel ? "Private Cloud Compute" : model
    }

    static func isPCC(provider: String, model: String) -> Bool {
        ["APPLE_INTELLIGENCE", "APPLE-PCC"].contains(provider.uppercased()) && model == pccModel
    }

    static func pccReasoningLevel(forPiThinkingLevel level: String) -> String? {
        pccReasoningLevels.first { piThinkingLevel(forPCCReasoningLevel: $0) == level }
    }

    static func effortDisplayName(_ effort: String, provider: String, model: String) -> String {
        guard isPCC(provider: provider, model: model),
              let level = pccReasoningLevel(forPiThinkingLevel: effort) else { return effort }
        return level.capitalized
    }

    static func piThinkingLevel(forPCCReasoningLevel level: String) -> String? {
        ["light": "low", "moderate": "medium", "deep": "high"][level]
    }
}
