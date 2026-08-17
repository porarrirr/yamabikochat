import Foundation
import Combine

private actor OpenRouterModelsFetchCoordinator {
    private var inFlight: Task<[SimpleModel], Error>?
    private var activeFetchID = UUID()

    func resolve(
        forceRefresh: Bool,
        perform: @Sendable @escaping () async throws -> [SimpleModel]
    ) async throws -> [SimpleModel] {
        if forceRefresh {
            inFlight?.cancel()
            inFlight = nil
        } else if let inFlight, !inFlight.isCancelled {
            return try await inFlight.value
        }

        let fetchID = UUID()
        activeFetchID = fetchID
        let task = Task { try await perform() }
        inFlight = task
        do {
            let result = try await task.value
            if activeFetchID == fetchID {
                inFlight = nil
            }
            return result
        } catch {
            if activeFetchID == fetchID {
                inFlight = nil
            }
            throw error
        }
    }
}

private actor OpenRouterEndpointsFetchCoordinator {
    private struct InFlight {
        var id: UUID
        var task: Task<[ModelEndpoint], Error>
    }

    private var inFlightByModel: [String: InFlight] = [:]

    func resolve(
        modelId: String,
        forceRefresh: Bool,
        perform: @Sendable @escaping () async throws -> [ModelEndpoint]
    ) async throws -> [ModelEndpoint] {
        if forceRefresh {
            inFlightByModel[modelId]?.task.cancel()
            inFlightByModel[modelId] = nil
        } else if let inFlight = inFlightByModel[modelId], !inFlight.task.isCancelled {
            return try await inFlight.task.value
        }

        let fetchID = UUID()
        let task = Task { try await perform() }
        inFlightByModel[modelId] = InFlight(id: fetchID, task: task)
        do {
            let result = try await task.value
            if inFlightByModel[modelId]?.id == fetchID {
                inFlightByModel[modelId] = nil
            }
            return result
        } catch {
            if inFlightByModel[modelId]?.id == fetchID {
                inFlightByModel[modelId] = nil
            }
            throw error
        }
    }
}

final class OpenRouterModelService {
    private let credentialStore: SecureCredentialStore
    private let httpClient: HTTPClientProtocol

    private let modelsSubject = CurrentValueSubject<[SimpleModel], Never>([])
    private let loadingSubject = CurrentValueSubject<Bool, Never>(false)
    private let errorSubject = CurrentValueSubject<String?, Never>(nil)

    private var cachedModels: [SimpleModel]?
    private var lastFetch: Date?
    private let modelCacheTTL: TimeInterval = 5 * 60
    private var activeModelsFetchID = UUID()

    private struct EndpointCacheEntry {
        var options: OpenRouterModelEndpointOptions
        var fetchedAt: Date
    }

    private var endpointCache: [String: EndpointCacheEntry] = [:]
    private var activeEndpointFetchIDs: [String: UUID] = [:]
    private let endpointCacheTTL: TimeInterval = 5 * 60

    private var cachedProviders: ProviderDirectory = .empty
    private var lastProvidersFetch: Date?
    private let providersCacheTTL: TimeInterval = 24 * 60 * 60
    private let modelsFetchCoordinator = OpenRouterModelsFetchCoordinator()
    private let endpointsFetchCoordinator = OpenRouterEndpointsFetchCoordinator()

    init(
        credentialStore: SecureCredentialStore,
        httpClient: HTTPClientProtocol = URLSessionHTTPClient()
    ) {
        self.credentialStore = credentialStore
        self.httpClient = httpClient
    }

    var modelsPublisher: AnyPublisher<[SimpleModel], Never> { modelsSubject.eraseToAnyPublisher() }
    var loadingPublisher: AnyPublisher<Bool, Never> { loadingSubject.eraseToAnyPublisher() }
    var errorPublisher: AnyPublisher<String?, Never> { errorSubject.eraseToAnyPublisher() }

    func currentModels() -> [SimpleModel] { modelsSubject.value }

    func getAvailableModels(forceRefresh: Bool = false) async -> [SimpleModel] {
        if !forceRefresh,
           let cachedModels,
           let lastFetch,
           Date().timeIntervalSince(lastFetch) < modelCacheTTL {
            return cachedModels
        }

        let fetchID = UUID()
        activeModelsFetchID = fetchID
        loadingSubject.send(true)
        errorSubject.send(nil)

        do {
            let resolved = try await modelsFetchCoordinator.resolve(forceRefresh: forceRefresh) { [self] in
                try await requestAvailableModels()
            }
            guard activeModelsFetchID == fetchID else { return resolved }
            cachedModels = resolved
            lastFetch = Date()
            modelsSubject.send(resolved)
            loadingSubject.send(false)
            DiagnosticsLogger.log(
                "OpenRouter models fetched count=\(resolved.count) forceRefresh=\(forceRefresh)",
                category: .network
            )
            return resolved
        } catch is CancellationError {
            guard activeModelsFetchID == fetchID else { return [] }
            loadingSubject.send(false)
            return []
        } catch {
            guard activeModelsFetchID == fetchID else { return [] }
            DiagnosticsLogger.log("OpenRouter models fetch failed", category: .network, error: error)
            cachedModels = nil
            lastFetch = nil
            errorSubject.send(error.localizedDescription)
            modelsSubject.send([])
            loadingSubject.send(false)
            return []
        }
    }

