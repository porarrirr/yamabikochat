import Foundation

let modelsDevProviderPrefix = "MODELS_DEV:"

struct ProviderReference: Codable, Hashable, Sendable {
    let persistedID: String

    var modelsDevID: String? {
        guard persistedID.uppercased().hasPrefix(modelsDevProviderPrefix) else { return nil }
        let value = String(persistedID.dropFirst(modelsDevProviderPrefix.count))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return value.isEmpty ? nil : value
    }

    var isModelsDev: Bool { modelsDevID != nil }

    static func modelsDev(_ providerID: String) -> ProviderReference {
        ProviderReference(persistedID: modelsDevProviderPrefix + providerID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
    }
}

enum ModelsDevMergedProvider {
    static func catalogID(for persistedID: String) -> String? {
        let reference = ProviderReference(persistedID: persistedID)
        if let dynamic = reference.modelsDevID { return dynamic }
        return [
            "GEMINI": "google", "OPENAI": "openai"
        ][persistedID.uppercased()]
    }
}

struct CatalogReasoningOption: Codable, Equatable, Sendable {
    let type: String
    var values: [String] = []
}

enum ModelsDevReasoningPreference {
    private static let fieldPrefix = "YAMABIKO_REASONING_EFFORT_"

    static func fieldName(modelID: String) -> String {
        let encodedModelID = modelID.utf8.map { String(format: "%02X", $0) }.joined()
        return fieldPrefix + encodedModelID
    }
}

struct CatalogLimits: Codable, Equatable, Sendable {
    var context: Int?
    var input: Int?
    var output: Int?
}

struct CatalogCost: Codable, Equatable, Sendable {
    var inputPerMillion: Double?
    var outputPerMillion: Double?
    var reasoningPerMillion: Double?
    var cacheReadPerMillion: Double?
    var cacheWritePerMillion: Double?
}

struct CatalogModel: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    var description: String?
    var family: String?
    var attachment: Bool
    var reasoning: Bool
    var reasoningOptions: [CatalogReasoningOption]
    var toolCall: Bool
    var structuredOutput: Bool
    var temperature: Bool
    var inputModalities: [String]
    var outputModalities: [String]
    var releaseDate: String?
    var lastUpdated: String?
    var limits: CatalogLimits
    var cost: CatalogCost

    var supportedReasoningEfforts: [String] {
        var seen = Set<String>()
        return reasoningOptions
            .filter { $0.type.caseInsensitiveCompare("effort") == .orderedSame }
            .flatMap(\.values)
            .compactMap { rawValue in
                let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                guard !value.isEmpty, seen.insert(value).inserted else { return nil }
                return value
            }
    }

    func shouldShowReasoningEffortPreference(savedEffort: String) -> Bool {
        !supportedReasoningEfforts.isEmpty || !savedEffort.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func matches(_ query: String) -> Bool {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return true }
        return [id, name, family ?? "", description ?? ""].contains {
            $0.localizedCaseInsensitiveContains(value)
        }
    }
}

struct CatalogProvider: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let npm: String
    var api: String?
    var env: [String]
    var documentationURL: String?
    var models: [CatalogModel]

    var reference: ProviderReference { .modelsDev(id) }

    func matches(_ query: String) -> Bool {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty || id.localizedCaseInsensitiveContains(value) || name.localizedCaseInsensitiveContains(value)
    }
}

enum ProviderAdapterKind: String, Codable, Sendable {
    case openAICompatible
    case openAI
    case anthropic
    case gemini
    case googleVertex
    case googleVertexAnthropic
    case azureOpenAI
    case amazonBedrock
    case cohere
    case sapAICore
    case gitLabDuo
    case vercelAI
    case cloudflareAIGateway
    case providerSpecific
    case unverifiedOpenAICompatible
}

struct ProviderExecutionProfile: Equatable, Sendable {
    let adapter: ProviderAdapterKind
    let isVerifiedMapping: Bool
    let requiresManualBaseURL: Bool
}

enum ModelsDevProviderAdapterRegistry {
    private static let resolvedBaseURLProviders: Set<String> = [
        "openai", "anthropic", "xai", "groq", "mistral", "togetherai", "cerebras",
        "deepinfra", "perplexity", "cohere", "vercel", "v0", "venice", "aihubmix",
        "merge-gateway", "azure", "azure-cognitive-services", "cloudflare-ai-gateway"
    ]

    static func profile(for provider: CatalogProvider) -> ProviderExecutionProfile {
        let kind: ProviderAdapterKind
        switch provider.npm {
        case "@ai-sdk/openai-compatible": kind = .openAICompatible
        case "@ai-sdk/openai": kind = .openAI
        case "@ai-sdk/anthropic": kind = .anthropic
        case "@ai-sdk/google": kind = .gemini
        case "@ai-sdk/google-vertex": kind = .googleVertex
        case "@ai-sdk/google-vertex/anthropic": kind = .googleVertexAnthropic
        case "@ai-sdk/azure": kind = .azureOpenAI
        case "@ai-sdk/amazon-bedrock": kind = .amazonBedrock
        case "@ai-sdk/cohere": kind = .cohere
        case "@jerome-benoit/sap-ai-provider-v2": kind = .sapAICore
        case "gitlab-ai-provider": kind = .gitLabDuo
        case "@ai-sdk/gateway", "@ai-sdk/vercel": kind = .vercelAI
        case "ai-gateway-provider": kind = .cloudflareAIGateway
        case "@ai-sdk/xai", "@ai-sdk/groq", "@ai-sdk/cerebras", "@ai-sdk/deepinfra",
             "@ai-sdk/mistral", "@ai-sdk/perplexity", "@ai-sdk/togetherai",
             "venice-ai-sdk-provider", "@qvac/ai-sdk-provider", "@aihubmix/ai-sdk-provider",
             "merge-gateway-ai-sdk-provider": kind = .providerSpecific
        default: kind = .unverifiedOpenAICompatible
        }
        return ProviderExecutionProfile(
            adapter: kind,
            isVerifiedMapping: kind != .unverifiedOpenAICompatible,
            requiresManualBaseURL: !resolvedBaseURLProviders.contains(provider.id) &&
                (provider.api?.trimmedNonEmpty == nil || provider.api?.contains("${") == true)
        )
    }
}

enum CatalogAvailability: String, Codable, Sendable {
    case idle, loading, ready, stale, error
}

struct CatalogLoadState: Equatable, Sendable {
    var availability: CatalogAvailability = .idle
    var providers: [CatalogProvider] = []
    var lastUpdated: Date?
    var error: String?
}
