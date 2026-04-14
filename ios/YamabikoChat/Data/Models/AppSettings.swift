import Foundation
import GRDB

struct OpenAICompatPreset: Codable, Equatable, Identifiable {
    var id: String { name }
    var name: String
    var baseURL: String

    enum CodingKeys: String, CodingKey {
        case name
        case baseURL
        case baseUrl
    }

    init(name: String, baseURL: String) {
        self.name = name
        self.baseURL = baseURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        baseURL = try container.decodeIfPresent(String.self, forKey: .baseURL)
            ?? container.decodeIfPresent(String.self, forKey: .baseUrl)
            ?? AppConstants.defaultOpenAIBaseURL.absoluteString
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encode(baseURL, forKey: .baseURL)
    }
}

struct SystemPromptPreset: Codable, Equatable, Identifiable {
    var id: String { name }
    var name: String
    var prompt: String
}

struct AppSettings: Codable, FetchableRecord, MutablePersistableRecord, Equatable {
    static let databaseTableName = "settings"

    enum ReasoningContext {
        case `default`
        case dualA
        case dualB
        case autoA
        case autoB
    }

    var id: Int64

    var defaultModel: String
    var apiProvider: String
    var systemPrompt: String?
    var systemPromptPresetsJSON: String
    var selectedSystemPromptPreset: String?

    var isStreamingEnabled: Bool
    var mathRenderingEnabled: Bool

    var dynamicColorEnabled: Bool
    var themeColor: String
    var themeMode: String

    var geminiThinkingEnabled: Bool
    var geminiThinkingBudget: Int
    var geminiThinkingLevel: String
    var geminiGoogleSearchEnabled: Bool
    var geminiCodeExecutionEnabled: Bool
    var geminiURLContextEnabled: Bool
    var geminiGoogleMapsEnabled: Bool
    var geminiComputerUseEnabled: Bool
    var geminiResponseMimeType: String
    var geminiResponseJSONSchema: String
    var geminiFunctionDeclarations: String

    var openRouterThinkingEnabled: Bool
    var openRouterThinkingBudget: Int
    var openRouterReasoningMode: String
    var openRouterReasoningEffort: String
    var openRouterReasoningExclude: Bool
    var openRouterGoogleSearchEnabled: Bool
    var openRouterCodeExecutionEnabled: Bool

    var isDualModeEnabled: Bool
    var dualModelA: String
    var dualModelB: String
    var dualProviderA: String
    var dualProviderB: String
    var dualSystemPromptA: String?
    var dualSystemPromptB: String?
    var dualSplitLayout: String
    var dualSplitRatio: Double
    var dualOpenRouterThinkingEnabledA: Bool?
    var dualOpenRouterThinkingBudgetA: Int?
    var dualOpenRouterReasoningModeA: String?
    var dualOpenRouterReasoningEffortA: String?
    var dualOpenRouterReasoningExcludeA: Bool?
    var dualOpenRouterThinkingEnabledB: Bool?
    var dualOpenRouterThinkingBudgetB: Int?
    var dualOpenRouterReasoningModeB: String?
    var dualOpenRouterReasoningEffortB: String?
    var dualOpenRouterReasoningExcludeB: Bool?
    var dualGoogleSearchEnabledA: Bool?
    var dualCodeExecutionEnabledA: Bool?
    var dualURLContextEnabledA: Bool?
    var dualGoogleMapsEnabledA: Bool?
    var dualComputerUseEnabledA: Bool?
    var dualThinkingEnabledA: Bool?
    var dualThinkingBudgetA: Int?
    var dualThinkingLevelA: String?
    var dualCodexReasoningEffortA: String?
    var dualGoogleSearchEnabledB: Bool?
    var dualCodeExecutionEnabledB: Bool?
    var dualURLContextEnabledB: Bool?
    var dualGoogleMapsEnabledB: Bool?
    var dualComputerUseEnabledB: Bool?
    var dualThinkingEnabledB: Bool?
    var dualThinkingBudgetB: Int?
    var dualThinkingLevelB: String?
    var dualCodexReasoningEffortB: String?

