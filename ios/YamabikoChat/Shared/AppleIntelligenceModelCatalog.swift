import Foundation

enum AppleIntelligenceModelCatalog {
    static let displayModel = "Apple Intelligence"
    static let pccModel = "PrivateCloudComputeLanguageModel"
    static let supportedModels = [displayModel, pccModel]

    static func displayName(_ model: String) -> String {
        model == pccModel ? "Apple Intelligence — Private Cloud Compute" : model
    }
}
