import Foundation
import Combine

final class OpenRouterModelService {
    private let credentialStore: SecureCredentialStore
    private let httpClient: HTTPClientProtocol

    private let modelsSubject = CurrentValueSubject<[SimpleModel], Never>([])
    private let loadingSubject = CurrentValueSubject<Bool, Never>(false)
    private let errorSubject = CurrentValueSubject<String?, Never>(nil)

    private var cachedModels: [SimpleModel]?
    private var lastFetch: Date?
    private let modelCacheTTL: TimeInterval = 5 * 60

    private var cachedProviders: ProviderDirectory = .empty
    private var lastProvidersFetch: Date?
    private let providersCacheTTL: TimeInterval = 24 * 60 * 60

    private let fallbackModels: [SimpleModel] = [
        .init(
            id: "openai/gpt-4o",
            name: "GPT-4o",
            provider: "openai",
            topProvider: nil,
            contextLength: 128_000,
            promptPricePerMillion: 5.0,
            completionPricePerMillion: 15.0,
            isFree: false,
            availableProviders: [],
            availableQuantizations: []
        ),
        .init(
            id: "anthropic/claude-3.5-sonnet",
            name: "Claude 3.5 Sonnet",
            provider: "anthropic",
            topProvider: nil,
            contextLength: 200_000,
            promptPricePerMillion: 3.0,
            completionPricePerMillion: 15.0,
            isFree: false,
            availableProviders: [],
            availableQuantizations: []
        ),
        .init(
            id: "meta-llama/llama-3.1-8b-instruct:free",
            name: "Llama 3.1 8B Instruct (Free)",
            provider: "meta-llama",
            topProvider: nil,
            contextLength: 131_072,
            promptPricePerMillion: 0.0,
            completionPricePerMillion: 0.0,
            isFree: true,
            availableProviders: [],
            availableQuantizations: []
        )
    ]

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

        loadingSubject.send(true)
        errorSubject.send(nil)
        defer { loadingSubject.send(false) }

        do {
            let request = HTTPRequest(
                url: URL(string: "https://openrouter.ai/api/v1/models")!,
                method: "GET",
                headers: try authHeaders()
            )

            let (data, response) = try await httpClient.send(request)
            guard (200 ... 299).contains(response.statusCode) else {
                throw ProviderClientError.httpStatus(response.statusCode, String(data: data, encoding: .utf8) ?? "")
            }

            let mapped = try parseModels(from: data)

            let resolved = mapped.isEmpty ? fallbackModels : mapped
            cachedModels = resolved
            lastFetch = Date()
            modelsSubject.send(resolved)
            DiagnosticsLogger.log(
                "OpenRouter models fetched count=\(resolved.count) forceRefresh=\(forceRefresh)",
                category: .network
            )
            return resolved
        } catch {
            DiagnosticsLogger.log("OpenRouter models fetch failed", category: .network, error: error)
            errorSubject.send(error.localizedDescription)
            let resolved = cachedModels ?? fallbackModels
            modelsSubject.send(resolved)
            return resolved
        }
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

    func getModelEndpoints(modelId: String) async -> [ModelEndpoint] {
        let parts = modelId.split(separator: "/")
        guard parts.count >= 2 else { return [] }

        let author = String(parts[0])
        let rawSlug = parts.dropFirst().joined(separator: "/")
        let canonicalSlug = rawSlug.split(separator: ":").first.map(String.init) ?? rawSlug
        let url = URL(string: "https://openrouter.ai/api/v1/models/\(author)/\(canonicalSlug)/endpoints")!

        do {
            let request = HTTPRequest(
                url: url,
                method: "GET",
                headers: try authHeaders()
            )
            let (data, response) = try await httpClient.send(request)
            guard (200 ... 299).contains(response.statusCode) else { return [] }
            let envelope = try JSONDecoder().decode(ModelEndpointsEnvelope.self, from: data)
            return envelope.data.endpoints
        } catch {
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

    func clearCache() {
        cachedModels = nil
        lastFetch = nil
        modelsSubject.send([])
        errorSubject.send(nil)
    }

    func getAvailableProviders(for modelId: String) async -> [String] {
        let endpoints = await getModelEndpoints(modelId: modelId)
        let directory = await getProvidersDirectory()
        return Array(Set(endpoints.compactMap { endpoint in
            directory.slugForName(endpoint.providerName) ?? endpoint.providerName?.lowercased()
        })).sorted()
    }

    func getAvailableQuantizations(for modelId: String) async -> [String] {
        let endpoints = await getModelEndpoints(modelId: modelId)
        return Array(Set(endpoints.compactMap(\.quantization))).sorted()
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
            availableQuantizations: availableQuantizations
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
