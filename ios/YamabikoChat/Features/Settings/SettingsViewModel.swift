import Foundation
import Combine

private let tokenStatsRangeDays: Int64 = 30
private let tokenStatsModelLimit = 12

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var settings: AppSettings = .init()
    @Published var apiKeyDraft: String = ""

    @Published var openRouterModels: [SimpleModel] = []
    @Published var openRouterModelsLoading: Bool = false
    @Published var openRouterModelsError: String?
    @Published var modelSearchQuery: String = ""
    @Published var openAICompatPresetNameInput: String = ""
    @Published var openAICompatPresetBaseURLInput: String = ""
    @Published var openAICompatApiKeyInput: String = ""
    @Published var systemPromptPresetNameInput: String = ""
    @Published var alibabaMCPAuthorizationTokenInput: String = ""

    @Published var codexAuthState: CodexAuthState = .init()
    @Published var codexUsageStatus: CodexUsageStatus?
    @Published var isCodexAuthActionRunning: Bool = false

    @Published var codexApiKeyInput: String = ""
    @Published var codexAccessTokenInput: String = ""
    @Published var codexAccountIdInput: String = ""
    @Published var codexEmailInput: String = ""
    @Published var codexPlanTypeInput: String = ""

    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var diagnosticsLogText: String = ""
    @Published var tokenUsageState: TokenUsageUiState = .init()

    private var repository: ChatRepository?
    private var credentialStore: SecureCredentialStore?
    private var cancellables: Set<AnyCancellable> = []

    func bind(repository: ChatRepository, credentialStore: SecureCredentialStore) {
        guard self.repository == nil else { return }
        self.repository = repository
        self.credentialStore = credentialStore

        repository.settingsPublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.settings = $0
                self?.syncSystemPromptPresetName()
                self?.loadCurrentProviderAPIKey()
                self?.loadAlibabaMCPAuthorizationToken()
            }
            .store(in: &cancellables)

        repository.codexAuthStatePublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.codexAuthState = $0
                self?.codexAccountIdInput = $0.accountId ?? ""
                self?.codexEmailInput = $0.email ?? ""
                self?.codexPlanTypeInput = $0.planType ?? ""
            }
            .store(in: &cancellables)

        repository.getOpenRouterModelsPublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.openRouterModels = $0
            }
            .store(in: &cancellables)

        repository.getOpenRouterModelsLoadingPublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.openRouterModelsLoading = $0
            }
            .store(in: &cancellables)

        repository.getOpenRouterModelsErrorPublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.openRouterModelsError = $0
            }
            .store(in: &cancellables)

        let nowMs = Int64(Date().timeIntervalSince1970 * 1000)
        let sinceMs = nowMs - tokenStatsRangeDays * 24 * 60 * 60 * 1000
        Publishers.CombineLatest3(
            repository.observeTokenUsageTotals(sinceEpochMs: sinceMs),
            repository.observeTokenUsageByModel(sinceEpochMs: sinceMs, limit: tokenStatsModelLimit),
            repository.observeTokenUsageDaily(sinceEpochMs: sinceMs)
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] totals, byModel, daily in
            self?.tokenUsageState = TokenUsageUiState(
                rangeDays: Int(tokenStatsRangeDays),
                totals: totals,
                byModel: byModel,
                daily: daily,
                lastUpdated: Date()
            )
        }
        .store(in: &cancellables)

        do {
            settings = try repository.loadSettings()
            loadCurrentProviderAPIKey()
            loadSelectedOpenAICompatApiKey()
            loadAlibabaMCPAuthorizationToken()
            syncSystemPromptPresetName()
        } catch {
            errorMessage = error.localizedDescription
            DiagnosticsLogger.log("Settings load failed", error: error)
        }

        Task {
            await refreshOpenRouterModels(force: false)
            await refreshCodexAuth(force: false)
            refreshDiagnosticsLog()
        }
    }

    var filteredOpenRouterModels: [SimpleModel] {
        let query = modelSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty { return openRouterModels }
        let lower = query.lowercased()
        return openRouterModels.filter {
            $0.id.lowercased().contains(lower) ||
                $0.name.lowercased().contains(lower) ||
                $0.provider.lowercased().contains(lower)
        }
    }

    func setStreamingEnabled(_ enabled: Bool) {
        settings.isStreamingEnabled = enabled
        guard let repository else { return }
        do {
            let normalized = settings.normalizedForPersistence()
            try repository.saveSettings(normalized)
            settings = normalized
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            DiagnosticsLogger.log("Streaming setting save failed", error: error)
        }
    }

    func saveSettings() {
        guard let repository else { return }
        do {
            let previousPersistedSettings = try repository.loadSettings()
            let previousMCPToken = try credentialStore.flatMap {
                try $0.readSecret(key: AppConstants.alibabaMCPAuthorizationTokenKey)
            }
            var normalized = settings.normalizedForPersistence()
            if normalized.alibabaMCPEnabled && normalized.resolvedAlibabaMCPServerURL() == nil {
                errorMessage = L10n.text("Remote MCP URL に有効な https:// URL を入力してください。")
                statusMessage = nil
                DiagnosticsLogger.log(
                    "Alibaba MCP settings validation failed because URL is invalid",
                    level: .warning,
                    category: .settings
                )
                return
            }
            if let selected = normalized.selectedSystemPromptPreset,
               !normalized.systemPromptPresets().contains(where: { $0.name.caseInsensitiveCompare(selected) == .orderedSame }) {
                normalized.selectedSystemPromptPreset = nil
            }
            try repository.saveSettings(normalized)
            do {
                try credentialStore?.saveSecret(
                    alibabaMCPAuthorizationTokenInput.nilIfBlank,
                    key: AppConstants.alibabaMCPAuthorizationTokenKey
                )
            } catch {
                try? repository.saveSettings(previousPersistedSettings)
                try? credentialStore?.saveSecret(
                    previousMCPToken,
                    key: AppConstants.alibabaMCPAuthorizationTokenKey
                )
                throw error
            }
            settings = normalized
            statusMessage = L10n.text("保存しました")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = nil
            DiagnosticsLogger.log("Settings save failed", error: error)
        }
    }

    func setAlibabaMCPServerURL(_ value: String) {
        let previousIdentity = normalizedAlibabaMCPServerURLIdentity(settings.alibabaMCPServerURL)
        settings.alibabaMCPServerURL = value
        let nextIdentity = normalizedAlibabaMCPServerURLIdentity(value)
        guard previousIdentity != nextIdentity else { return }
        alibabaMCPAuthorizationTokenInput = ""
        statusMessage = nil
    }

    func saveAPIKey() {
        guard let credentialStore else { return }
        guard let provider = credentialProvider(for: settings.apiProvider) else {
            errorMessage = L10n.format("未対応のプロバイダーです: %@", settings.apiProvider)
            return
        }
        do {
            try credentialStore.setCredential(apiKeyDraft.nilIfBlank, for: provider)
            statusMessage = L10n.text("APIキーを保存しました")
            loadCurrentProviderAPIKey()
        } catch {
            errorMessage = error.localizedDescription
            DiagnosticsLogger.log("API key save failed provider=\(settings.apiProvider)", error: error)
        }
    }

    func setProvider(_ provider: String) {
        let nextProvider = provider.uppercased()
        let currentProvider = settings.apiProvider.uppercased()
        let currentModel = settings.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)

        var providerMap = settings.providerModelMap()
        if currentModel.isEmpty {
            providerMap.removeValue(forKey: currentProvider)
        } else {
            providerMap[currentProvider] = currentModel
        }

        settings.apiProvider = nextProvider
        let nextModel = nextProvider == "APPLE_INTELLIGENCE"
            ? AppleIntelligenceModelCatalog.displayModel
            : (providerMap[nextProvider] ?? defaultModelForProvider(nextProvider))
        settings.defaultModel = nextModel
        providerMap[nextProvider] = nextModel

        if let data = try? JSONEncoder().encode(providerMap), let json = String(data: data, encoding: .utf8) {
            settings.providerDefaultModelsJSON = json
        }
        loadCurrentProviderAPIKey()
    }

    var openAICompatPresets: [OpenAICompatPreset] {
        settings.openAICompatPresets()
    }

    var systemPromptPresets: [SystemPromptPreset] {
        settings.systemPromptPresets()
    }

    func addOrUpdateOpenAICompatPreset() {
        guard let name = openAICompatPresetNameInput.nilIfBlank else {
            errorMessage = L10n.text("プリセット名を入力してください")
            return
        }
        guard let base = openAICompatPresetBaseURLInput.nilIfBlank else {
            errorMessage = L10n.text("Base URLを入力してください")
            return
        }

        var presets = settings.openAICompatPresets()
        if let index = presets.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            presets[index] = OpenAICompatPreset(name: name, baseURL: base)
        } else {
            presets.append(OpenAICompatPreset(name: name, baseURL: base))
        }

        if let data = try? JSONEncoder().encode(presets), let json = String(data: data, encoding: .utf8) {
            settings.openAICompatPresetsJSON = json
            if settings.selectedOpenAICompatPreset?.isEmpty != false {
                settings.selectedOpenAICompatPreset = name
            }
            statusMessage = L10n.text("OPENAI_COMPATプリセットを保存しました")
        } else {
            errorMessage = L10n.text("プリセットの保存に失敗しました")
            DiagnosticsLogger.log("OPENAI_COMPAT preset save failed")
        }
    }

    func removeOpenAICompatPreset(name: String) {
        var presets = settings.openAICompatPresets()
        presets.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        if let data = try? JSONEncoder().encode(presets), let json = String(data: data, encoding: .utf8) {
            settings.openAICompatPresetsJSON = json
            if settings.selectedOpenAICompatPreset?.caseInsensitiveCompare(name) == .orderedSame {
                settings.selectedOpenAICompatPreset = presets.first?.name
            }
            statusMessage = L10n.text("OPENAI_COMPATプリセットを削除しました")
        } else {
            DiagnosticsLogger.log("OPENAI_COMPAT preset removal encode failed name=\(name)")
        }
    }

    func saveSelectedOpenAICompatApiKey() {
        guard let repository else { return }
        guard let preset = settings.selectedOpenAICompatPreset?.nilIfBlank else {
            errorMessage = L10n.text("先にOPENAI_COMPATプリセットを選択してください")
            return
        }
        let ok = repository.saveOpenAiCompatApiKey(name: preset, apiKey: openAICompatApiKeyInput.nilIfBlank)
        if ok {
            statusMessage = L10n.text("OPENAI_COMPAT APIキーを保存しました")
            openAICompatApiKeyInput = ""
        } else {
            errorMessage = L10n.text("OPENAI_COMPAT APIキー保存に失敗しました")
            DiagnosticsLogger.log("OPENAI_COMPAT API key save failed name=\(preset)")
        }
    }

    func loadSelectedOpenAICompatApiKey() {
        guard let repository else { return }
        guard let preset = settings.selectedOpenAICompatPreset?.nilIfBlank else { return }
        openAICompatApiKeyInput = repository.peekOpenAiCompatApiKey(name: preset) ?? ""
    }

    func setDefaultModel(_ modelId: String) {
        settings.defaultModel = modelId
        var map = settings.providerModelMap()
        map[settings.apiProvider.uppercased()] = modelId
        if let data = try? JSONEncoder().encode(map), let json = String(data: data, encoding: .utf8) {
            settings.providerDefaultModelsJSON = json
        }
    }

    func setDualModeEnabled(_ enabled: Bool) {
        settings.isDualModeEnabled = enabled
        if enabled {
            settings.isAutoConversationEnabled = false
        }
    }

    func setAutoConversationEnabled(_ enabled: Bool) {
        settings.isAutoConversationEnabled = enabled
        if enabled {
            settings.isDualModeEnabled = false
        }
    }

    func selectSystemPromptPreset(_ name: String?) {
        guard let selected = name?.nilIfBlank else {
            settings.selectedSystemPromptPreset = nil
            return
        }
        guard let preset = systemPromptPresets.first(where: { $0.name.caseInsensitiveCompare(selected) == .orderedSame }) else {
            settings.selectedSystemPromptPreset = nil
            return
        }
        settings.selectedSystemPromptPreset = preset.name
        settings.systemPrompt = preset.prompt
        systemPromptPresetNameInput = preset.name
    }

    func addOrUpdateSystemPromptPreset() {
        guard let name = systemPromptPresetNameInput.nilIfBlank else {
            errorMessage = L10n.text("プリセット名を入力してください")
            return
        }
        guard let prompt = settings.systemPrompt?.nilIfBlank else {
            errorMessage = L10n.text("システムプロンプトを入力してください")
            return
        }

        var presets = systemPromptPresets
        if let index = presets.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            presets[index] = SystemPromptPreset(name: name, prompt: prompt)
        } else {
            presets.append(SystemPromptPreset(name: name, prompt: prompt))
        }

        if let data = try? JSONEncoder().encode(presets), let json = String(data: data, encoding: .utf8) {
            settings.systemPromptPresetsJSON = json
            settings.selectedSystemPromptPreset = name
            statusMessage = L10n.text("システムプロンプトプリセットを保存しました")
        } else {
            errorMessage = L10n.text("システムプロンプトプリセットの保存に失敗しました")
            DiagnosticsLogger.log("System prompt preset save failed")
        }
    }

    func removeSelectedSystemPromptPreset() {
        guard let selected = settings.selectedSystemPromptPreset?.nilIfBlank else { return }
        var presets = systemPromptPresets
        presets.removeAll { $0.name.caseInsensitiveCompare(selected) == .orderedSame }

        if let data = try? JSONEncoder().encode(presets), let json = String(data: data, encoding: .utf8) {
            settings.systemPromptPresetsJSON = json
            settings.selectedSystemPromptPreset = nil
            systemPromptPresetNameInput = ""
            statusMessage = L10n.text("システムプロンプトプリセットを削除しました")
        } else {
            errorMessage = L10n.text("システムプロンプトプリセットの削除に失敗しました")
            DiagnosticsLogger.log("System prompt preset remove failed name=\(selected)")
        }
    }

    func refreshDiagnosticsLog() {
        diagnosticsLogText = DiagnosticsLogger.read()
    }

    func clearDiagnosticsLog() {
        DiagnosticsLogger.clear()
        diagnosticsLogText = ""
        statusMessage = L10n.text("診断ログをクリアしました")
    }

    func refreshOpenRouterModels(force: Bool) async {
        guard let repository else { return }
        _ = await repository.getOpenRouterModels(forceRefresh: force)
    }

    func loginCodexAuth() async {
        guard let repository = requireRepository(action: "codex_login") else { return }
        isCodexAuthActionRunning = true
        statusMessage = L10n.text("Codexログインを開始しました")
        errorMessage = nil
        DiagnosticsLogger.log("Codex auth login tapped", category: .auth)
        refreshDiagnosticsLog()
        defer {
            isCodexAuthActionRunning = false
            refreshDiagnosticsLog()
        }
        let result = await repository.loginCodexAuthWithBrowser()
        switch result {
        case let .success(state):
            codexAuthState = state
            codexAccountIdInput = state.accountId ?? ""
            codexEmailInput = state.email ?? ""
            codexPlanTypeInput = state.planType ?? ""
            statusMessage = L10n.text("Codexにログインしました")
            DiagnosticsLogger.log("Codex auth login succeeded accountId=\(state.accountId ?? "-")")
        case let .failure(error):
            errorMessage = error.localizedDescription
            DiagnosticsLogger.log("Codex auth login failed", error: error)
        }
    }

    func logoutCodexAuth() async {
        guard let repository = requireRepository(action: "codex_logout") else { return }
        isCodexAuthActionRunning = true
        errorMessage = nil
        defer {
            isCodexAuthActionRunning = false
            refreshDiagnosticsLog()
        }
        let result = await repository.logoutCodexAuth()
        switch result {
        case let .success(state):
            codexAuthState = state
            codexUsageStatus = nil
            statusMessage = L10n.text("Codexからログアウトしました")
            DiagnosticsLogger.log("Codex auth logout succeeded")
        case let .failure(error):
            errorMessage = error.localizedDescription
            DiagnosticsLogger.log("Codex auth logout failed", error: error)
        }
    }

    func refreshCodexAuth(force: Bool) async {
        guard let repository = requireRepository(action: "codex_refresh") else { return }
        isCodexAuthActionRunning = true
        defer {
            isCodexAuthActionRunning = false
            refreshDiagnosticsLog()
        }
        let result = await repository.refreshCodexAuth(force: force)
        switch result {
        case let .success(state):
            codexAuthState = state
        case let .failure(error):
            errorMessage = error.localizedDescription
            DiagnosticsLogger.log("Codex auth refresh failed", error: error)
        }
    }

    func retrieveCodexUsage() async {
        guard let repository = requireRepository(action: "codex_usage") else { return }
        isCodexAuthActionRunning = true
        defer {
            isCodexAuthActionRunning = false
            refreshDiagnosticsLog()
        }
        let result = await repository.retrieveCodexAuthUsage()
        switch result {
        case let .success(status):
            codexUsageStatus = status
            statusMessage = L10n.text("Codex使用量を更新しました")
            DiagnosticsLogger.log("Codex usage refresh succeeded")
        case let .failure(error):
            errorMessage = error.localizedDescription
            DiagnosticsLogger.log("Codex usage refresh failed", error: error)
        }
    }

    private func requireRepository(action: String) -> ChatRepository? {
        guard let repository else {
            errorMessage = L10n.text("設定画面の初期化が完了していません。画面を開き直して再試行してください。")
            DiagnosticsLogger.log(
                "Settings action ignored because repository is not bound action=\(action)",
                level: .warning,
                category: .settings
            )
            refreshDiagnosticsLog()
            return nil
        }
        return repository
    }

    private func defaultModelForProvider(_ provider: String) -> String {
        switch provider.uppercased() {
        case "GEMINI":
            return "gemini-2.5-flash"
        case "ALIBABA_CODING_PLAN":
            return AlibabaCodingPlanModelCatalog.defaultModel
        case "OPENCODE_GO":
            return OpenCodeGoModelCatalog.defaultModel
        case "MINIMAX":
            return "MiniMax-M2.1"
        case "CODEX_AUTH":
            return CodexModelCatalog.defaultModel()
        case "APPLE_INTELLIGENCE":
            return AppleIntelligenceModelCatalog.displayModel
        default:
            return settings.modelForProvider(provider.uppercased())
        }
    }

    private func syncSystemPromptPresetName() {
        if let selected = settings.selectedSystemPromptPreset?.nilIfBlank {
            systemPromptPresetNameInput = selected
        }
    }

    private func credentialProvider(for provider: String) -> CredentialProvider? {
        CredentialProvider(rawValue: provider.uppercased())
    }

    private func loadCurrentProviderAPIKey() {
        guard let credentialStore else { return }
        guard let provider = credentialProvider(for: settings.apiProvider) else {
            apiKeyDraft = ""
            return
        }
        do {
            apiKeyDraft = try credentialStore.credential(for: provider) ?? ""
        } catch {
            errorMessage = error.localizedDescription
            DiagnosticsLogger.log("API key load failed provider=\(settings.apiProvider)", error: error)
        }
    }

    private func loadAlibabaMCPAuthorizationToken() {
        guard let credentialStore else {
            alibabaMCPAuthorizationTokenInput = ""
            return
        }
        do {
            alibabaMCPAuthorizationTokenInput = try credentialStore.readSecret(
                key: AppConstants.alibabaMCPAuthorizationTokenKey
            ) ?? ""
        } catch {
            errorMessage = error.localizedDescription
            DiagnosticsLogger.log("Alibaba MCP authorization token load failed", error: error)
        }
    }

    private func normalizedAlibabaMCPServerURLIdentity(_ value: String) -> String? {
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

}

struct TokenUsageUiState: Equatable {
    var rangeDays: Int = Int(tokenStatsRangeDays)
    var totals: TokenUsageTotals = .init()
    var byModel: [TokenUsageByModel] = []
    var daily: [TokenUsageDailyPoint] = []
    var lastUpdated: Date?
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
