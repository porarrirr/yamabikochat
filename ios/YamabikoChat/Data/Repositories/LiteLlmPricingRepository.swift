import Foundation

protocol LiteLlmPricingEstimating: Sendable {
    func estimateCostUsd(
        provider: String,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cachedInputTokens: Int?,
        cacheCreationInputTokens: Int?,
        reasoningTokens: Int?
    ) async -> Double?

    func modelSupportsVision(provider: String, model: String) async -> Bool
}

actor LiteLlmPricingRepository: LiteLlmPricingEstimating {
    private let session: URLSession
    private var cachedCatalog: [String: LiteLlmModelCatalogEntry] = [:]
    private var visionByBasename: [String: Bool] = [:]
    private var lastFetchedAtMs: Int64 = 0

    init(session: URLSession = .shared) {
        self.session = session
    }

    func estimateCostUsd(
        provider: String,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cachedInputTokens: Int?,
        cacheCreationInputTokens: Int?,
        reasoningTokens: Int?
    ) async -> Double? {
        guard let price = await resolvePrice(provider: provider, model: model) else { return nil }
        let providerKey = provider.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedInputTokens = max(0, inputTokens)
        let normalizedCachedInputTokens = max(0, min(normalizedInputTokens, cachedInputTokens ?? 0))
        let normalizedCacheCreationInputTokens = max(0, cacheCreationInputTokens ?? 0)
        let normalizedNonCachedInputTokens = max(0, normalizedInputTokens - normalizedCachedInputTokens)
        let inputRate = price.inputCostPerToken ?? 0
        let cachedInputRate = price.cacheReadInputCostPerToken ?? inputRate
        let cacheCreationInputRate = price.cacheCreationInputCostPerToken ?? inputRate
        let outputRate = price.outputCostPerToken ?? price.inputCostPerToken ?? 0
        let reasoningCount = max(0, reasoningTokens ?? 0)
        let reasoningIncludedInOutput = providerKey != "GEMINI"
        let nonReasoningOutput = reasoningIncludedInOutput
            ? max(0, outputTokens - reasoningCount)
            : max(0, outputTokens)
        let reasoningRate = price.outputCostPerReasoningToken ?? outputRate

        let inputCost =
            inputRate * Double(normalizedNonCachedInputTokens) +
            cachedInputRate * Double(normalizedCachedInputTokens) +
            cacheCreationInputRate * Double(normalizedCacheCreationInputTokens)
        let outputCost = outputRate * Double(nonReasoningOutput) + reasoningRate * Double(reasoningCount)
        let total = inputCost + outputCost
        guard total.isFinite, total >= 0 else { return nil }
        return total
    }

    func modelSupportsVision(provider: String, model: String) async -> Bool {
        await ensureCatalogLoaded()
        guard !cachedCatalog.isEmpty else { return false }

        let candidates = buildLookupCandidates(provider: provider, model: model)
        for candidate in candidates {
            if let entry = cachedCatalog[candidate] {
                return entry.supportsVision == true
            }
        }

        if provider.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "SUPERGROK",
           let catalogModel = SuperGrokModelCatalog.model(for: model) {
            return catalogModel.supportsVision
        }

        let basename = modelBasename(from: model)
        guard !basename.isEmpty else { return false }
        return visionByBasename[basename] == true
    }

    private func resolvePrice(provider: String, model: String) async -> LiteLlmModelPrice? {
        await ensureCatalogLoaded()
        guard !cachedCatalog.isEmpty else { return nil }
        let candidates = buildLookupCandidates(provider: provider, model: model)
        for candidate in candidates {
            if let entry = cachedCatalog[candidate], entry.hasPricing {
                return entry.price
            }
        }
        return nil
    }

    private func ensureCatalogLoaded(forceRefresh: Bool = false) async {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        if !forceRefresh, !cachedCatalog.isEmpty, (now - lastFetchedAtMs) < Self.cacheTTLms {
            return
        }

        guard let url = URL(string: "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json") else {
            return
        }

        do {
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                return
            }
            let parsed = parseCatalog(data: data)
            if !parsed.catalog.isEmpty {
                cachedCatalog = parsed.catalog
                visionByBasename = parsed.visionByBasename
                lastFetchedAtMs = Int64(Date().timeIntervalSince1970 * 1000)
            }
        } catch {
            DiagnosticsLogger.log("LiteLlmPricingRepository fetch failed", category: .network, error: error)
        }
    }

    private struct ParsedCatalog {
        var catalog: [String: LiteLlmModelCatalogEntry]
        var visionByBasename: [String: Bool]
    }

    private func parseCatalog(data: Data) -> ParsedCatalog {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ParsedCatalog(catalog: [:], visionByBasename: [:])
        }
        var output: [String: LiteLlmModelCatalogEntry] = [:]
        var visionByBasename: [String: Bool] = [:]
        for (rawKey, rawValue) in root {
            let key = rawKey.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if key == "sample_spec" { continue }
            guard let object = rawValue as? [String: Any] else { continue }
            let price = LiteLlmModelPrice(
                inputCostPerToken: object.doubleValue(for: "input_cost_per_token"),
                outputCostPerToken: object.doubleValue(for: "output_cost_per_token"),
                outputCostPerReasoningToken: object.doubleValue(for: "output_cost_per_reasoning_token"),
                cacheReadInputCostPerToken: object.doubleValue(for: "cache_read_input_token_cost"),
                cacheCreationInputCostPerToken: object.doubleValue(for: "cache_creation_input_token_cost")
            )
            let supportsVision = object.boolValue(for: "supports_vision")
            let hasPricing =
                price.inputCostPerToken != nil ||
                price.outputCostPerToken != nil ||
                price.outputCostPerReasoningToken != nil ||
                price.cacheReadInputCostPerToken != nil ||
                price.cacheCreationInputCostPerToken != nil
            guard hasPricing || supportsVision != nil else { continue }

            output[key] = LiteLlmModelCatalogEntry(price: price, supportsVision: supportsVision)

            if supportsVision == true {
                let basename = modelBasename(from: key)
                if !basename.isEmpty {
                    visionByBasename[basename] = true
                }
            }
        }
        return ParsedCatalog(catalog: output, visionByBasename: visionByBasename)
    }

    private func modelBasename(from model: String) -> String {
        let cleaned = model
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^/+"#, with: "", options: .regularExpression)
            .lowercased()
        guard !cleaned.isEmpty else { return "" }
        let canonical = cleaned.components(separatedBy: "@").first ?? cleaned
        let withoutVariant = canonical.components(separatedBy: ":").first ?? canonical
        if let last = withoutVariant.split(separator: "/").last, !last.isEmpty {
            return String(last)
        }
        return withoutVariant
    }

    private func buildLookupCandidates(provider: String, model: String) -> [String] {
        let cleanedModel = model
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^/+"#, with: "", options: .regularExpression)
            .lowercased()
        if cleanedModel.isEmpty { return [] }

        let canonical = cleanedModel.components(separatedBy: "@").first ?? cleanedModel
        let providerKey = provider.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        var values: [String] = []

        func append(_ value: String?) {
            guard let value else { return }
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !normalized.isEmpty, !values.contains(normalized) else { return }
            values.append(normalized)
        }

        append(canonical)
        append(canonical.components(separatedBy: ":").first)

        func suffixAfterFirstSlash(_ value: String) -> String {
            guard let slash = value.firstIndex(of: "/") else { return "" }
            let next = value.index(after: slash)
            guard next < value.endIndex else { return "" }
            return String(value[next...])
        }

        if canonical.contains("/") {
            let noVariant = canonical.components(separatedBy: ":").first ?? canonical
            let afterFirstSlash = suffixAfterFirstSlash(noVariant)
            let afterSecondSlash = suffixAfterFirstSlash(afterFirstSlash)
            append(noVariant)
            append(afterFirstSlash)
            append(afterSecondSlash)
            append("openrouter/\(noVariant)")
            if !afterFirstSlash.isEmpty {
                append("openrouter/\(afterFirstSlash.components(separatedBy: ":").first ?? afterFirstSlash)")
            }
        } else {
            let providerPrefix = inferProviderPrefix(model: canonical)
            append(providerPrefix.map { "\($0)/\(canonical)" })
            append("openrouter/\(canonical)")
            append(providerPrefix.map { "openrouter/\($0)/\(canonical)" })
        }

        switch providerKey {
        case "OPENROUTER":
            let base = canonical.components(separatedBy: ":").first ?? canonical
            append("openrouter/\(base)")
            if !base.hasPrefix("openrouter/") {
                let suffix = suffixAfterFirstSlash(base)
                append("openrouter/\(suffix.isEmpty ? base : suffix)")
            }
        case "OPENAI", "CODEX_AUTH", "OPENAI_COMPAT", "OPENCODE_GO", "SUPERGROK", "CLINEPASS", "ALIBABA_CODING_PLAN", "MINIMAX", "ZAI":
            append(canonical.replacingOccurrences(of: "openai/", with: ""))
            append(canonical.replacingOccurrences(of: "google/", with: ""))
            append(canonical.replacingOccurrences(of: "anthropic/", with: ""))
        case "GEMINI":
            let noGoogle = canonical.replacingOccurrences(of: "google/", with: "")
            append(noGoogle)
            append("openrouter/google/\(noGoogle)")
        default:
            break
        }
        return values
    }

    private func inferProviderPrefix(model: String) -> String? {
        if model.hasPrefix("gpt") || model.hasPrefix("o1") || model.hasPrefix("o3") || model.hasPrefix("o4") {
            return "openai"
        }
        if model.hasPrefix("gemini") { return "google" }
        if model.hasPrefix("claude") { return "anthropic" }
        if model.hasPrefix("deepseek") { return "deepseek" }
        if model.hasPrefix("llama") { return "meta-llama" }
        if model.hasPrefix("qwen") { return "qwen" }
        if model.hasPrefix("mistral") || model.hasPrefix("mixtral") || model.hasPrefix("ministral") {
            return "mistralai"
        }
        if model.hasPrefix("minimax") || model.hasPrefix("abab") {
            return "minimax"
        }
        return nil
    }

    private static let cacheTTLms: Int64 = 12 * 60 * 60 * 1000
}

