import Foundation

enum AppleIntelligenceModelCatalog {
    static let displayModel = "Apple Intelligence"
    static let pccModel = "PrivateCloudComputeLanguageModel"
    static let supportedModels = [displayModel, pccModel]
    static let pccReasoningLevels = ["light", "moderate", "deep"]
    static let defaultPCCReasoningLevel = "moderate"

    static func displayName(_ model: String) -> String {
        model == pccModel ? "Apple Intelligence — Private Cloud Compute" : model
    }

    static func piThinkingLevel(forPCCReasoningLevel level: String) -> String? {
        ["light": "low", "moderate": "medium", "deep": "high"][level]
    }
}
