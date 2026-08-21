import Combine
import Foundation

private actor ModelsDevFetchCoordinator {
    private var task: Task<CatalogLoadState, Never>?

    func resolve(forceRefresh: Bool, operation: @Sendable @escaping () async -> CatalogLoadState) async -> CatalogLoadState {
        if forceRefresh { task?.cancel(); task = nil }
        if let task { return await task.value }
        let next = Task { await operation() }
        task = next
        let value = await next.value
        task = nil
        return value
    }
}

final class ModelsDevCatalogRepository: @unchecked Sendable {
    private static let catalogURL = URL(string: "https://models.dev/catalog.json")!
    private static let cacheTTL: TimeInterval = 24 * 60 * 60
    private static let etagKey = "models_dev_catalog_etag"
    private static let fetchedAtKey = "models_dev_catalog_fetched_at"

    private let session: URLSession
    private let defaults: UserDefaults
    private let cacheURL: URL
    private let stateSubject: CurrentValueSubject<CatalogLoadState, Never>
    private let coordinator = ModelsDevFetchCoordinator()

    init(session: URLSession = .shared, defaults: UserDefaults = .standard, cacheURL: URL? = nil) {
        self.session = session
        self.defaults = defaults
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        self.cacheURL = cacheURL ?? base.appendingPathComponent("models_dev_catalog_cache.json")
        let providers = Self.readCache(at: self.cacheURL)
        let date = defaults.object(forKey: Self.fetchedAtKey) as? Date
        stateSubject = CurrentValueSubject(CatalogLoadState(
            availability: providers.isEmpty ? .idle : .stale,
            providers: providers,
            lastUpdated: date,
            error: nil
        ))
    }

    var statePublisher: AnyPublisher<CatalogLoadState, Never> { stateSubject.eraseToAnyPublisher() }
    func currentState() -> CatalogLoadState { stateSubject.value }

    func provider(for reference: ProviderReference) -> CatalogProvider? {
        guard let id = reference.modelsDevID else { return nil }
        return stateSubject.value.providers.first { $0.id == id }
    }

    func load(forceRefresh: Bool = false) async -> CatalogLoadState {
        let current = stateSubject.value
        if !forceRefresh,
           !current.providers.isEmpty,
           let updated = current.lastUpdated,
           Date().timeIntervalSince(updated) < Self.cacheTTL {
            let ready = CatalogLoadState(availability: .ready, providers: current.providers, lastUpdated: updated)
            stateSubject.send(ready)
            return ready
        }
        stateSubject.send(CatalogLoadState(availability: .loading, providers: current.providers, lastUpdated: current.lastUpdated))
        let result = await coordinator.resolve(forceRefresh: forceRefresh) { [self] in
            await fetch(previous: current)
        }
        stateSubject.send(result)
        return result
    }