    var isAutoConversationEnabled: Bool
    var autoModelA: String
    var autoModelB: String
    var autoProviderA: String
    var autoProviderB: String
    var autoSystemPromptA: String
    var autoSystemPromptB: String
    var autoMaxTurns: Int
    var autoOpenRouterThinkingEnabledA: Bool?
    var autoOpenRouterThinkingBudgetA: Int?
    var autoOpenRouterReasoningModeA: String?
    var autoOpenRouterReasoningEffortA: String?
    var autoOpenRouterReasoningExcludeA: Bool?
    var autoOpenRouterThinkingEnabledB: Bool?
    var autoOpenRouterThinkingBudgetB: Int?
    var autoOpenRouterReasoningModeB: String?
    var autoOpenRouterReasoningEffortB: String?
    var autoOpenRouterReasoningExcludeB: Bool?
    var autoGoogleSearchEnabledA: Bool?
    var autoCodeExecutionEnabledA: Bool?
    var autoURLContextEnabledA: Bool?
    var autoGoogleMapsEnabledA: Bool?
    var autoComputerUseEnabledA: Bool?
    var autoThinkingEnabledA: Bool?
    var autoThinkingBudgetA: Int?
    var autoThinkingLevelA: String?
    var autoCodexReasoningEffortA: String?
    var autoGoogleSearchEnabledB: Bool?
    var autoCodeExecutionEnabledB: Bool?
    var autoURLContextEnabledB: Bool?
    var autoGoogleMapsEnabledB: Bool?
    var autoComputerUseEnabledB: Bool?
    var autoThinkingEnabledB: Bool?
    var autoThinkingBudgetB: Int?
    var autoThinkingLevelB: String?
    var autoCodexReasoningEffortB: String?

    var providerDefaultModelsJSON: String
    var preferredProvidersJSON: String
    var selectedQuantizationsJSON: String
    var maxPricePerMillionTokens: Double
    var allowFallbacks: Bool
    var requireParameters: Bool
    var providerSelectionMax: Int
    var providerSort: String

    var openAIBaseURL: String
    var miniMaxBaseURL: String
    var openAICompatPresetsJSON: String
    var selectedOpenAICompatPreset: String?
    var alibabaMCPEnabled: Bool
    var alibabaMCPServerURL: String
    var alibabaMCPServerName: String
    var alibabaMCPAllowedToolsCSV: String

    var codexUserAgentPreset: String
    var codexReasoningEnabled: Bool
    var codexReasoningEffort: String
    var codexReasoningSummary: String
    var codexVerbosity: String
    var codexSupportsReasoningSummaries: Bool
    var codexShowReasoningSummary: Bool
    var codexWebSearchEnabled: Bool
    var codexWebSearchContextSize: String
    var codexPromptCacheEnabled: Bool
    var codexPromptCacheMinLength: Int
    var codexPromptCacheType: String

    var showGlobalProviderPresetsInChat: Bool
    var showGlobalProviderPresetsInChatByProviderJSON: String

    var extraJSON: String

