import Foundation

/// Resolves the reasoning-effort levels a provider/model can actually accept from the
/// catalogs the app already trusts (the ChatGPT account catalog, the models.dev catalog,
/// and the built-in xAI catalog). Every execution mode shares this resolution so the
/// settings and chat controls offer the same list instead of a free-form text field.
enum ReasoningEffortOptions {
    /// xAI exposes the same three levels for every reasoning-capable model.
    static let superGrok = ["low", "medium", "high"]

    static func options(
        provider: String,
        model: String,
        codexModels: [PiCodexModel] = [],
        catalogProviders: [CatalogProvider] = []
    ) -> [String] {
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedModel.isEmpty else { return [] }

        if let providerID = ProviderReference(persistedID: provider).modelsDevID {
            return catalogModel(
                providerID: providerID,
                model: normalizedModel,
                catalogProviders: catalogProviders
            )?.supportedReasoningEfforts ?? []
        }

        switch provider.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() {
        case "CODEX_AUTH":
            let efforts = CodexModelCatalog.findPreset(normalizedModel, in: codexModels)?
                .supportedReasoningEfforts.map(\.effort) ?? []
            return deduplicated(efforts)
        case "SUPERGROK":
            return superGrok
        default:
            return []
        }
    }

    static func catalogModel(
        providerID: String,
        model: String,
        catalogProviders: [CatalogProvider]
    ) -> CatalogModel? {
        catalogProviders
            .first { $0.id.caseInsensitiveCompare(providerID) == .orderedSame }?
            .models.first { $0.id == model }
    }

    private static func deduplicated(_ efforts: [String]) -> [String] {
        var seen = Set<String>()
        return efforts.filter { seen.insert($0).inserted }
    }
}
