import Foundation
import Combine

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

    @Published var codexAuthState: CodexAuthState = .init()
    @Published var geminiAuthState: GeminiAuthState = .init()
    @Published var codexUsageStatus: CodexUsageStatus?
    @Published var geminiUserQuota: GeminiUserQuota?
    @Published var isCodexAuthActionRunning: Bool = false
    @Published var isGeminiAuthActionRunning: Bool = false

    @Published var codexApiKeyInput: String = ""
    @Published var codexAccessTokenInput: String = ""
    @Published var codexAccountIdInput: String = ""
    @Published var codexEmailInput: String = ""
    @Published var codexPlanTypeInput: String = ""

    @Published var geminiAccessTokenInput: String = ""
    @Published var geminiProjectIdInput: String = ""
    @Published var geminiEmailInput: String = ""
    @Published var geminiTierInput: String = ""
    @Published var geminiTierNameInput: String = ""

    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var diagnosticsLogText: String = ""

    private var repository: ChatRepository?
    private var credentialStore: SecureCredentialStore?
    private var cancellables: Set<AnyCancellable> = []
    private let geminiOAuthMissingMessage =
        "Gemini OAuth client ID/secret が未設定です。Info.plist の GEMINI_OAUTH_CLIENT_ID / GEMINI_OAUTH_CLIENT_SECRET を設定してください。"

    var isGeminiOAuthConfigured: Bool {
        if let repository {
            return repository.isGeminiOAuthClientConfigured()
        }
        return GeminiAuthRepository.isDefaultOAuthClientConfigured()
    }

    func bind(repository: ChatRepository, credentialStore: SecureCredentialStore) {
        guard self.repository == nil else { return }
        self.repository = repository
        self.credentialStore = credentialStore

        repository.settingsPublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.settings = $0
                self?.syncSystemPromptPresetName()
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

        repository.geminiAuthStatePublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.geminiAuthState = $0
                self?.geminiProjectIdInput = $0.projectId ?? ""
                self?.geminiEmailInput = $0.email ?? ""
                self?.geminiTierInput = $0.userTier ?? ""
                self?.geminiTierNameInput = $0.userTierName ?? ""
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

        do {
            settings = try repository.loadSettings()
            loadSelectedOpenAICompatApiKey()
            syncSystemPromptPresetName()
        } catch {
            errorMessage = error.localizedDescription
            DiagnosticsLogger.log("Settings load failed", error: error)
        }

        Task {
            await refreshOpenRouterModels(force: false)
            await refreshCodexAuth(force: false)
            await refreshGeminiAuth(force: false)
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

    func saveSettings() {
        guard let repository else { return }
        do {
            var normalized = settings.normalizedForPersistence()
            if let selected = normalized.selectedSystemPromptPreset,
               !normalized.systemPromptPresets().contains(where: { $0.name.caseInsensitiveCompare(selected) == .orderedSame }) {
                normalized.selectedSystemPromptPreset = nil
            }
            settings = normalized
            try repository.saveSettings(normalized)
            statusMessage = "保存しました"
        } catch {
            errorMessage = error.localizedDescription
            DiagnosticsLogger.log("Settings save failed", error: error)
        }
    }

    func saveAPIKey() {
        guard let credentialStore else { return }
        do {
            let provider = CredentialProvider(rawValue: settings.apiProvider.uppercased()) ?? .gemini
            try credentialStore.setCredential(apiKeyDraft.isEmpty ? nil : apiKeyDraft, for: provider)
            statusMessage = "APIキーを保存しました"
            apiKeyDraft = ""
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
        let nextModel = providerMap[nextProvider] ?? defaultModelForProvider(nextProvider)
        settings.defaultModel = nextModel
        providerMap[nextProvider] = nextModel

        if let data = try? JSONEncoder().encode(providerMap), let json = String(data: data, encoding: .utf8) {
            settings.providerDefaultModelsJSON = json
        }
    }

    var openAICompatPresets: [OpenAICompatPreset] {
        settings.openAICompatPresets()
    }

    var systemPromptPresets: [SystemPromptPreset] {
        settings.systemPromptPresets()
    }

    func addOrUpdateOpenAICompatPreset() {
        guard let name = openAICompatPresetNameInput.nilIfBlank else {
            errorMessage = "プリセット名を入力してください"
            return
        }
        guard let base = openAICompatPresetBaseURLInput.nilIfBlank else {
            errorMessage = "Base URLを入力してください"
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
            statusMessage = "OPENAI_COMPATプリセットを保存しました"
        } else {
            errorMessage = "プリセットの保存に失敗しました"
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
            statusMessage = "OPENAI_COMPATプリセットを削除しました"
        } else {
            DiagnosticsLogger.log("OPENAI_COMPAT preset removal encode failed name=\(name)")
        }
    }

    func saveSelectedOpenAICompatApiKey() {
        guard let repository else { return }
        guard let preset = settings.selectedOpenAICompatPreset?.nilIfBlank else {
            errorMessage = "先にOPENAI_COMPATプリセットを選択してください"
            return
        }
        let ok = repository.saveOpenAiCompatApiKey(name: preset, apiKey: openAICompatApiKeyInput.nilIfBlank)
        if ok {
            statusMessage = "OPENAI_COMPAT APIキーを保存しました"
            openAICompatApiKeyInput = ""
        } else {
            errorMessage = "OPENAI_COMPAT APIキー保存に失敗しました"
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
            errorMessage = "プリセット名を入力してください"
            return
        }
        guard let prompt = settings.systemPrompt?.nilIfBlank else {
            errorMessage = "システムプロンプトを入力してください"
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
            statusMessage = "システムプロンプトプリセットを保存しました"
        } else {
            errorMessage = "システムプロンプトプリセットの保存に失敗しました"
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
            statusMessage = "システムプロンプトプリセットを削除しました"
        } else {
            errorMessage = "システムプロンプトプリセットの削除に失敗しました"
            DiagnosticsLogger.log("System prompt preset remove failed name=\(selected)")
        }
    }

    func refreshDiagnosticsLog() {
        diagnosticsLogText = DiagnosticsLogger.read()
    }

    func clearDiagnosticsLog() {
        DiagnosticsLogger.clear()
        diagnosticsLogText = ""
        statusMessage = "診断ログをクリアしました"
    }

    func refreshOpenRouterModels(force: Bool) async {
        guard let repository else { return }
        _ = await repository.getOpenRouterModels(forceRefresh: force)
    }

    func loginCodexAuth() async {
        guard let repository = requireRepository(action: "codex_login") else { return }
        isCodexAuthActionRunning = true
        statusMessage = "Codexログインを開始しました"
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
            statusMessage = "Codexにログインしました"
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
            statusMessage = "Codexからログアウトしました"
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
            statusMessage = "Codex使用量を更新しました"
            DiagnosticsLogger.log("Codex usage refresh succeeded")
        case let .failure(error):
            errorMessage = error.localizedDescription
            DiagnosticsLogger.log("Codex usage refresh failed", error: error)
        }
    }

    func loginGeminiAuth() async {
        guard let repository = requireRepository(action: "gemini_login") else { return }
        guard isGeminiOAuthConfigured else {
            statusMessage = nil
            errorMessage = geminiOAuthMissingMessage
            DiagnosticsLogger.log(
                "Gemini auth login blocked because oauth client config is missing",
                level: .warning,
                category: .auth
            )
            refreshDiagnosticsLog()
            return
        }
        isGeminiAuthActionRunning = true
        statusMessage = "Geminiログインを開始しました"
        errorMessage = nil
        DiagnosticsLogger.log("Gemini auth login tapped", category: .auth)
        refreshDiagnosticsLog()
        defer {
            isGeminiAuthActionRunning = false
            refreshDiagnosticsLog()
        }
        let result = await repository.loginGeminiAuthWithBrowser()
        switch result {
        case let .success(state):
            geminiAuthState = state
            geminiProjectIdInput = state.projectId ?? ""
            geminiEmailInput = state.email ?? ""
            geminiTierInput = state.userTier ?? ""
            geminiTierNameInput = state.userTierName ?? ""
            statusMessage = "Geminiにログインしました"
            DiagnosticsLogger.log("Gemini auth login succeeded project=\(state.projectId ?? "-")")
        case let .failure(error):
            errorMessage = error.localizedDescription
            DiagnosticsLogger.log("Gemini auth login failed", error: error)
        }
    }

    func logoutGeminiAuth() async {
        guard let repository = requireRepository(action: "gemini_logout") else { return }
        isGeminiAuthActionRunning = true
        errorMessage = nil
        defer {
            isGeminiAuthActionRunning = false
            refreshDiagnosticsLog()
        }
        let result = await repository.logoutGeminiAuth()
        switch result {
        case let .success(state):
            geminiAuthState = state
            geminiUserQuota = nil
            statusMessage = "Geminiからログアウトしました"
            DiagnosticsLogger.log("Gemini auth logout succeeded")
        case let .failure(error):
            errorMessage = error.localizedDescription
            DiagnosticsLogger.log("Gemini auth logout failed", error: error)
        }
    }

    func refreshGeminiAuth(force: Bool) async {
        guard let repository = requireRepository(action: "gemini_refresh") else { return }
        isGeminiAuthActionRunning = true
        defer {
            isGeminiAuthActionRunning = false
            refreshDiagnosticsLog()
        }
        let result = await repository.refreshGeminiAuth(force: force)
        switch result {
        case let .success(state):
            geminiAuthState = state
        case let .failure(error):
            errorMessage = error.localizedDescription
            DiagnosticsLogger.log("Gemini auth refresh failed", error: error)
        }
    }

    func retrieveGeminiQuota() async {
        guard let repository = requireRepository(action: "gemini_quota") else { return }
        isGeminiAuthActionRunning = true
        defer {
            isGeminiAuthActionRunning = false
            refreshDiagnosticsLog()
        }
        let result = await repository.retrieveGeminiAuthQuota()
        switch result {
        case let .success(quota):
            geminiUserQuota = quota
            statusMessage = "Geminiクォータを更新しました"
            DiagnosticsLogger.log("Gemini quota refresh succeeded buckets=\(quota.buckets.count)")
        case let .failure(error):
            if Self.isGeminiQuotaMissingCredentialError(error) {
                geminiUserQuota = nil
                errorMessage = nil
                statusMessage = "Geminiにログインするとクォータを取得できます"
                DiagnosticsLogger.log(
                    "Gemini quota refresh skipped: missing GEMINI_AUTH credential",
                    level: .info
                )
            } else {
                errorMessage = error.localizedDescription
                DiagnosticsLogger.log("Gemini quota refresh failed", error: error)
            }
        }
    }

    func saveGeminiProjectId() {
        guard let repository = requireRepository(action: "gemini_save_project_id") else { return }
        let ok = repository.saveGeminiAuthProjectId(geminiProjectIdInput.nilIfBlank)
        if ok {
            statusMessage = "Gemini Project IDを保存しました"
        } else {
            errorMessage = "Gemini Project IDの保存に失敗しました"
            DiagnosticsLogger.log("Gemini project id save failed")
            refreshDiagnosticsLog()
        }
    }

    private func requireRepository(action: String) -> ChatRepository? {
        guard let repository else {
            errorMessage = "設定画面の初期化が完了していません。画面を開き直して再試行してください。"
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
        case "GEMINI", "GEMINI_AUTH":
            return "gemini-2.5-flash"
        case "MINIMAX":
            return "MiniMax-M2.1"
        case "CODEX_AUTH":
            return CodexModelCatalog.defaultModel()
        default:
            return settings.modelForProvider(provider.uppercased())
        }
    }

    private func syncSystemPromptPresetName() {
        if let selected = settings.selectedSystemPromptPreset?.nilIfBlank {
            systemPromptPresetNameInput = selected
        }
    }

    static func isGeminiQuotaMissingCredentialError(_ error: Error) -> Bool {
        guard let providerError = error as? ProviderClientError else { return false }
        if case let .missingCredential(provider) = providerError {
            return provider.uppercased() == "GEMINI_AUTH"
        }
        return false
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