    init() {
        id = 1
        defaultModel = "gemini-2.5-flash"
        apiProvider = "GEMINI"
        systemPrompt = nil
        systemPromptPresetsJSON = "[]"
        selectedSystemPromptPreset = nil

        isStreamingEnabled = true
        mathRenderingEnabled = true

        dynamicColorEnabled = true
        themeColor = "BLUE_PURPLE"
        themeMode = "SYSTEM"

        geminiThinkingEnabled = false
        geminiThinkingBudget = 0
        geminiThinkingLevel = ""
        geminiGoogleSearchEnabled = false
        geminiCodeExecutionEnabled = false
        geminiURLContextEnabled = false
        geminiGoogleMapsEnabled = false
        geminiComputerUseEnabled = false
        geminiResponseMimeType = ""
        geminiResponseJSONSchema = ""
        geminiFunctionDeclarations = ""

        openRouterThinkingEnabled = false
        openRouterThinkingBudget = 0
        openRouterReasoningMode = "auto"
        openRouterReasoningEffort = ""
        openRouterReasoningExclude = false
        openRouterGoogleSearchEnabled = false
        openRouterCodeExecutionEnabled = false

        isDualModeEnabled = false
        dualModelA = "gemini-2.5-flash"
        dualModelB = "deepseek/deepseek-chat"
        dualProviderA = "GEMINI"
        dualProviderB = "OPENROUTER"
        dualSystemPromptA = nil
        dualSystemPromptB = nil
        dualSplitLayout = "VERTICAL"
        dualSplitRatio = 0.5
        dualOpenRouterThinkingEnabledA = nil
        dualOpenRouterThinkingBudgetA = nil
        dualOpenRouterReasoningModeA = nil
        dualOpenRouterReasoningEffortA = nil
        dualOpenRouterReasoningExcludeA = nil
        dualOpenRouterThinkingEnabledB = nil
        dualOpenRouterThinkingBudgetB = nil
        dualOpenRouterReasoningModeB = nil
        dualOpenRouterReasoningEffortB = nil
        dualOpenRouterReasoningExcludeB = nil
        dualGoogleSearchEnabledA = nil
        dualCodeExecutionEnabledA = nil
        dualURLContextEnabledA = nil
        dualGoogleMapsEnabledA = nil
        dualComputerUseEnabledA = nil
        dualThinkingEnabledA = nil
        dualThinkingBudgetA = nil
        dualThinkingLevelA = nil
        dualCodexReasoningEffortA = nil
        dualGoogleSearchEnabledB = nil
        dualCodeExecutionEnabledB = nil
        dualURLContextEnabledB = nil
        dualGoogleMapsEnabledB = nil
        dualComputerUseEnabledB = nil
        dualThinkingEnabledB = nil
        dualThinkingBudgetB = nil
        dualThinkingLevelB = nil
        dualCodexReasoningEffortB = nil

        isAutoConversationEnabled = false
        autoModelA = "gemini-2.5-flash"
        autoModelB = "deepseek/deepseek-chat"
        autoProviderA = "GEMINI"
        autoProviderB = "OPENROUTER"
        autoSystemPromptA = L10n.text("あなたは親しみやすい日本語AIアシスタントです。自然で温かみのある会話を心がけてください。")
        autoSystemPromptB = L10n.text("あなたは論理的で分析的なAIアシスタントです。深く考えながら詳細に回答してください。")
        autoMaxTurns = 20
        autoOpenRouterThinkingEnabledA = nil
        autoOpenRouterThinkingBudgetA = nil
        autoOpenRouterReasoningModeA = nil
        autoOpenRouterReasoningEffortA = nil
        autoOpenRouterReasoningExcludeA = nil
        autoOpenRouterThinkingEnabledB = nil
        autoOpenRouterThinkingBudgetB = nil
        autoOpenRouterReasoningModeB = nil
        autoOpenRouterReasoningEffortB = nil
        autoOpenRouterReasoningExcludeB = nil
        autoGoogleSearchEnabledA = nil
        autoCodeExecutionEnabledA = nil
        autoURLContextEnabledA = nil
        autoGoogleMapsEnabledA = nil
        autoComputerUseEnabledA = nil
        autoThinkingEnabledA = nil
        autoThinkingBudgetA = nil
        autoThinkingLevelA = nil
        autoCodexReasoningEffortA = nil
        autoGoogleSearchEnabledB = nil
        autoCodeExecutionEnabledB = nil
        autoURLContextEnabledB = nil
        autoGoogleMapsEnabledB = nil
        autoComputerUseEnabledB = nil
        autoThinkingEnabledB = nil
        autoThinkingBudgetB = nil
        autoThinkingLevelB = nil
        autoCodexReasoningEffortB = nil

        providerDefaultModelsJSON = "{}"
        preferredProvidersJSON = "[]"
        selectedQuantizationsJSON = "[]"
        maxPricePerMillionTokens = 0
        allowFallbacks = true
        requireParameters = false
        providerSelectionMax = 12
        providerSort = "price"

        openAIBaseURL = "https://api.openai.com/v1/"
        miniMaxBaseURL = "https://api.minimax.io/v1/"
        openAICompatPresetsJSON = "[]"
        selectedOpenAICompatPreset = nil
        alibabaMCPEnabled = false
        alibabaMCPServerURL = ""
        alibabaMCPServerName = AppConstants.alibabaMCPDefaultServerName
        alibabaMCPAllowedToolsCSV = ""

        codexUserAgentPreset = "ANDROID"
        codexReasoningEnabled = true
        codexReasoningEffort = "medium"
        codexReasoningSummary = "auto"
        codexVerbosity = "medium"
        codexSupportsReasoningSummaries = false
        codexShowReasoningSummary = true
        codexWebSearchEnabled = false
        codexWebSearchContextSize = "medium"
        codexPromptCacheEnabled = true
        codexPromptCacheMinLength = 512
        codexPromptCacheType = "ephemeral"

        showGlobalProviderPresetsInChat = true
        showGlobalProviderPresetsInChatByProviderJSON = "{}"

        extraJSON = "{}"
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    func currentModel() -> String {
        modelForProvider(apiProvider)
    }

    func normalizedForPersistence() -> AppSettings {
        var normalized = self
        if normalized.isDualModeEnabled && normalized.isAutoConversationEnabled {
            normalized.isAutoConversationEnabled = false
        }
        let layout = normalized.dualSplitLayout
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        normalized.dualSplitLayout = layout == "HORIZONTAL" ? "HORIZONTAL" : "VERTICAL"
        if normalized.dualSplitRatio.isNaN || !normalized.dualSplitRatio.isFinite {
            normalized.dualSplitRatio = 0.5
        } else {
            normalized.dualSplitRatio = min(max(normalized.dualSplitRatio, 0.1), 0.9)
        }

        func normalizedReasoningMode(_ value: String?) -> String? {
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return ["auto", "effort", "budget"].contains(trimmed) ? trimmed : nil
        }

        func normalizedEffort(_ value: String?) -> String? {
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return trimmed.isEmpty ? nil : trimmed
        }

        func normalizedLevel(_ value: String?) -> String? {
            guard let value else { return nil }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }

        normalized.dualOpenRouterReasoningModeA = normalizedReasoningMode(normalized.dualOpenRouterReasoningModeA)
        normalized.dualOpenRouterReasoningModeB = normalizedReasoningMode(normalized.dualOpenRouterReasoningModeB)
        normalized.dualOpenRouterReasoningEffortA = normalizedEffort(normalized.dualOpenRouterReasoningEffortA)
        normalized.dualOpenRouterReasoningEffortB = normalizedEffort(normalized.dualOpenRouterReasoningEffortB)
        normalized.dualCodexReasoningEffortA = normalizedEffort(normalized.dualCodexReasoningEffortA)
        normalized.dualCodexReasoningEffortB = normalizedEffort(normalized.dualCodexReasoningEffortB)
        normalized.autoOpenRouterReasoningModeA = normalizedReasoningMode(normalized.autoOpenRouterReasoningModeA)
        normalized.autoOpenRouterReasoningModeB = normalizedReasoningMode(normalized.autoOpenRouterReasoningModeB)
        normalized.autoOpenRouterReasoningEffortA = normalizedEffort(normalized.autoOpenRouterReasoningEffortA)
        normalized.autoOpenRouterReasoningEffortB = normalizedEffort(normalized.autoOpenRouterReasoningEffortB)
        normalized.autoCodexReasoningEffortA = normalizedEffort(normalized.autoCodexReasoningEffortA)
        normalized.autoCodexReasoningEffortB = normalizedEffort(normalized.autoCodexReasoningEffortB)
        normalized.dualThinkingLevelA = normalizedLevel(normalized.dualThinkingLevelA)
        normalized.dualThinkingLevelB = normalizedLevel(normalized.dualThinkingLevelB)
        normalized.autoThinkingLevelA = normalizedLevel(normalized.autoThinkingLevelA)
        normalized.autoThinkingLevelB = normalizedLevel(normalized.autoThinkingLevelB)
        normalized.alibabaMCPServerURL = normalized.alibabaMCPServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        normalized.alibabaMCPServerName = normalized.alibabaMCPServerName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .ifBlank(AppConstants.alibabaMCPDefaultServerName)
        normalized.alibabaMCPAllowedToolsCSV = normalized.alibabaMCPAllowedToolsCSV
            .split(whereSeparator: \.isNewline)
            .flatMap { $0.split(separator: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, value in
                if !result.contains(where: { $0.caseInsensitiveCompare(value) == .orderedSame }) {
                    result.append(value)
                }
            }
            .joined(separator: ", ")

        if let value = normalized.dualOpenRouterThinkingBudgetA {
            normalized.dualOpenRouterThinkingBudgetA = max(0, value)
        }
        if let value = normalized.dualOpenRouterThinkingBudgetB {
            normalized.dualOpenRouterThinkingBudgetB = max(0, value)
        }
        if let value = normalized.autoOpenRouterThinkingBudgetA {
            normalized.autoOpenRouterThinkingBudgetA = max(0, value)
        }
        if let value = normalized.autoOpenRouterThinkingBudgetB {
            normalized.autoOpenRouterThinkingBudgetB = max(0, value)
        }
        if let value = normalized.dualThinkingBudgetA {
            normalized.dualThinkingBudgetA = max(0, value)
        }
        if let value = normalized.dualThinkingBudgetB {
            normalized.dualThinkingBudgetB = max(0, value)
        }
        if let value = normalized.autoThinkingBudgetA {
            normalized.autoThinkingBudgetA = max(0, value)
        }
        if let value = normalized.autoThinkingBudgetB {
            normalized.autoThinkingBudgetB = max(0, value)
        }
        return normalized
    }

    func toolOverride(for context: ReasoningContext) -> (
        googleSearch: Bool?,
        codeExecution: Bool?,
        urlContext: Bool?,
        googleMaps: Bool?,
        computerUse: Bool?
    ) {
        switch context {
        case .dualA:
            return (
                dualGoogleSearchEnabledA,
                dualCodeExecutionEnabledA,
                dualURLContextEnabledA,
                dualGoogleMapsEnabledA,
                dualComputerUseEnabledA
            )
        case .dualB:
            return (
                dualGoogleSearchEnabledB,
                dualCodeExecutionEnabledB,
                dualURLContextEnabledB,
                dualGoogleMapsEnabledB,
                dualComputerUseEnabledB
            )
        case .autoA:
            return (
                autoGoogleSearchEnabledA,
                autoCodeExecutionEnabledA,
                autoURLContextEnabledA,
                autoGoogleMapsEnabledA,
                autoComputerUseEnabledA
            )
        case .autoB:
            return (
                autoGoogleSearchEnabledB,
                autoCodeExecutionEnabledB,
                autoURLContextEnabledB,
                autoGoogleMapsEnabledB,
                autoComputerUseEnabledB
            )
        case .default:
            return (nil, nil, nil, nil, nil)
        }
    }

    func thinkingOverride(for context: ReasoningContext) -> (
        enabled: Bool?,
        budget: Int?,
        level: String?,
        codexEffort: String?
    ) {
        switch context {
        case .dualA:
            return (
                dualThinkingEnabledA,
                dualThinkingBudgetA,
                dualThinkingLevelA,
                dualCodexReasoningEffortA
            )
        case .dualB:
            return (
                dualThinkingEnabledB,
                dualThinkingBudgetB,
                dualThinkingLevelB,
                dualCodexReasoningEffortB
            )
        case .autoA:
            return (
                autoThinkingEnabledA,
                autoThinkingBudgetA,
                autoThinkingLevelA,
                autoCodexReasoningEffortA
            )
        case .autoB:
            return (
                autoThinkingEnabledB,
                autoThinkingBudgetB,
                autoThinkingLevelB,
                autoCodexReasoningEffortB
            )
        case .default:
            return (nil, nil, nil, nil)
        }
    }

    func openRouterOverride(for context: ReasoningContext) -> (
        enabled: Bool?,
        budget: Int?,
        mode: String?,
        effort: String?,
        exclude: Bool?
    ) {
        switch context {
        case .dualA:
            return (
                dualOpenRouterThinkingEnabledA,
                dualOpenRouterThinkingBudgetA,
                dualOpenRouterReasoningModeA,
                dualOpenRouterReasoningEffortA,
                dualOpenRouterReasoningExcludeA
            )
        case .dualB:
            return (
                dualOpenRouterThinkingEnabledB,
                dualOpenRouterThinkingBudgetB,
                dualOpenRouterReasoningModeB,
                dualOpenRouterReasoningEffortB,
                dualOpenRouterReasoningExcludeB
            )
        case .autoA:
            return (
                autoOpenRouterThinkingEnabledA,
                autoOpenRouterThinkingBudgetA,
                autoOpenRouterReasoningModeA,
                autoOpenRouterReasoningEffortA,
                autoOpenRouterReasoningExcludeA
            )
        case .autoB:
            return (
                autoOpenRouterThinkingEnabledB,
                autoOpenRouterThinkingBudgetB,
                autoOpenRouterReasoningModeB,
                autoOpenRouterReasoningEffortB,
                autoOpenRouterReasoningExcludeB
            )
        case .default:
            return (nil, nil, nil, nil, nil)
        }
    }

    func modelForProvider(_ provider: String) -> String {
        let map = providerModelMap()
        return map[provider.uppercased()] ?? defaultModel
    }

    func providerModelMap() -> [String: String] {
        guard
            let data = providerDefaultModelsJSON.data(using: .utf8),
            let map = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [apiProvider.uppercased(): defaultModel]
        }

        if map[apiProvider.uppercased()] == nil {
            var merged = map
            merged[apiProvider.uppercased()] = defaultModel
            return merged
        }
        return map
    }

    func openAICompatPresets() -> [OpenAICompatPreset] {
        guard
            let data = openAICompatPresetsJSON.data(using: .utf8),
            let list = try? JSONDecoder().decode([OpenAICompatPreset].self, from: data)
        else {
            return []
        }
        return list
    }

    func preferredProvidersList() -> [String] {
        let values = Self.parseStringArray(preferredProvidersJSON)
        return Self.unique(values.map { $0.lowercased() })
    }

    mutating func setPreferredProvidersList(_ providers: [String]) {
        let normalized = Self.unique(
            providers
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty }
        )
        let limited: [String]
        if providerSelectionMax > 0 {
            limited = Array(normalized.prefix(providerSelectionMax))
        } else {
            limited = normalized
        }
        preferredProvidersJSON = Self.encodeStringArray(limited)
    }