struct LiteLlmModelCatalogEntry: Sendable {
    var price: LiteLlmModelPrice
    var supportsVision: Bool?

    var hasPricing: Bool {
        price.inputCostPerToken != nil ||
            price.outputCostPerToken != nil ||
            price.outputCostPerReasoningToken != nil ||
            price.cacheReadInputCostPerToken != nil ||
            price.cacheCreationInputCostPerToken != nil
    }
}

struct LiteLlmModelPrice: Sendable {
    var inputCostPerToken: Double?
    var outputCostPerToken: Double?
    var outputCostPerReasoningToken: Double?
    var cacheReadInputCostPerToken: Double?
    var cacheCreationInputCostPerToken: Double?
}

private extension Dictionary where Key == String, Value == Any {
    func doubleValue(for key: String) -> Double? {
        if let value = self[key] as? Double {
            return value
        }
        if let value = self[key] as? NSNumber {
            return value.doubleValue
        }
        if let value = self[key] as? String {
            return Double(value)
        }
        return nil
    }

    func boolValue(for key: String) -> Bool? {
        if let value = self[key] as? Bool {
            return value
        }
        if let value = self[key] as? NSNumber {
            return value.boolValue
        }
        if let value = self[key] as? String {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "1", "yes":
                return true
            case "false", "0", "no":
                return false
            default:
                return nil
            }
        }
        return nil
    }
}