    private func requestAvailableModels() async throws -> [SimpleModel] {
        let request = HTTPRequest(
            url: URL(string: "https://openrouter.ai/api/v1/models")!,
            method: "GET",
            headers: try authHeaders()
        )

        let (data, response) = try await httpClient.send(request)
        guard (200 ... 299).contains(response.statusCode) else {
            throw ProviderClientError.httpStatus(response.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        let models = try parseModels(from: data)
        guard !models.isEmpty else {
            throw ProviderClientError.parseFailure("OpenRouter returned an empty model catalog")
        }
        return models
    }

    func getProvidersDirectory(forceRefresh: Bool = false) async -> ProviderDirectory {
        if !forceRefresh,
           cachedProviders != .empty,
           let lastProvidersFetch,
           Date().timeIntervalSince(lastProvidersFetch) < providersCacheTTL {
            return cachedProviders
        }

        do {
            let request = HTTPRequest(
                url: URL(string: "https://openrouter.ai/api/v1/providers")!,
                method: "GET",
                headers: try authHeaders()
            )
            let (data, response) = try await httpClient.send(request)
            guard (200 ... 299).contains(response.statusCode) else {
                return cachedProviders
            }

            let providers = try JSONDecoder().decode(ProvidersResponse.self, from: data)
            let mapped = ProviderDirectory.fromList(providers.data)
            cachedProviders = mapped
            lastProvidersFetch = Date()
            return mapped
        } catch {
            return cachedProviders
        }
    }

    func getModelEndpointOptions(
        modelId: String,
        forceRefresh: Bool = false
    ) async throws -> OpenRouterModelEndpointOptions {
        let normalizedModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if !forceRefresh,
           let cached = endpointCache[normalizedModelId],
           Date().timeIntervalSince(cached.fetchedAt) < endpointCacheTTL {
            return cached.options
        }
        if forceRefresh {
            endpointCache[normalizedModelId] = nil
        }

        let fetchID = UUID()
        activeEndpointFetchIDs[normalizedModelId] = fetchID
        let endpoints: [ModelEndpoint]
        do {
            endpoints = try await endpointsFetchCoordinator.resolve(
                modelId: normalizedModelId,
                forceRefresh: forceRefresh
            ) { [self] in
                try await requestModelEndpoints(modelId: normalizedModelId)
            }
        } catch {
            if activeEndpointFetchIDs[normalizedModelId] == fetchID {
                activeEndpointFetchIDs[normalizedModelId] = nil
            }
            throw error
        }

        var seenTags: Set<String> = []
        var providerEndpoints: [OpenRouterEndpointOption] = []
        var seenQuantizations: Set<String> = []
        var quantizations: [String] = []

        for endpoint in endpoints {
            guard let tag = endpoint.tag?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
                !tag.isEmpty
            else {
                DiagnosticsLogger.log(
                    "OpenRouter endpoint ignored because tag is missing",
                    level: .warning,
                    category: .network,
                    metadata: [
                        "model": normalizedModelId,
                        "endpoint": endpoint.name
                    ]
                )
                continue
            }
            guard seenTags.insert(tag).inserted else { continue }

            let quantization = endpoint.quantization?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .nilIfEmpty
            if let quantization, seenQuantizations.insert(quantization).inserted {
                quantizations.append(quantization)
            }

            let providerName = endpoint.providerName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty ?? tag
            providerEndpoints.append(
                OpenRouterEndpointOption(
                    tag: tag,
                    providerName: providerName,
                    quantization: quantization,
                    supportedParameters: endpoint.supportedParameters ?? [],
                    status: endpoint.status
                )
            )
        }

        let options = OpenRouterModelEndpointOptions(
            modelId: normalizedModelId,
            endpoints: endpoints,
            providerEndpoints: providerEndpoints,
            quantizations: quantizations
        )
        if activeEndpointFetchIDs[normalizedModelId] == fetchID {
            endpointCache[normalizedModelId] = EndpointCacheEntry(options: options, fetchedAt: Date())
            activeEndpointFetchIDs[normalizedModelId] = nil
            DiagnosticsLogger.log(
                "OpenRouter endpoints fetched count=\(providerEndpoints.count)",
                category: .network,
                metadata: ["model": normalizedModelId]
            )
        }
        return options
    }

    private func requestModelEndpoints(modelId: String) async throws -> [ModelEndpoint] {
        let parts = modelId.split(separator: "/")
        guard parts.count >= 2 else {
            throw ProviderClientError.parseFailure("Invalid OpenRouter model id: \(modelId)")
        }

        let author = String(parts[0])
        let slug = parts.dropFirst().joined(separator: "/")
        // Variants like ":free" have their own endpoint listings whose providers
        // differ from the base model, so the suffix must stay in the slug.
        guard let url = URL(string: "https://openrouter.ai/api/v1/models/\(author)/\(slug)/endpoints") else {
            throw ProviderClientError.parseFailure("Invalid OpenRouter endpoints URL for model: \(modelId)")
        }

        let request = HTTPRequest(
            url: url,
            method: "GET",
            headers: try authHeaders()
        )
        let (data, response) = try await httpClient.send(request)
        guard (200 ... 299).contains(response.statusCode) else {
            throw ProviderClientError.httpStatus(response.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return try JSONDecoder().decode(ModelEndpointsEnvelope.self, from: data).data.endpoints
    }

    func getModelEndpoints(modelId: String) async -> [ModelEndpoint] {
        do {
            return try await getModelEndpointOptions(modelId: modelId).endpoints
        } catch is CancellationError {
            return []
        } catch {
            DiagnosticsLogger.log(
                "OpenRouter endpoints fetch failed",
                category: .network,
                metadata: ["model": modelId],
                error: error
            )
            return []
        }
    }

    func searchModels(query: String) -> [SimpleModel] {
        let lower = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if lower.isEmpty { return modelsSubject.value }
        return modelsSubject.value.filter {
            $0.id.lowercased().contains(lower) ||
                $0.name.lowercased().contains(lower) ||
                $0.provider.lowercased().contains(lower)
        }
    }

    func getModelsByProvider(_ provider: String) -> [SimpleModel] {
        modelsSubject.value.filter { $0.provider.caseInsensitiveCompare(provider) == .orderedSame }
    }

    func getFreeModels() -> [SimpleModel] {
        modelsSubject.value.filter(\.isFree)
    }

    func getModelById(_ modelId: String) -> SimpleModel? {
        modelsSubject.value.first(where: { $0.id == modelId })
    }

    func resolveContextLength(modelID: String, providerID: String) -> Int? {
        let normalized = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }

        if let direct = getModelById(normalized)?.contextLength, direct > 0 {
            return direct
        }

        let lowerModel = normalized.lowercased()
        let withoutVariant = lowerModel.components(separatedBy: ":").first ?? lowerModel
        let targetLeaf = withoutVariant.split(separator: "/").last.map(String.init) ?? withoutVariant
        let providerPrefix: String? = switch providerID.uppercased() {
        case "GEMINI": "google"
        case "OPENAI", "CODEX_AUTH": "openai"
        case "MINIMAX": "minimax"
        case "ZAI": "z-ai"
        case "SUPERGROK": "x-ai"
        case "ALIBABA_CODING_PLAN": "qwen"
        default: nil
        }
        let available = currentModels()

        if let exact = available.first(where: { $0.id.lowercased() == lowerModel }),
           exact.contextLength > 0 {
            return exact.contextLength
        }
        if let loose = available.first(where: { model in
               let candidate = model.id.lowercased().components(separatedBy: ":").first ?? model.id.lowercased()
               let candidateLeaf = candidate.split(separator: "/").last.map(String.init) ?? candidate
               let prefixMatches = providerPrefix.map { candidate.hasPrefix("\($0)/") } ?? true
               return prefixMatches && (candidate == withoutVariant || candidateLeaf == targetLeaf)
           }),
           loose.contextLength > 0 {
            return loose.contextLength
        }
        return nil
    }

    func clearCache() {
        cachedModels = nil
        lastFetch = nil
        endpointCache = [:]
        activeEndpointFetchIDs = [:]
        modelsSubject.send([])
        errorSubject.send(nil)
    }

    func replaceCachedModels(_ models: [SimpleModel]) {
        cachedModels = models
        lastFetch = Date()
        modelsSubject.send(models)
    }

    func getAvailableProviders(for modelId: String) async -> [String] {
        do {
            return try await getModelEndpointOptions(modelId: modelId)
                .providerEndpoints
                .map(\.tag)
        } catch {
            DiagnosticsLogger.log(
                "OpenRouter provider endpoint lookup failed",
                category: .network,
                metadata: ["model": modelId],
                error: error
            )
            return []
        }
    }

    func getAvailableQuantizations(for modelId: String) async -> [String] {
        do {
            return try await getModelEndpointOptions(modelId: modelId).quantizations
        } catch {
            DiagnosticsLogger.log(
                "OpenRouter quantization lookup failed",
                category: .network,
                metadata: ["model": modelId],
                error: error
            )
            return []
        }
    }

    private func authHeaders() throws -> [String: String] {
        var headers: [String: String] = [
            "Content-Type": "application/json",
            "Accept": "application/json",
            "HTTP-Referer": "https://yamabikochat.app",
            "X-Title": "YamabikoChat iOS",
            "User-Agent": "YamabikoChat-iOS/1.0"
        ]

        if let key = try credentialStore.credential(for: .openRouter), !key.isEmpty {
            headers["Authorization"] = "Bearer \(key)"
        }
        return headers
    }

    private func parseModels(from data: Data) throws -> [SimpleModel] {
        if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
           let entries = root["data"] as? [Any] {
            let mapped = entries
                .compactMap { $0 as? [String: Any] }
                .compactMap(parseSimpleModel)
            return sortModels(mapped)
        }

        let envelope = try JSONDecoder().decode(OpenRouterModelsResponse.self, from: data)
        return sortModels(envelope.data.map(SimpleModel.fromOpenRouterModel))
    }

    private func sortModels(_ models: [SimpleModel]) -> [SimpleModel] {
        models.sorted { lhs, rhs in
            if lhs.isFree != rhs.isFree { return lhs.isFree }
            if lhs.promptPricePerMillion != rhs.promptPricePerMillion {
                return lhs.promptPricePerMillion < rhs.promptPricePerMillion
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private func parseSimpleModel(from object: [String: Any]) -> SimpleModel? {
        guard let id = parseString(object["id"])?.trimmingCharacters(in: .whitespacesAndNewlines),
              !id.isEmpty
        else {
            return nil
        }

        let name = parseString(object["name"])?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? id
        let pricing = object["pricing"] as? [String: Any] ?? [:]
        let promptPerToken = firstDouble([
            pricing["prompt"],
            pricing["completion"],
            pricing["request"]
        ])
        let completionPerToken = firstDouble([
            pricing["completion"],
            pricing["prompt"],
            pricing["request"]
        ])
        let provider = id.split(separator: "/").first.map(String.init) ?? "unknown"

        let topProvider = object["top_provider"] as? [String: Any]
        let availableProviders = parseStringArray(topProvider?["available_providers"])
        let availableQuantizations = parseStringArray(topProvider?["available_quantizations"])
        let contextLength = parseInt(object["context_length"]) ?? 0
        let reasoning = parseReasoningCapabilities(object["reasoning"])

        return SimpleModel(
            id: id,
            name: name,
            provider: provider,
            topProvider: availableProviders.first,
            contextLength: contextLength,
            promptPricePerMillion: promptPerToken * 1_000_000,
            completionPricePerMillion: completionPerToken * 1_000_000,
            isFree: promptPerToken == 0 && completionPerToken == 0,
            availableProviders: availableProviders,
            availableQuantizations: availableQuantizations,
            reasoning: reasoning
        )
    }

    private func parseReasoningCapabilities(_ value: Any?) -> OpenRouterReasoningCapabilities? {
        guard let object = value as? [String: Any] else { return nil }
        let exposesEffortSelection = object.keys.contains("supported_efforts")
        let supportedEfforts: [String]?
        if exposesEffortSelection, !(object["supported_efforts"] is NSNull) {
            supportedEfforts = parseStringArray(object["supported_efforts"])
        } else {
            supportedEfforts = nil
        }

        return OpenRouterReasoningCapabilities(
            supportedEfforts: supportedEfforts,
            exposesEffortSelection: exposesEffortSelection,
            defaultEffort: parseString(object["default_effort"])?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
                .nilIfEmpty,
            defaultEnabled: parseBool(object["default_enabled"]),
            supportsMaxTokens: parseBool(object["supports_max_tokens"]) ?? false,
            mandatory: parseBool(object["mandatory"]) ?? false
        )
    }

    private func parseString(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private func parseInt(_ value: Any?) -> Int? {
        if let intValue = value as? Int { return intValue }
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String, let parsed = Int(text) { return parsed }
        return nil
    }

    private func parseBool(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let text = value as? String {
            switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: return nil
            }
        }
        return nil
    }

    private func firstDouble(_ values: [Any?]) -> Double {
        values.compactMap(parseDouble).first ?? 0
    }

    private func parseDouble(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let text = value as? String { return Double(text) }
        return nil
    }

    private func parseStringArray(_ value: Any?) -> [String] {
        guard let raw = value as? [Any] else { return [] }
        return raw
            .compactMap(parseString)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