    func selectedQuantizationsList() -> [String] {
        let values = Self.parseStringArray(selectedQuantizationsJSON)
        return Self.unique(values)
    }

    mutating func setSelectedQuantizationsList(_ quantizations: [String]) {
        let normalized = Self.unique(
            quantizations
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        )
        selectedQuantizationsJSON = Self.encodeStringArray(normalized)
    }

    func systemPromptPresets() -> [SystemPromptPreset] {
        guard
            let data = systemPromptPresetsJSON.data(using: .utf8),
            let list = try? JSONDecoder().decode([SystemPromptPreset].self, from: data)
        else {
            return []
        }
        return list
    }

    func resolveSelectedSystemPromptPreset() -> SystemPromptPreset? {
        guard let selectedSystemPromptPreset else { return nil }
        return systemPromptPresets().first { $0.name.caseInsensitiveCompare(selectedSystemPromptPreset) == .orderedSame }
    }

    func buildGlobalProviderPresets(includeSystemPrompt: Bool = false) -> [ModelPreset] {
        let models = providerModelMap()
        if models.isEmpty {
            return []
        }

        let preferredOrder = [
            "GEMINI",
            "GEMINI_AUTH",
            "QWEN_CODE",
            "OPENROUTER",
            "ALIBABA_CODING_PLAN",
            "ZAI",
            "MINIMAX",
            "OPENAI",
            "CODEX_AUTH",
            "OPENAI_COMPAT"
        ]
        let orderedProviders =
            preferredOrder.filter { models[$0] != nil } +
            models.keys.filter { !preferredOrder.contains($0) }.sorted()

        let resolvedPrompt: String?
        if includeSystemPrompt {
            resolvedPrompt = resolveSelectedSystemPromptPreset()?.prompt ?? systemPrompt
        } else {
            resolvedPrompt = nil
        }

        return orderedProviders.enumerated().compactMap { index, provider in
            let modelName = (models[provider] ?? modelForProvider(provider))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if modelName.isEmpty {
                return nil
            }
            return ModelPreset(
                id: -Int64(index + 1),
                name: L10n.format("グローバル: %@", ProviderCatalog.displayName(for: provider)),
                model: modelName,
                apiProvider: provider,
                systemPrompt: resolvedPrompt,
                configJSON: "{}",
                createdAtMs: 0
            )
        }
    }

