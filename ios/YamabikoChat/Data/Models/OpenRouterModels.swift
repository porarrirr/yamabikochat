import Foundation

struct OpenRouterReasoningCapabilities: Codable, Sendable, Equatable {
    static let gatewayEfforts = ["max", "xhigh", "high", "medium", "low", "minimal", "none"]

    var supportedEfforts: [String]?
    var exposesEffortSelection: Bool
    var defaultEffort: String?
    var defaultEnabled: Bool?
    var supportsMaxTokens: Bool
    var mandatory: Bool

    init(
        supportedEfforts: [String]? = nil,
        exposesEffortSelection: Bool = false,
        defaultEffort: String? = nil,
        defaultEnabled: Bool? = nil,
        supportsMaxTokens: Bool = false,
        mandatory: Bool = false
    ) {
        self.supportedEfforts = supportedEfforts
        self.exposesEffortSelection = exposesEffortSelection
        self.defaultEffort = defaultEffort
        self.defaultEnabled = defaultEnabled
        self.supportsMaxTokens = supportsMaxTokens
        self.mandatory = mandatory
    }

    var selectableEfforts: [String] {
        guard exposesEffortSelection else { return [] }
        let source = supportedEfforts ?? Self.gatewayEfforts
        var seen: Set<String> = []
        return source
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { effort in
                guard !effort.isEmpty, seen.insert(effort).inserted else { return false }
                return !mandatory || effort != "none"
            }
    }

    enum CodingKeys: String, CodingKey {
        case supportedEfforts = "supported_efforts"
        case defaultEffort = "default_effort"
        case defaultEnabled = "default_enabled"
        case supportsMaxTokens = "supports_max_tokens"
        case mandatory
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        exposesEffortSelection = container.contains(.supportedEfforts)
        supportedEfforts = try container.decodeIfPresent([String].self, forKey: .supportedEfforts)
        defaultEffort = try container.decodeIfPresent(String.self, forKey: .defaultEffort)
        defaultEnabled = try container.decodeIfPresent(Bool.self, forKey: .defaultEnabled)
        supportsMaxTokens = try container.decodeIfPresent(Bool.self, forKey: .supportsMaxTokens) ?? false
        mandatory = try container.decodeIfPresent(Bool.self, forKey: .mandatory) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        if exposesEffortSelection {
            if let supportedEfforts {
                try container.encode(supportedEfforts, forKey: .supportedEfforts)
            } else {
                try container.encodeNil(forKey: .supportedEfforts)
            }
        }
        try container.encodeIfPresent(defaultEffort, forKey: .defaultEffort)
        try container.encodeIfPresent(defaultEnabled, forKey: .defaultEnabled)
        if supportsMaxTokens {
            try container.encode(true, forKey: .supportsMaxTokens)
        }
        if mandatory {
            try container.encode(true, forKey: .mandatory)
        }
    }
}

struct OpenRouterModel: Codable, Sendable {
    struct Pricing: Codable, Sendable, Equatable {
        var prompt: String?
        var completion: String?
        var request: String?
        var inputCacheRead: String? = nil

        enum CodingKeys: String, CodingKey {
            case prompt
            case completion
            case request
            case inputCacheRead = "input_cache_read"
        }
    }

    struct TopProvider: Codable, Sendable {
        var availableProviders: [String]?
        var availableQuantizations: [String]?
        var maxCompletionTokens: Int?

        enum CodingKeys: String, CodingKey {
            case availableProviders = "available_providers"
            case availableQuantizations = "available_quantizations"
            case maxCompletionTokens = "max_completion_tokens"
        }
    }

    struct Architecture: Codable, Sendable {
        var inputModalities: [String]?
        var outputModalities: [String]?

        enum CodingKeys: String, CodingKey {
            case inputModalities = "input_modalities"
            case outputModalities = "output_modalities"
        }
    }

    var id: String
    var name: String
    var description: String?
    var pricing: Pricing
    var contextLength: Int?
    var topProvider: TopProvider?
    var reasoning: OpenRouterReasoningCapabilities? = nil
    var architecture: Architecture? = nil
    var supportedParameters: [String]? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case pricing
        case contextLength = "context_length"
        case topProvider = "top_provider"
        case reasoning
        case architecture
        case supportedParameters = "supported_parameters"
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
    var reasoning: OpenRouterReasoningCapabilities? = nil
    var inputModalities: [String] = []
    var outputModalities: [String] = []
    var maxCompletionTokens: Int? = nil
    var supportsTools: Bool = false
    var supportsReasoning: Bool = false

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
            availableQuantizations: model.topProvider?.availableQuantizations ?? [],
            reasoning: model.reasoning,
            inputModalities: model.architecture?.inputModalities ?? [],
            outputModalities: model.architecture?.outputModalities ?? [],
            maxCompletionTokens: model.topProvider?.maxCompletionTokens,
            supportsTools: model.supportedParameters?.contains("tools") == true,
            supportsReasoning: model.reasoning != nil || (model.supportedParameters ?? []).contains {
                ["include_reasoning", "reasoning", "reasoning_effort"].contains($0)
            }
        )
    }
}

extension SimpleModel {
    func matchesSearchQuery(_ query: String) -> Bool {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else { return true }

        let searchTerms = Self.normalizedSearchText(trimmedQuery).split(separator: " ")
        guard !searchTerms.isEmpty else { return false }

        let searchableFields = [id, name, provider].map(Self.normalizedSearchText)
        return searchTerms.allSatisfy { term in
            searchableFields.contains { field in
                field.contains(term) || field.replacingOccurrences(of: " ", with: "").contains(term)
            }
        }
    }

    private static func normalizedSearchText(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? String($0) : " " }
            .joined()
    }
}

struct ModelEndpoint: Codable, Sendable, Equatable, Identifiable {
    var id: String { tag ?? "\(name)_\(providerName ?? "")_\(quantization ?? "")" }
    var name: String
    var contextLength: Double?
    var providerName: String?
    var tag: String?
    var quantization: String?
    var maxCompletionTokens: Double?
    var maxPromptTokens: Double?
    var supportedParameters: [String]?
    var status: Int?
    var pricing: OpenRouterModel.Pricing?

    enum CodingKeys: String, CodingKey {
        case name
        case contextLength = "context_length"
        case providerName = "provider_name"
        case tag
        case quantization
        case maxCompletionTokens = "max_completion_tokens"
        case maxPromptTokens = "max_prompt_tokens"
        case supportedParameters = "supported_parameters"
        case status
        case pricing
    }
}

struct OpenRouterEndpointOption: Sendable, Equatable, Identifiable {
    var id: String { tag }
    var tag: String
    var providerName: String
    var quantization: String?
    var supportedParameters: [String]
    var status: Int?
    var promptPricePerMillion: Double? = nil
    var cachedInputPricePerMillion: Double? = nil
    var completionPricePerMillion: Double? = nil
}

struct OpenRouterModelEndpointOptions: Sendable, Equatable {
    var modelId: String
    var endpoints: [ModelEndpoint]
    var providerEndpoints: [OpenRouterEndpointOption]
    var quantizations: [String]
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