    private func fetch(previous: CatalogLoadState) async -> CatalogLoadState {
        do {
            var request = URLRequest(url: Self.catalogURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
            if let etag = defaults.string(forKey: Self.etagKey) { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
            if http.statusCode == 304, !previous.providers.isEmpty {
                let date = Date()
                defaults.set(date, forKey: Self.fetchedAtKey)
                return CatalogLoadState(availability: .ready, providers: previous.providers, lastUpdated: date)
            }
            guard (200 ... 299).contains(http.statusCode) else {
                throw ProviderClientError.httpStatus(http.statusCode, String(data: data, encoding: .utf8) ?? "")
            }
            let providers = try Self.parseCatalog(data)
            guard !providers.isEmpty else { throw ProviderClientError.parseFailure("models.dev returned no usable providers") }
            try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(providers).write(to: cacheURL, options: .atomic)
            let date = Date()
            defaults.set(date, forKey: Self.fetchedAtKey)
            defaults.set(http.value(forHTTPHeaderField: "ETag"), forKey: Self.etagKey)
            DiagnosticsLogger.log("models.dev catalog updated providers=\(providers.count)", category: .network)
            return CatalogLoadState(availability: .ready, providers: providers, lastUpdated: date)
        } catch {
            DiagnosticsLogger.log("models.dev catalog update failed", category: .network, error: error)
            return CatalogLoadState(
                availability: previous.providers.isEmpty ? .error : .stale,
                providers: previous.providers,
                lastUpdated: previous.lastUpdated,
                error: error.localizedDescription
            )
        }
    }

    static func parseCatalog(_ data: Data) throws -> [CatalogProvider] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let rawProviders = root["providers"] as? [String: Any]
        else { throw ProviderClientError.parseFailure("catalog.json is missing providers") }

        return rawProviders.compactMap { providerID, rawValue -> CatalogProvider? in
            guard providerID.lowercased() != "openrouter",
                  let value = rawValue as? [String: Any],
                  let name = value["name"] as? String,
                  let npm = value["npm"] as? String,
                  let rawModels = value["models"] as? [String: Any]
            else { return nil }
            let models = rawModels.compactMap { modelID, rawModel -> CatalogModel? in
                guard let model = rawModel as? [String: Any],
                      (model["status"] as? String)?.lowercased() != "deprecated"
                else { return nil }
                let modalities = model["modalities"] as? [String: Any]
                let outputs = modalities?["output"] as? [String] ?? []
                guard outputs.contains(where: { $0.caseInsensitiveCompare("text") == .orderedSame }) else { return nil }
                let limits = model["limit"] as? [String: Any]
                let cost = model["cost"] as? [String: Any]
                let modelProvider = model["provider"] as? [String: Any]
                let reasoningOptions = (model["reasoning_options"] as? [[String: Any]] ?? []).compactMap { option in
                    (option["type"] as? String).map { type in
                        let values = (option["values"] as? [Any] ?? []).compactMap { $0 as? String }
                        return CatalogReasoningOption(type: type, values: values)
                    }
                }
                return CatalogModel(
                    id: modelID,
                    name: model["name"] as? String ?? modelID,
                    description: model["description"] as? String,
                    family: model["family"] as? String,
                    attachment: model["attachment"] as? Bool,
                    reasoning: model["reasoning"] as? Bool,
                    reasoningOptions: reasoningOptions,
                    toolCall: model["tool_call"] as? Bool,
                    structuredOutput: model["structured_output"] as? Bool,
                    temperature: model["temperature"] as? Bool,
                    inputModalities: modalities?["input"] as? [String] ?? [],
                    outputModalities: outputs,
                    releaseDate: model["release_date"] as? String,
                    lastUpdated: model["last_updated"] as? String,
                    limits: CatalogLimits(context: number(limits?["context"]), input: number(limits?["input"]), output: number(limits?["output"])),
                    cost: CatalogCost(
                        inputPerMillion: decimal(cost?["input"]), outputPerMillion: decimal(cost?["output"]),
                        reasoningPerMillion: decimal(cost?["reasoning"]), cacheReadPerMillion: decimal(cost?["cache_read"]),
                        cacheWritePerMillion: decimal(cost?["cache_write"])
                    ),
                    providerContract: CatalogModelProviderContract(
                        npm: modelProvider?["npm"] as? String ?? npm,
                        api: modelProvider?["api"] as? String ?? value["api"] as? String,
                        shape: modelProvider?["shape"] as? String,
                        provenance: modelProvider == nil ? "provider" : "model"
                    )
                )
            }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            guard !models.isEmpty else { return nil }
            return CatalogProvider(
                id: providerID.lowercased(), name: name, npm: npm, api: value["api"] as? String,
                env: value["env"] as? [String] ?? [], documentationURL: value["doc"] as? String, models: models
            )
        }.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private static func readCache(at url: URL) -> [CatalogProvider] {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode([CatalogProvider].self, from: $0) } ?? []
    }

    private static func number(_ value: Any?) -> Int? { (value as? NSNumber)?.intValue }
    private static func decimal(_ value: Any?) -> Double? { (value as? NSNumber)?.doubleValue }
}