    func showGlobalProviderPresetsInChatByProviderMap() -> [String: Bool] {
        if showGlobalProviderPresetsInChatByProviderJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [:]
        }
        return Self.parseStringKeyedBooleanMap(showGlobalProviderPresetsInChatByProviderJSON)
    }

    func shouldShowGlobalProviderPresetInChat(provider: String) -> Bool {
        let normalized = provider.uppercased()
        let overrides = showGlobalProviderPresetsInChatByProviderMap()
        return overrides[normalized] ?? showGlobalProviderPresetsInChat
    }

    mutating func setShowGlobalProviderPresetInChat(provider: String, visible: Bool) {
        let normalized = provider.uppercased()
        var overrides = showGlobalProviderPresetsInChatByProviderMap()
        overrides[normalized] = visible
        showGlobalProviderPresetsInChatByProviderJSON = Self.encodeStringKeyedBooleanMap(overrides)
    }

    func selectedCompatBaseURL() -> URL? {
        guard let selectedOpenAICompatPreset else { return nil }
        let preset = openAICompatPresets().first { $0.name.caseInsensitiveCompare(selectedOpenAICompatPreset) == .orderedSame }
        guard let preset else { return nil }
        return URL(string: preset.baseURL)
    }

    func resolvedOpenAIBaseURL() -> String {
        Self.resolveBaseURL(
            openAIBaseURL,
            fallback: AppConstants.defaultOpenAIBaseURL.absoluteString
        )
    }

    func resolvedMiniMaxBaseURL() -> String {
        Self.resolveBaseURL(
            miniMaxBaseURL,
            fallback: AppConstants.defaultMiniMaxBaseURL.absoluteString
        )
    }

    func resolvedAlibabaMCPServerURL() -> String? {
        Self.resolveRemoteMCPURL(alibabaMCPServerURL)
    }

    func resolvedAlibabaMCPServerName() -> String {
        alibabaMCPServerName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .ifBlank(AppConstants.alibabaMCPDefaultServerName)
    }

    func alibabaMCPAllowedToolsList() -> [String] {
        alibabaMCPAllowedToolsCSV
            .split(whereSeparator: \.isNewline)
            .flatMap { $0.split(separator: ",") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func resolveBaseURL(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, URL(string: trimmed) != nil else {
            return fallback
        }
        return trimmed
    }

    private static func resolveRemoteMCPURL(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              scheme == "https",
              let host = components.host?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty,
              components.user == nil,
              components.password == nil
        else {
            return nil
        }
        return components.url?.absoluteString
    }

    private static func parseStringArray(_ raw: String) -> [String] {
        guard
            let data = raw.data(using: .utf8),
            let decoded = try? JSONDecoder().decode([String].self, from: data)
        else {
            return []
        }
        return decoded
    }

    private static func encodeStringArray(_ values: [String]) -> String {
        guard
            let data = try? JSONEncoder().encode(values),
            let text = String(data: data, encoding: .utf8)
        else {
            return "[]"
        }
        return text
    }

    private static func parseStringKeyedBooleanMap(_ raw: String) -> [String: Bool] {
        guard let data = raw.data(using: .utf8) else {
            return [:]
        }
        if let decoded = try? JSONDecoder().decode([String: Bool].self, from: data) {
            return decoded.reduce(into: [:]) { result, pair in
                result[pair.key.uppercased()] = pair.value
            }
        }
        if let decodedStrings = try? JSONDecoder().decode([String: String].self, from: data) {
            return decodedStrings.reduce(into: [:]) { result, pair in
                let normalizedValue = pair.value
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                if normalizedValue == "true" {
                    result[pair.key.uppercased()] = true
                } else if normalizedValue == "false" {
                    result[pair.key.uppercased()] = false
                }
            }
        }
        return [:]
    }

    private static func encodeStringKeyedBooleanMap(_ values: [String: Bool]) -> String {
        let normalized = values.reduce(into: [String: Bool]()) { result, pair in
            result[pair.key.uppercased()] = pair.value
        }
        guard
            let data = try? JSONEncoder().encode(normalized),
            let text = String(data: data, encoding: .utf8)
        else {
            return "{}"
        }
        return text
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for value in values {
            if seen.insert(value).inserted {
                result.append(value)
            }
        }
        return result
    }
}

private extension String {
    func ifBlank(_ fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
