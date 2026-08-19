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
    private static let catalogProviderIDsRepresentedByBuiltIns: Set<String> = ["google", "openrouter"]

    static func catalogID(for persistedID: String) -> String? {
        let reference = ProviderReference(persistedID: persistedID)
        if let dynamic = reference.modelsDevID { return dynamic }
        return persistedID.caseInsensitiveCompare("GEMINI") == .orderedSame ? "google" : nil
    }

    static func isSelectableCatalogProvider(_ providerID: String) -> Bool {
        !catalogProviderIDsRepresentedByBuiltIns.contains(providerID.lowercased())
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

    static func fieldKey(providerID: String, fieldName: String) -> String {
        let provider = providerID.lowercased().replacingOccurrences(
            of: "[^a-z0-9._-]+",
            with: "_",
            options: .regularExpression
        )
        let field = fieldName.uppercased().replacingOccurrences(
            of: "[^A-Z0-9_]+",
            with: "_",
            options: .regularExpression
        )
        return "models_dev_\(provider)_\(field)"
    }

    static func storageKey(providerID: String, modelID: String) -> String {
        fieldKey(providerID: providerID, fieldName: fieldName(modelID: modelID))
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

struct CatalogModelProviderContract: Codable, Equatable, Sendable {
    var npm: String?
    var api: String?
    var shape: String?
}

struct CatalogModel: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    var description: String?
    var family: String?
    var attachment: Bool?
    var reasoning: Bool?
    var reasoningOptions: [CatalogReasoningOption]
    var toolCall: Bool?
    var structuredOutput: Bool?
    var temperature: Bool?
    var inputModalities: [String]
    var outputModalities: [String]
    var releaseDate: String?
    var lastUpdated: String?
    var limits: CatalogLimits
    var cost: CatalogCost
    var providerContract: CatalogModelProviderContract? = nil

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

enum CatalogAvailability: String, Codable, Sendable {
    case idle, loading, ready, stale, error
}

struct CatalogLoadState: Equatable, Sendable {
    var availability: CatalogAvailability = .idle
    var providers: [CatalogProvider] = []
    var lastUpdated: Date?
    var error: String?
}
