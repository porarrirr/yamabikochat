import Foundation

struct OpenRouterModel: Codable, Sendable {
    struct Pricing: Codable, Sendable {
        var prompt: String?
        var completion: String?
        var request: String?
    }

    struct TopProvider: Codable, Sendable {
        var availableProviders: [String]?
        var availableQuantizations: [String]?

        enum CodingKeys: String, CodingKey {
            case availableProviders = "available_providers"
            case availableQuantizations = "available_quantizations"
        }
    }

    var id: String
    var name: String
    var description: String?
    var pricing: Pricing
    var contextLength: Int?
    var topProvider: TopProvider?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case pricing
        case contextLength = "context_length"
        case topProvider = "top_provider"
    }
}

struct OpenRouterModelsResponse: Codable, Sendable {
    var data: [OpenRouterModel]
}

struct SimpleModel: Codable, Sendable, Equatable, Identifiable {
    var id: String
    var name: String
    var provider: String
    var topProvider: String?
    var contextLength: Int
    var promptPricePerMillion: Double
    var completionPricePerMillion: Double
    var isFree: Bool
    var availableProviders: [String]
    var availableQuantizations: [String]

    static func fromOpenRouterModel(_ model: OpenRouterModel) -> SimpleModel {
        func parse(_ values: String?...) -> Double {
            values.compactMap { Double($0 ?? "") }.first ?? 0
        }

        let promptPerToken = parse(model.pricing.prompt, model.pricing.completion, model.pricing.request)
        let completionPerToken = parse(model.pricing.completion, model.pricing.prompt, model.pricing.request)

        return SimpleModel(
            id: model.id,
            name: model.name,
            provider: model.id.split(separator: "/").first.map(String.init) ?? "unknown",
            topProvider: model.topProvider?.availableProviders?.first,
            contextLength: model.contextLength ?? 0,
            promptPricePerMillion: promptPerToken * 1_000_000,
            completionPricePerMillion: completionPerToken * 1_000_000,
            isFree: promptPerToken == 0 && completionPerToken == 0,
            availableProviders: model.topProvider?.availableProviders ?? [],
            availableQuantizations: model.topProvider?.availableQuantizations ?? []
        )
    }
}

struct ModelEndpoint: Codable, Sendable, Equatable, Identifiable {
    var id: String { "\(name)_\(providerName ?? "")_\(quantization ?? "")" }
    var name: String
    var contextLength: Double?
    var providerName: String?
    var quantization: String?
    var maxCompletionTokens: Double?
    var maxPromptTokens: Double?
    var supportedParameters: [String]?

    enum CodingKeys: String, CodingKey {
        case name
        case contextLength = "context_length"
        case providerName = "provider_name"
        case quantization
        case maxCompletionTokens = "max_completion_tokens"
        case maxPromptTokens = "max_prompt_tokens"
        case supportedParameters = "supported_parameters"
    }
}

struct ModelEndpointsEnvelope: Codable, Sendable {
    struct DataEnvelope: Codable, Sendable {
        var endpoints: [ModelEndpoint]
    }

    var data: DataEnvelope
}

struct ProviderInfo: Codable, Sendable, Equatable, Identifiable {
    var id: String { slug }
    var name: String
    var slug: String
}

struct ProvidersResponse: Codable, Sendable {
    var data: [ProviderInfo]
}

struct ProviderDirectory: Sendable, Equatable {
    var nameToSlug: [String: String]
    var slugToName: [String: String]

    static let empty = ProviderDirectory(nameToSlug: [:], slugToName: [:])

    static func fromList(_ list: [ProviderInfo]) -> ProviderDirectory {
        let nameToSlug = Dictionary(uniqueKeysWithValues: list.map { ($0.name.lowercased(), $0.slug) })
        let slugToName = Dictionary(uniqueKeysWithValues: list.map { ($0.slug, $0.name) })
        return ProviderDirectory(nameToSlug: nameToSlug, slugToName: slugToName)
    }

    func slugForName(_ name: String?) -> String? {
        guard let name else { return nil }
        return nameToSlug[name.lowercased()]
    }

    func nameForSlug(_ slug: String?) -> String? {
        guard let slug else { return nil }
        return slugToName[slug]
    }
}