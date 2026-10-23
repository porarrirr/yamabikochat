import Foundation
import Combine

private let tokenStatsRangeDays: Int64 = 30
private let tokenStatsModelLimit = 12

@MainActor
final class SettingsViewModel: ObservableObject {
    static let disabledSystemPromptSelection = "__SYSTEM_PROMPT_DISABLED__"
    static let newSystemPromptSelection = "__SYSTEM_PROMPT_NEW__"

    @Published var settings: AppSettings = .init()
    @Published var apiKeyDraft: String = ""

    @Published var openRouterModels: [SimpleModel] = []
    @Published var openRouterModelsLoading: Bool = false
    @Published var openRouterModelsError: String?
    @Published var openRouterEndpointOptions: [OpenRouterEndpointOption] = []
    @Published var openRouterEndpointQuantizations: [String] = []
    @Published var openRouterEndpointsLoading: Bool = false
    @Published var openRouterEndpointsError: String?
    @Published var openRouterEndpointModelId: String?
    @Published var modelSearchQuery: String = ""
    @Published var modelsDevCatalogState: CatalogLoadState = .init()
    @Published var customEndpointDraft = OpenAICompatPreset(name: "", baseURL: "")
    @Published var openAICompatApiKeyInput: String = ""
    @Published var geminiKeySlotNameInput: String = ""
    @Published var geminiKeySlotValueInput: String = ""
    @Published var geminiRotationModelInput: String = ""
    @Published var systemPromptPresetNameInput: String = ""
    @Published private(set) var systemPromptPresetValidationMessage: String?
    @Published var alibabaMCPAuthorizationTokenInput: String = ""

    @Published var codexAuthState: CodexAuthState = .init()
    @Published var codexModels: [PiCodexModel] = []
    @Published private(set) var codexModelsLoading = false
    @Published private(set) var codexModelsError: String?
    @Published var codexUsageStatus: CodexUsageStatus?
    @Published var isCodexAuthActionRunning: Bool = false

    @Published var openCodeGoUsageStatus: OpenCodeGoUsageStatus?
    @Published var openCodeGoUsageError: String?
    @Published var openCodeGoUsageLastUpdated: Date?
    @Published var isOpenCodeGoUsageLoading: Bool = false

    @Published var superGrokAuthState: SuperGrokAuthState = .init()
    @Published var isSuperGrokAuthActionRunning: Bool = false
    @Published var superGrokEmailInput: String = ""

    @Published var codexAccountIdInput: String = ""
    @Published var codexEmailInput: String = ""
    @Published var codexPlanTypeInput: String = ""

    @Published var statusMessage: String?
    @Published var errorMessage: String? {
        didSet { isDiagnosticError = false }
    }
    @Published private var isDiagnosticError = false

    /// Input guidance remains visible; technical failures belong in diagnostics.
    var visibleErrorMessage: String? {
        isDiagnosticError ? nil : errorMessage
    }

    func recordFailure(_ error: Error, operation: String = #function) {
        errorMessage = error.localizedDescription
        isDiagnosticError = true
        DiagnosticsLogger.log(operation, level: .error, category: .settings, error: error)
    }
    #if DEBUG
    @Published var diagnosticsLogText: String = ""
    #endif
    @Published var tokenUsageState: TokenUsageUiState = .init()
    @Published private(set) var installedAgentSkills: [InstalledAgentSkill] = []
    @Published var agentSkillInstallPreview: AgentSkillInstallPreview?

    private var repository: ChatRepository?
    private var credentialStore: SecureCredentialStore?
    private var modelsDevCatalogRepository: ModelsDevCatalogRepository?
    private var skillRepository: AgentSkillRepository?
    private var cancellables: Set<AnyCancellable> = []
    private var autoSaveWorkItem: DispatchWorkItem?
    private var modelCatalogPrefetchTask: Task<Void, Never>?
    #if DEBUG
    private var diagnosticsReadTask: Task<Void, Never>?
    #endif
    private var modelsDevFieldCache: [String: String] = [:]
    private var persistedSettingsSnapshot: AppSettings?
    private var isHydratingFromPersistence = false
    private var isPersistingSettings = false
    private var activeOpenRouterModelsFetchID = UUID()
    private var activeOpenRouterEndpointsFetchID = UUID()
    private var activeCodexModelsFetchID = UUID()
    private var apiKeyDraftsByProvider: [String: String] = [:]

    private static let autoSaveDebounceInterval: TimeInterval = 0.5

    func bind(
        repository: ChatRepository,
        credentialStore: SecureCredentialStore,
        modelsDevCatalogRepository: ModelsDevCatalogRepository? = nil,
        skillRepository: AgentSkillRepository? = nil,
        automaticallyRefreshCodexAuth: Bool = true
    ) {
        guard self.repository == nil else { return }
        self.repository = repository
        codexModels = repository.cachedChatGPTModels()
        self.credentialStore = credentialStore
        self.modelsDevCatalogRepository = modelsDevCatalogRepository
        self.skillRepository = skillRepository
        skillRepository?.skillsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.installedAgentSkills = $0 }
            .store(in: &cancellables)

        modelsDevCatalogRepository?.statePublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in self?.modelsDevCatalogState = state }
            .store(in: &cancellables)

        repository.settingsPublisher()
            // The current value is loaded synchronously below. Ignoring the
            // observation's initial snapshot prevents it from overwriting edits
            // made immediately after binding.
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newSettings in
                guard let self else { return }
                guard !self.isPersistingSettings,
                      newSettings != self.persistedSettingsSnapshot,
                      newSettings != self.settings else { return }
                guard self.autoSaveWorkItem == nil else {
                    self.statusMessage = L10n.text("外部の設定変更があります。編集中の内容を保存してから再読み込みしてください。")
                    DiagnosticsLogger.log(
                        "Deferred external settings update while local edits are pending",
                        level: .warning,
                        category: .settings
                    )
                    return
                }
                self.isHydratingFromPersistence = true
                self.settings = newSettings
                self.persistedSettingsSnapshot = newSettings
                self.modelsDevFieldCache.removeAll()
                self.syncSystemPromptPresetName()
                self.loadCurrentProviderAPIKey()
                self.loadAlibabaMCPAuthorizationToken()
                self.isHydratingFromPersistence = false
            }
            .store(in: &cancellables)

        repository.codexAuthStatePublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.codexAuthState = $0
                self?.codexModels = repository.cachedChatGPTModels()
                self?.codexAccountIdInput = $0.accountId ?? ""
                self?.codexEmailInput = $0.email ?? ""
                self?.codexPlanTypeInput = $0.planType ?? ""
            }
            .store(in: &cancellables)

        repository.superGrokAuthStatePublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.superGrokAuthState = $0
                self?.superGrokEmailInput = $0.email ?? ""
            }
            .store(in: &cancellables)

        repository.getOpenRouterModelsPublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] models in
                guard let self else { return }
                openRouterModels = models
                if let modelId = settings.defaultModel.trimmedNonEmpty {
                    reconcileOpenRouterReasoning(forModelId: modelId)
                }
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
            persistedSettingsSnapshot = settings
            loadCurrentProviderAPIKey()
            loadSelectedOpenAICompatApiKey()
            loadAlibabaMCPAuthorizationToken()
            syncSystemPromptPresetName()
        } catch {
            recordFailure(error)
            DiagnosticsLogger.log("Settings load failed", error: error)
        }

        setupAutoSave()

        if automaticallyRefreshCodexAuth {
            Task { await refreshCodexAuth(force: false) }
        }
    }

    func prefetchLatestModelCatalogs() async {
        if let task = modelCatalogPrefetchTask {
            await task.value
            return
        }
        modelsDevFieldCache.removeAll()
        let task = Task {
            async let modelsDevRefresh: CatalogLoadState? = modelsDevCatalogRepository?.load()
            async let openRouterRefresh: Void = refreshOpenRouterModels(force: false)
            // Account discovery handles its own contract load. Cached account
            // models must not wait for an unrelated catalog network refresh.
            async let codexRefresh: Void = refreshCodexModels()
            _ = await (modelsDevRefresh, openRouterRefresh, codexRefresh)
        }
        modelCatalogPrefetchTask = task
        await task.value
        modelCatalogPrefetchTask = nil
    }

    func refreshCodexModels(forceRefresh: Bool = false) async {
        guard let repository else { return }
        codexModels = repository.cachedChatGPTModels()
        let fetchID = UUID()
        activeCodexModelsFetchID = fetchID
        codexModelsLoading = true
        codexModelsError = nil
        defer {
            if activeCodexModelsFetchID == fetchID { codexModelsLoading = false }
        }
        do {
            let models = try await repository.chatGPTModels(forceRefresh: forceRefresh)
            guard activeCodexModelsFetchID == fetchID else { return }
            codexModels = models
        } catch is CancellationError {
            // Account changes invalidate an in-flight catalog result.
        } catch {
            guard activeCodexModelsFetchID == fetchID else { return }
            codexModels = repository.cachedChatGPTModels()
            codexModelsError = error.localizedDescription
            recordFailure(error)
            DiagnosticsLogger.log("ChatGPT account model catalog unavailable", category: .network, error: error)
        }
    }

    func refreshModelsDevCatalog() {
        Task { _ = await modelsDevCatalogRepository?.load(forceRefresh: true) }
    }

    func inspectAgentSkill(at url: URL) {
        guard let skillRepository else { return }
        Task {
            do {
                let preview = try await Task.detached { try skillRepository.inspect(sourceURL: url) }.value
                agentSkillInstallPreview = preview
            } catch {
                recordFailure(error)
                DiagnosticsLogger.log("Agent Skill inspection failed", category: .settings, error: error)
            }
        }
    }

    func installAgentSkill(trusted: Bool, allowReplacement: Bool) {
        guard let skillRepository, let preview = agentSkillInstallPreview else { return }
        do {
            _ = try skillRepository.install(preview, trusted: trusted, allowReplacement: allowReplacement)
            agentSkillInstallPreview = nil
            statusMessage = "Agent Skillをインストールしました。"
        } catch {
            recordFailure(error)
        }
    }

    func discardAgentSkillPreview() {
        if let preview = agentSkillInstallPreview { skillRepository?.discard(preview) }
        agentSkillInstallPreview = nil
    }

    func setAgentSkillEnabled(_ enabled: Bool, name: String) {
        do { try skillRepository?.setEnabled(enabled, name: name) }
        catch { recordFailure(error) }
    }

    func deleteAgentSkill(name: String) {
        do {
            try skillRepository?.delete(name: name)
            statusMessage = "Agent Skillを削除しました。一時コンテナは遅くとも20分で失効します。"
        } catch { recordFailure(error) }
    }

    func modelsDevField(providerID: String, fieldName: String) -> String {
        guard let credentialStore else { return "" }
        let key = modelsDevFieldKey(providerID: providerID, fieldName: fieldName)
        if let cached = modelsDevFieldCache[key] { return cached }
        do {
            let value = try credentialStore.readSecret(key: key) ?? ""
            modelsDevFieldCache[key] = value
            return value
        } catch {
            return ""
        }
    }

    func saveModelsDevFields(providerID: String, fields: [String: String]) {
        do {
            for (name, value) in fields {
                let key = modelsDevFieldKey(providerID: providerID, fieldName: name)
                try credentialStore?.saveSecret(
                    value.trimmingCharacters(in: .whitespacesAndNewlines).trimmedNonEmpty,
                    key: key
                )
                modelsDevFieldCache.removeValue(forKey: key)
            }
            statusMessage = L10n.text("保存しました")
            errorMessage = nil
        } catch {
            recordFailure(error)
        }
    }

    func modelsDevReasoningEffort(providerID: String, modelID: String) -> String {
        modelsDevField(
            providerID: providerID,
            fieldName: ModelsDevReasoningPreference.fieldName(modelID: modelID)
        ).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    func saveModelsDevReasoningEffort(providerID: String, modelID: String, effort: String) {
        let normalized = effort.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let model = modelsDevCatalogState.providers
            .first(where: { $0.id == providerID.lowercased() })?
            .models.first(where: { $0.id == modelID })
        else {
            errorMessage = L10n.text("選択したモデルをmodels.devカタログで確認できません。")
            return
        }
        guard normalized.isEmpty || model.supportedReasoningEfforts.contains(normalized) else {
            errorMessage = L10n.text("このReasoning effortは選択したモデルでサポートされていません。")
            return
        }
        do {
            let key = modelsDevFieldKey(
                providerID: providerID,
                fieldName: ModelsDevReasoningPreference.fieldName(modelID: modelID)
            )
            try credentialStore?.saveSecret(normalized.trimmedNonEmpty, key: key)
            modelsDevFieldCache.removeValue(forKey: key)
            errorMessage = nil
        } catch {
            recordFailure(error)
        }
    }

    private func modelsDevFieldKey(providerID: String, fieldName: String) -> String {
        ModelsDevReasoningPreference.fieldKey(providerID: providerID, fieldName: fieldName)
    }

    func flushPendingSettingsSave() {
        guard autoSaveWorkItem != nil else { return }
        autoSaveWorkItem?.cancel()
        autoSaveWorkItem = nil
        persistSettings(showSuccessMessage: false)
    }

    private func setupAutoSave() {
        $settings
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleAutoSave()
            }
            .store(in: &cancellables)

        $alibabaMCPAuthorizationTokenInput
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleAutoSave()
            }
            .store(in: &cancellables)

        $apiKeyDraft
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] value in
                guard let self else { return }
                self.apiKeyDraftsByProvider[self.settings.apiProvider.uppercased()] = value
                if !self.isHydratingFromPersistence,
                   ModelsDevMergedProvider.isOpenCodeGo(self.settings.apiProvider) {
                    self.openCodeGoUsageCredentialDidChange()
                }
                self.scheduleAutoSave()
            }
            .store(in: &cancellables)

        $openAICompatApiKeyInput
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleAutoSave()
            }
            .store(in: &cancellables)
    }

    private func scheduleAutoSave() {
        guard !isHydratingFromPersistence, !isPersistingSettings else { return }
        autoSaveWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.autoSaveWorkItem = nil
            self?.persistSettings(showSuccessMessage: false)
        }
        autoSaveWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.autoSaveDebounceInterval,
            execute: work
        )
    }

    var filteredOpenRouterModels: [SimpleModel] {
        openRouterModels.filter { $0.matchesSearchQuery(modelSearchQuery) }
    }

    func setStreamingEnabled(_ enabled: Bool) {
        settings.isStreamingEnabled = enabled
    }

    func setClientWebSearchToolEnabled(_ enabled: Bool) {
        settings.clientWebSearchToolEnabled = enabled
        if enabled, settings.apiProvider.caseInsensitiveCompare("GEMINI") == .orderedSame {
            settings.disableGeminiTools()
        }
    }

    func setPythonToolEnabled(_ enabled: Bool) {
        settings.pythonToolEnabled = enabled
        if enabled, settings.apiProvider.caseInsensitiveCompare("GEMINI") == .orderedSame {
            settings.disableGeminiTools()
        }
    }

    func setGenUIToolEnabled(_ enabled: Bool) {
        settings.genUIToolEnabled = enabled
        if enabled, settings.apiProvider.caseInsensitiveCompare("GEMINI") == .orderedSame {
            settings.disableGeminiTools()
        }
    }

    func setGeminiGoogleSearchEnabled(_ enabled: Bool) {
        setGeminiToolEnabled(enabled, at: \AppSettings.geminiGoogleSearchEnabled)
    }

    func setGeminiURLContextEnabled(_ enabled: Bool) {
        setGeminiToolEnabled(enabled, at: \AppSettings.geminiURLContextEnabled)
    }

    func setGeminiCodeExecutionEnabled(_ enabled: Bool) {
        setGeminiToolEnabled(enabled, at: \AppSettings.geminiCodeExecutionEnabled)
    }

    func setGeminiGoogleMapsEnabled(_ enabled: Bool) {
        setGeminiToolEnabled(enabled, at: \AppSettings.geminiGoogleMapsEnabled)
    }

    private func setGeminiToolEnabled(
        _ enabled: Bool,
        at keyPath: WritableKeyPath<AppSettings, Bool>
    ) {
        settings[keyPath: keyPath] = enabled
        if enabled {
            settings.disableClientTools()
        }
    }

    func saveSettings() {
        persistSettings(showSuccessMessage: true)
    }

    private func persistSettings(showSuccessMessage: Bool) {
        guard let repository else { return }
        autoSaveWorkItem?.cancel()
        autoSaveWorkItem = nil
        isPersistingSettings = true
        defer { isPersistingSettings = false }

        do {
            let previousPersistedSettings = try repository.loadSettings()
            let previousMCPToken = try credentialStore.flatMap {
                try $0.readSecret(key: AppConstants.alibabaMCPAuthorizationTokenKey)
            }
            let normalized = settings.normalizedForPersistence()
            let hasInvalidMCP = normalized.alibabaMCPEnabled && normalized.resolvedAlibabaMCPServerURL() == nil
            var persisted = normalized
            if hasInvalidMCP {
                persisted.alibabaMCPEnabled = previousPersistedSettings.alibabaMCPEnabled
                persisted.alibabaMCPServerURL = previousPersistedSettings.alibabaMCPServerURL
                errorMessage = L10n.text("Remote MCP URL に有効な https:// URL を入力してください。")
                if showSuccessMessage {
                    statusMessage = nil
                }
                DiagnosticsLogger.log(
                    "Alibaba MCP settings validation failed because URL is invalid",
                    level: .warning,
                    category: .settings
                )
            }
            if let selected = persisted.selectedSystemPromptPreset,
               !persisted.systemPromptPresets().contains(where: { $0.name.caseInsensitiveCompare(selected) == .orderedSame }) {
                persisted.selectedSystemPromptPreset = nil
            }
            try repository.saveSettings(persisted)
            do {
                try persistCredentialDrafts(includeMCP: !hasInvalidMCP)
            } catch {
                try? repository.saveSettings(previousPersistedSettings)
                try? credentialStore?.saveSecret(
                    previousMCPToken,
                    key: AppConstants.alibabaMCPAuthorizationTokenKey
                )
                throw error
            }
            // Ignore our own database observation even when a rejected MCP draft
            // intentionally differs from the values saved to persistence.
            persistedSettingsSnapshot = persisted
            if !hasInvalidMCP {
                settings = persisted
            }
            if showSuccessMessage {
                statusMessage = L10n.text("保存しました")
            }
            if !hasInvalidMCP {
                errorMessage = nil
            }
        } catch {
            recordFailure(error)
            if showSuccessMessage {
                statusMessage = nil
            }
            DiagnosticsLogger.log("Settings save failed", error: error)
        }
    }

    private func persistCredentialDrafts(includeMCP: Bool = true) throws {
        if includeMCP {
            try credentialStore?.saveSecret(
                alibabaMCPAuthorizationTokenInput.trimmedNonEmpty,
                key: AppConstants.alibabaMCPAuthorizationTokenKey
            )
        }

        let providerKey = settings.apiProvider.uppercased()
        if providerKey != "CODEX_AUTH", providerKey != "SUPERGROK", providerKey != "APPLE_INTELLIGENCE",
           let provider = credentialProvider(for: providerKey) {
            try credentialStore?.setCredential(apiKeyDraft.trimmedNonEmpty, for: provider)
        }

        if providerKey == "OPENAI_COMPAT",
           let repository,
           let preset = settings.selectedOpenAICompatPreset?.trimmedNonEmpty {
            let ok = repository.saveOpenAiCompatApiKey(
                name: preset,
                apiKey: openAICompatApiKeyInput.trimmedNonEmpty
            )
            if !ok {
                throw NSError(
                    domain: "SettingsViewModel",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: L10n.text("OPENAI_COMPAT APIキー保存に失敗しました")]
                )
            }
        }
    }

    func setAlibabaMCPServerURL(_ value: String) {
        settings.alibabaMCPServerURL = value
        statusMessage = nil
    }

    func saveAPIKey() {
        guard let credentialStore else { return }
        guard let provider = credentialProvider(for: settings.apiProvider) else {
            errorMessage = L10n.format("未対応のプロバイダーです: %@", settings.apiProvider)
            return
        }
        do {
            try credentialStore.setCredential(apiKeyDraft.trimmedNonEmpty, for: provider)
            statusMessage = L10n.text("APIキーを保存しました")
            loadCurrentProviderAPIKey()
        } catch {
            recordFailure(error)
            DiagnosticsLogger.log("API key save failed provider=\(settings.apiProvider)", error: error)
        }
    }

    func setProvider(_ provider: String) {
        modelsDevFieldCache.removeAll()
        let nextProvider = provider.uppercased()
        let currentProvider = settings.apiProvider.uppercased()
        apiKeyDraftsByProvider[currentProvider] = apiKeyDraft
        let currentModel = settings.defaultModel.trimmingCharacters(in: .whitespacesAndNewlines)

        var providerMap = settings.providerModelMap()
        if currentModel.isEmpty {
            providerMap.removeValue(forKey: currentProvider)
        } else {
            providerMap[currentProvider] = currentModel
        }

        settings.apiProvider = nextProvider
        if nextProvider == "GEMINI", settings.hasEnabledGeminiTool {
            settings.disableClientTools()
        }
        let nextModel = providerMap[nextProvider] ?? (ProviderReference(persistedID: nextProvider).isModelsDev ? "" : defaultModelForProvider(nextProvider))
        settings.defaultModel = nextModel
        providerMap[nextProvider] = nextModel

        if let data = try? JSONEncoder().encode(providerMap), let json = String(data: data, encoding: .utf8) {
            settings.providerDefaultModelsJSON = json
        }
        if nextProvider == "APPLE_INTELLIGENCE", nextModel == AppleIntelligenceModelCatalog.pccModel, settings.pccReasoningLevel == nil {
            settings.pccReasoningLevel = AppleIntelligenceModelCatalog.defaultPCCReasoningLevel
        }
        if nextProvider == "OPENROUTER" {
            resetOpenRouterEndpointState(forModelId: nextModel)
            reconcileOpenRouterReasoning(forModelId: nextModel)
            Task { await refreshOpenRouterEndpointOptions(forModelId: nextModel, force: false) }
        } else {
            resetOpenRouterEndpointState(forModelId: nil)
        }
        if let draft = apiKeyDraftsByProvider[nextProvider] {
            isHydratingFromPersistence = true
            apiKeyDraft = draft
            isHydratingFromPersistence = false
        } else {
            loadCurrentProviderAPIKey()
        }
    }

    private func scheduleAPIKeyLoad(for provider: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.settings.apiProvider.caseInsensitiveCompare(provider) == .orderedSame else {
                return
            }
            self.loadCurrentProviderAPIKey()
        }
    }

    var openAICompatPresets: [OpenAICompatPreset] {
        settings.openAICompatPresets()
    }

    var systemPromptPresets: [SystemPromptPreset] {
        settings.systemPromptPresets()
    }

    var systemPromptPickerSelection: String {
        if !settings.isSystemPromptEnabled {
            return Self.disabledSystemPromptSelection
        }
        return settings.resolveSelectedSystemPromptPreset()?.name ?? Self.newSystemPromptSelection
    }

    func selectCustomEndpointPreset(_ name: String) {
        settings.selectedOpenAICompatPreset = name.trimmedNonEmpty
        if name.isEmpty { customEndpointDraft = OpenAICompatPreset(name: "", baseURL: "") }
        if let preset = openAICompatPresets.first(where: { $0.name == name }) {
            customEndpointDraft = preset
            if !preset.modelId.isEmpty { setDefaultModel(preset.modelId) }
        }
        loadSelectedOpenAICompatApiKey()
    }

    func addOrUpdateOpenAICompatPreset() {
        var preset = customEndpointDraft
        preset.name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
        preset.baseURL = preset.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        preset.modelId = preset.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        if let error = preset.validationError { errorMessage = error; return }
        var presets = settings.openAICompatPresets()
        if let index = presets.firstIndex(where: { $0.name.caseInsensitiveCompare(preset.name) == .orderedSame }) {
            presets[index] = preset
        } else { presets.append(preset) }
        do {
            settings.openAICompatPresetsJSON = String(decoding: try JSONEncoder().encode(presets), as: UTF8.self)
            customEndpointDraft = preset
            selectCustomEndpointPreset(preset.name)
            statusMessage = "カスタムエンドポイントを保存しました"
        } catch { recordFailure(error) }
    }

    func removeOpenAICompatPreset(name: String) {
        var presets = settings.openAICompatPresets()
        presets.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        if let data = try? JSONEncoder().encode(presets), let json = String(data: data, encoding: .utf8) {
            settings.openAICompatPresetsJSON = json
            if settings.selectedOpenAICompatPreset?.caseInsensitiveCompare(name) == .orderedSame {
                settings.selectedOpenAICompatPreset = nil
                customEndpointDraft = OpenAICompatPreset(name: "", baseURL: "")
                openAICompatApiKeyInput = ""
            }
            statusMessage = L10n.text("OPENAI_COMPATプリセットを削除しました")
        } else {
            DiagnosticsLogger.log("OPENAI_COMPAT preset removal encode failed name=\(name)")
        }
    }

    func saveSelectedOpenAICompatApiKey() {
        guard let repository else { return }
        guard let preset = settings.selectedOpenAICompatPreset?.trimmedNonEmpty else {
            errorMessage = L10n.text("先にOPENAI_COMPATプリセットを選択してください")
            return
        }
        let ok = repository.saveOpenAiCompatApiKey(name: preset, apiKey: openAICompatApiKeyInput.trimmedNonEmpty)
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
        guard let preset = settings.selectedOpenAICompatPreset?.trimmedNonEmpty else { return }
        isHydratingFromPersistence = true
        openAICompatApiKeyInput = repository.peekOpenAiCompatApiKey(name: preset) ?? ""
        isHydratingFromPersistence = false
    }

    var geminiKeySlots: [String] {
        settings.geminiKeyNames()
    }

    var geminiRotationModels: [String] {
        settings.geminiRotationModelsList()
    }

    var geminiRotationCatalogProvider: CatalogProvider? {
        guard let providerID = ModelsDevMergedProvider.catalogID(for: "GEMINI") else { return nil }
        return modelsDevCatalogState.providers.first { $0.id == providerID }
    }

    func addGeminiKeySlot() {
        guard let repository else { return }
        guard let name = geminiKeySlotNameInput.trimmedNonEmpty else {
            errorMessage = L10n.text("キー名を入力してください")
            return
        }
        guard let value = geminiKeySlotValueInput.trimmedNonEmpty else {
            errorMessage = L10n.text("APIキーを入力してください")
            return
        }
        guard repository.saveGeminiApiKey(name: name, apiKey: value) else {
            errorMessage = L10n.text("Gemini APIキー保存に失敗しました")
            DiagnosticsLogger.log("Gemini rotation key save failed name=\(name)")
            return
        }
        var names = settings.geminiKeyNames()
        if !names.contains(name) {
            names.append(name)
            settings.setGeminiKeyNames(names)
        }
        geminiKeySlotNameInput = ""
        geminiKeySlotValueInput = ""
        statusMessage = L10n.text("Gemini APIキーを追加しました")
    }

    func removeGeminiKeySlot(name: String) {
        var names = settings.geminiKeyNames()
        names.removeAll { $0 == name }
        settings.setGeminiKeyNames(names)
        repository?.removeGeminiApiKey(name: name)
    }

    func addGeminiRotationModel(_ model: String) {
        guard let trimmed = model.trimmedNonEmpty else { return }
        var models = settings.geminiRotationModelsList()
        guard !models.contains(trimmed) else { return }
        models.append(trimmed)
        settings.setGeminiRotationModelsList(models)
        geminiRotationModelInput = ""
    }

    func removeGeminiRotationModel(_ model: String) {
        var models = settings.geminiRotationModelsList()
        models.removeAll { $0 == model }
        settings.setGeminiRotationModelsList(models)
    }

    func setDefaultModel(_ modelId: String) {
        settings.defaultModel = modelId
        var map = settings.providerModelMap()
        map[settings.apiProvider.uppercased()] = modelId
        if let data = try? JSONEncoder().encode(map), let json = String(data: data, encoding: .utf8) {
            settings.providerDefaultModelsJSON = json
        }
        if settings.apiProvider.uppercased() == "APPLE_INTELLIGENCE" {
            if modelId == AppleIntelligenceModelCatalog.pccModel {
                if settings.pccReasoningLevel == nil {
                    settings.pccReasoningLevel = AppleIntelligenceModelCatalog.defaultPCCReasoningLevel
                }
            } else if modelId == AppleIntelligenceModelCatalog.displayModel {
                settings.pccReasoningLevel = nil
            }
        }
        guard settings.apiProvider.uppercased() == "OPENROUTER" else { return }
        resetOpenRouterEndpointState(forModelId: modelId)
        reconcileOpenRouterReasoning(forModelId: modelId)
        Task { await refreshOpenRouterEndpointOptions(forModelId: modelId, force: false) }
    }

    func reconcileOpenRouterPreferredProviders(forModelId modelId: String) {
        guard settings.apiProvider.uppercased() == "OPENROUTER" else { return }
        guard openRouterEndpointModelId == modelId else { return }

        let availableTags = Set(openRouterEndpointOptions.map(\.tag))
        let currentProviders = settings.preferredProvidersList()
        let validProviders = currentProviders.filter { availableTags.contains($0.lowercased()) }
        if validProviders != currentProviders {
            settings.setPreferredProvidersList(validProviders)
        }

        let availableQuantizations = Set(openRouterEndpointQuantizations)
        let currentQuantizations = settings.selectedQuantizationsList()
        let validQuantizations = currentQuantizations.compactMap { value -> String? in
            let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return availableQuantizations.contains(normalized) ? normalized : nil
        }
        if validQuantizations != currentQuantizations {
            settings.setSelectedQuantizationsList(validQuantizations)
        }
    }

    func openRouterReasoningCapabilities(forModelId modelId: String) -> OpenRouterReasoningCapabilities? {
        openRouterModels.first(where: { $0.id == modelId })?.reasoning
    }

    func openRouterReasoningModes(forModelId modelId: String) -> [String] {
        guard let capabilities = openRouterReasoningCapabilities(forModelId: modelId) else { return [] }
        var modes = ["auto"]
        if !capabilities.selectableEfforts.isEmpty {
            modes.append("effort")
        }
        if capabilities.supportsMaxTokens {
            modes.append("budget")
        }
        return modes
    }

    func openRouterReasoningEfforts(forModelId modelId: String) -> [String] {
        openRouterReasoningCapabilities(forModelId: modelId)?.selectableEfforts ?? []
    }

    func reconcileOpenRouterReasoning(forModelId modelId: String) {
        guard settings.apiProvider.uppercased() == "OPENROUTER" else { return }
        guard let model = openRouterModels.first(where: { $0.id == modelId }) else { return }
        guard let capabilities = model.reasoning else {
            settings.openRouterThinkingEnabled = false
            settings.openRouterReasoningMode = "auto"
            settings.openRouterReasoningEffort = ""
            return
        }

        if capabilities.mandatory {
            settings.openRouterThinkingEnabled = true
        }

        let modes = openRouterReasoningModes(forModelId: modelId)
        let currentMode = settings.openRouterReasoningMode
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        settings.openRouterReasoningMode = modes.contains(currentMode) ? currentMode : "auto"

        let efforts = capabilities.selectableEfforts
        let currentEffort = settings.openRouterReasoningEffort
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        if efforts.isEmpty {
            settings.openRouterReasoningEffort = ""
        } else if !efforts.contains(currentEffort) {
            settings.openRouterReasoningEffort = preferredOpenRouterEffort(
                capabilities: capabilities,
                explicitlyEnabled: settings.openRouterThinkingEnabled
            ) ?? ""
        }
    }

    func setOpenRouterThinkingEnabled(_ enabled: Bool, modelId: String) {
        guard let capabilities = openRouterReasoningCapabilities(forModelId: modelId) else {
            settings.openRouterThinkingEnabled = false
            return
        }
        settings.openRouterThinkingEnabled = capabilities.mandatory || enabled
        if settings.openRouterThinkingEnabled,
           settings.openRouterReasoningMode == "effort",
           !capabilities.selectableEfforts.contains(settings.openRouterReasoningEffort) {
            settings.openRouterReasoningEffort = preferredOpenRouterEffort(
                capabilities: capabilities,
                explicitlyEnabled: true
            ) ?? ""
        }
    }

    func setOpenRouterReasoningMode(_ mode: String, modelId: String) {
        let normalized = mode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let modes = openRouterReasoningModes(forModelId: modelId)
        settings.openRouterReasoningMode = modes.contains(normalized) ? normalized : "auto"
        guard settings.openRouterReasoningMode == "effort",
              let capabilities = openRouterReasoningCapabilities(forModelId: modelId),
              !capabilities.selectableEfforts.contains(settings.openRouterReasoningEffort)
        else { return }
        settings.openRouterReasoningEffort = preferredOpenRouterEffort(
            capabilities: capabilities,
            explicitlyEnabled: true
        ) ?? ""
    }

    func setOpenRouterReasoningEffort(_ effort: String, modelId: String) {
        let normalized = effort.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let efforts = openRouterReasoningEfforts(forModelId: modelId)
        guard efforts.contains(normalized) else { return }
        settings.openRouterReasoningEffort = normalized
    }

    private func preferredOpenRouterEffort(
        capabilities: OpenRouterReasoningCapabilities,
        explicitlyEnabled: Bool
    ) -> String? {
        let efforts = capabilities.selectableEfforts
        if let defaultEffort = capabilities.defaultEffort?.lowercased(),
           efforts.contains(defaultEffort),
           !(explicitlyEnabled && defaultEffort == "none") {
            return defaultEffort
        }
        return efforts.first(where: { !explicitlyEnabled || $0 != "none" }) ?? efforts.first
    }

    func setDualModeEnabled(_ enabled: Bool) {
        settings.isDualModeEnabled = enabled
        if enabled {
            settings.isAutoConversationEnabled = false
        }
    }

    func initialModelForSlot(for provider: String) -> String {
        if provider.caseInsensitiveCompare("OPENAI_COMPAT") == .orderedSame {
            return settings.openAICompatPresets().first {
                $0.name.caseInsensitiveCompare(settings.selectedOpenAICompatPreset ?? "") == .orderedSame
            }?.modelId ?? ""
        }
        if ProviderReference(persistedID: provider).isModelsDev { return "" }
        return settings.providerModelMap()[provider.uppercased()] ?? ProviderCatalog.defaultModel(for: provider)
    }

    func setAutoConversationEnabled(_ enabled: Bool) {
        settings.isAutoConversationEnabled = enabled
        if enabled {
            settings.isDualModeEnabled = false
        }
    }

    func selectSystemPromptOption(_ selection: String) {
        flushPendingSettingsSave()
        systemPromptPresetValidationMessage = nil
        switch selection {
        case Self.disabledSystemPromptSelection:
            settings.isSystemPromptEnabled = false
        case Self.newSystemPromptSelection:
            settings.isSystemPromptEnabled = true
            settings.selectedSystemPromptPreset = nil
            settings.systemPrompt = nil
            systemPromptPresetNameInput = ""
        default:
            selectSystemPromptPreset(selection)
        }
    }

    func selectSystemPromptPreset(_ name: String?) {
        guard let selected = name?.trimmedNonEmpty,
              let preset = systemPromptPresets.first(where: {
                  $0.name.caseInsensitiveCompare(selected) == .orderedSame
              }) else { return }
        systemPromptPresetValidationMessage = nil
        settings.isSystemPromptEnabled = true
        settings.selectedSystemPromptPreset = preset.name
        settings.systemPrompt = preset.prompt
        systemPromptPresetNameInput = preset.name
    }

    func updateSystemPromptName(_ name: String) {
        systemPromptPresetNameInput = name
        autoSaveSystemPromptPreset()
    }

    func updateSystemPromptText(_ text: String) {
        settings.systemPrompt = text.isEmpty ? nil : text
        autoSaveSystemPromptPreset()
    }

    private func autoSaveSystemPromptPreset() {
        var presets = systemPromptPresets
        let selectedIndex = presets.firstIndex { $0.name == settings.selectedSystemPromptPreset }
        let name: String
        if let input = systemPromptPresetNameInput.trimmedNonEmpty {
            name = input
        } else if let selectedIndex {
            // Keep the preset identity while its name field is temporarily empty.
            name = presets[selectedIndex].name
        } else {
            guard settings.systemPrompt?.trimmedNonEmpty != nil else { return }
            let base = "新しいプリセット"
            var candidate = base
            var suffix = 2
            while presets.contains(where: { $0.name.caseInsensitiveCompare(candidate) == .orderedSame }) {
                candidate = "\(base) \(suffix)"
                suffix += 1
            }
            name = candidate
            systemPromptPresetNameInput = name
        }

        guard !presets.enumerated().contains(where: { index, preset in
            index != selectedIndex && preset.name.caseInsensitiveCompare(name) == .orderedSame
        }) else {
            systemPromptPresetValidationMessage = L10n.text("同じ名前のプリセットがすでにあります")
            // The body still belongs to the selected preset even during an invalid rename.
            if let selectedIndex {
                presets[selectedIndex].prompt = settings.systemPrompt ?? ""
                if let data = try? JSONEncoder().encode(presets), let json = String(data: data, encoding: .utf8) {
                    settings.systemPromptPresetsJSON = json
                }
            }
            return
        }

        let preset = SystemPromptPreset(name: name, prompt: settings.systemPrompt ?? "")
        if let selectedIndex {
            presets[selectedIndex] = preset
        } else {
            presets.append(preset)
        }
        do {
            let data = try JSONEncoder().encode(presets)
            settings.systemPromptPresetsJSON = String(decoding: data, as: UTF8.self)
            settings.selectedSystemPromptPreset = name
            systemPromptPresetValidationMessage = nil
        } catch {
            systemPromptPresetValidationMessage = error.localizedDescription
            DiagnosticsLogger.log("System prompt preset save failed", category: .settings, error: error)
        }
    }

    func removeSelectedSystemPromptPreset() {
        systemPromptPresetValidationMessage = nil
        guard let selected = settings.selectedSystemPromptPreset?.trimmedNonEmpty else { return }
        var presets = systemPromptPresets
        presets.removeAll { $0.name.caseInsensitiveCompare(selected) == .orderedSame }

        if let data = try? JSONEncoder().encode(presets), let json = String(data: data, encoding: .utf8) {
            settings.systemPromptPresetsJSON = json
            settings.selectedSystemPromptPreset = nil
            settings.systemPrompt = nil
            systemPromptPresetNameInput = ""
            statusMessage = L10n.text("システムプロンプトプリセットを削除しました")
        } else {
            errorMessage = L10n.text("システムプロンプトプリセットの削除に失敗しました")
            DiagnosticsLogger.log("System prompt preset remove failed name=\(selected)")
        }
    }

    func refreshDiagnosticsLog() {
        #if DEBUG
        diagnosticsReadTask?.cancel()
        diagnosticsReadTask = Task { [weak self] in
            let text = await Task.detached(priority: .utility) { DiagnosticsLogger.read() }.value
            guard !Task.isCancelled, let self, self.diagnosticsLogText != text else { return }
            self.diagnosticsLogText = text
        }
        #endif
    }

    func clearDiagnosticsLog() {
        #if DEBUG
        diagnosticsReadTask?.cancel()
        DiagnosticsLogger.clear()
        diagnosticsLogText = ""
        statusMessage = L10n.text("診断ログをクリアしました")
        #endif
    }

    func refreshOpenRouterModels(force: Bool) async {
        guard let repository else { return }
        let fetchID = UUID()
        activeOpenRouterModelsFetchID = fetchID
        _ = await repository.getOpenRouterModels(forceRefresh: force)
        guard activeOpenRouterModelsFetchID == fetchID else { return }
        guard settings.apiProvider.uppercased() == "OPENROUTER",
              let modelId = settings.defaultModel.trimmedNonEmpty
        else { return }
        await refreshOpenRouterEndpointOptions(forModelId: modelId, force: force)
    }

    func refreshOpenRouterEndpointOptions(forModelId modelId: String, force: Bool) async {
        guard let repository else { return }
        let normalizedModelId = modelId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedModelId.isEmpty else {
            resetOpenRouterEndpointState(forModelId: nil)
            return
        }

        let fetchID = UUID()
        activeOpenRouterEndpointsFetchID = fetchID
        if openRouterEndpointModelId != normalizedModelId {
            openRouterEndpointOptions = []
            openRouterEndpointQuantizations = []
            openRouterEndpointModelId = nil
        }
        openRouterEndpointsLoading = true
        openRouterEndpointsError = nil

        do {
            let options = try await repository.getOpenRouterModelEndpointOptions(
                normalizedModelId,
                forceRefresh: force
            )
            guard activeOpenRouterEndpointsFetchID == fetchID,
                  settings.apiProvider.uppercased() == "OPENROUTER",
                  settings.defaultModel == normalizedModelId
            else { return }

            openRouterEndpointModelId = normalizedModelId
            openRouterEndpointOptions = options.providerEndpoints
            openRouterEndpointQuantizations = options.quantizations
            openRouterEndpointsLoading = false
            reconcileOpenRouterPreferredProviders(forModelId: normalizedModelId)
        } catch is CancellationError {
            guard activeOpenRouterEndpointsFetchID == fetchID else { return }
            openRouterEndpointsLoading = false
        } catch {
            guard activeOpenRouterEndpointsFetchID == fetchID,
                  settings.apiProvider.uppercased() == "OPENROUTER",
                  settings.defaultModel == normalizedModelId
            else { return }

            openRouterEndpointModelId = normalizedModelId
            openRouterEndpointOptions = []
            openRouterEndpointQuantizations = []
            openRouterEndpointsLoading = false
            openRouterEndpointsError = error.localizedDescription
            DiagnosticsLogger.log(
                "OpenRouter endpoint options refresh failed",
                category: .network,
                metadata: ["model": normalizedModelId],
                error: error
            )
        }
    }

    private func resetOpenRouterEndpointState(forModelId modelId: String?) {
        activeOpenRouterEndpointsFetchID = UUID()
        openRouterEndpointOptions = []
        openRouterEndpointQuantizations = []
        openRouterEndpointsLoading = false
        openRouterEndpointsError = nil
        openRouterEndpointModelId = modelId?.trimmingCharacters(in: .whitespacesAndNewlines).trimmedNonEmpty
    }

    func loginSuperGrokWithBrowser() async {
        guard let repository = requireRepository(action: "supergrok_login_browser") else { return }
        isSuperGrokAuthActionRunning = true
        statusMessage = L10n.text("xAIログインを開始しました")
        errorMessage = nil
        defer { isSuperGrokAuthActionRunning = false }
        let result = await repository.loginSuperGrokWithBrowser()
        switch result {
        case let .success(state):
            superGrokAuthState = state
            superGrokEmailInput = state.email ?? ""
            statusMessage = L10n.text("xAIにログインしました")
        case let .failure(error):
            recordFailure(error)
        }
    }

    func loginSuperGrokWithDeviceCode() async {
        guard let repository = requireRepository(action: "supergrok_login_device_code") else { return }
        isSuperGrokAuthActionRunning = true
        statusMessage = L10n.text("xAI Device Code ログインを開始しました")
        errorMessage = nil
        defer { isSuperGrokAuthActionRunning = false }
        let result = await repository.loginSuperGrokWithDeviceCode()
        switch result {
        case let .success(state):
            superGrokAuthState = state
            superGrokEmailInput = state.email ?? ""
            statusMessage = L10n.text("xAIにログインしました")
        case let .failure(error):
            recordFailure(error)
        }
    }

    func logoutSuperGrok() async {
        guard let repository = requireRepository(action: "supergrok_logout") else { return }
        isSuperGrokAuthActionRunning = true
        errorMessage = nil
        defer { isSuperGrokAuthActionRunning = false }
        let result = await repository.logoutSuperGrok()
        switch result {
        case let .success(state):
            superGrokAuthState = state
            superGrokEmailInput = ""
            statusMessage = state.revocationUnconfirmed
                ? L10n.text("この端末からログアウトしました。xAIの接続解除を確認できませんでした。Grokのアカウント設定で接続済みアプリとセッションを確認してください。")
                : L10n.text("xAIの接続を解除してログアウトしました")
        case let .failure(error):
            recordFailure(error)
            statusMessage = L10n.text("xAIのログアウトを完了できませんでした。アプリを終了し、Grokのアカウント設定で接続済みアプリとセッションを確認してください。")
        }
    }

    func refreshSuperGrok(force: Bool) async {
        guard let repository = requireRepository(action: "supergrok_refresh") else { return }
        isSuperGrokAuthActionRunning = true
        defer { isSuperGrokAuthActionRunning = false }
        let result = await repository.refreshSuperGrok(force: force)
        switch result {
        case let .success(state):
            superGrokAuthState = state
            superGrokEmailInput = state.email ?? ""
            statusMessage = L10n.text("xAIトークンを更新しました")
        case let .failure(error):
            recordFailure(error)
        }
    }

    func loginCodexAuth() async {
        guard let repository = requireRepository(action: "codex_login") else { return }
        isCodexAuthActionRunning = true
        statusMessage = "ChatGPTへの接続を開始しました"
        errorMessage = nil
        activeCodexModelsFetchID = UUID()
        codexModels = []
        codexModelsLoading = false
        codexModelsError = nil
        DiagnosticsLogger.log("Codex auth login tapped", category: .auth)
        refreshDiagnosticsLog()
        defer {
            isCodexAuthActionRunning = false
            refreshDiagnosticsLog()
        }
        let result = await repository.loginCodexAuthWithBrowser()
        guard !Task.isCancelled else {
            statusMessage = nil
            return
        }
        switch result {
        case let .success(state):
            codexAuthState = state
            codexAccountIdInput = state.accountId ?? ""
            codexEmailInput = state.email ?? ""
            codexPlanTypeInput = state.planType ?? ""
            statusMessage = state.planUsageEnabled ? "ChatGPTプランを利用できます" : "ChatGPTに接続しました。プラン利用の許可が必要です。"
            await refreshCodexModels()
            DiagnosticsLogger.log("Codex auth login succeeded accountId=\(state.accountId ?? "-")")
        case let .failure(error):
            recordFailure(error)
            DiagnosticsLogger.log("Codex auth login failed", error: error)
        }
    }

    func logoutCodexAuth() async {
        guard let repository = requireRepository(action: "codex_logout") else { return }
        isCodexAuthActionRunning = true
        errorMessage = nil
        activeCodexModelsFetchID = UUID()
        codexModelsLoading = false
        codexModelsError = nil
        defer {
            isCodexAuthActionRunning = false
            refreshDiagnosticsLog()
        }
        let result = await repository.logoutCodexAuth()
        switch result {
        case let .success(state):
            codexAuthState = state
            codexUsageStatus = nil
            codexModels = []
            statusMessage = state.revocationUnconfirmed
                ? "この端末からログアウトしました。接続解除を確認できなかったため、ChatGPTの設定でアプリを解除してください。"
                : "ChatGPTからログアウトしました"
            DiagnosticsLogger.log("Codex auth logout succeeded")
        case let .failure(error):
            recordFailure(error)
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
            recordFailure(error)
            DiagnosticsLogger.log("Codex auth refresh failed", error: error)
        }
    }

    func openCodeGoUsageCredentialDidChange() {
        openCodeGoUsageStatus = nil
        openCodeGoUsageError = nil
        openCodeGoUsageLastUpdated = nil
    }

    func retrieveOpenCodeGoUsageIfNeeded(apiKey: String) async {
        guard openCodeGoUsageStatus == nil,
              openCodeGoUsageError == nil,
              apiKey.trimmedNonEmpty != nil
        else { return }
        await retrieveOpenCodeGoUsage(apiKey: apiKey)
    }

    func retrieveOpenCodeGoUsage(apiKey: String) async {
        guard !isOpenCodeGoUsageLoading else { return }
        guard let repository = requireRepository(action: "opencode_go_usage"),
              let credentialStore
        else { return }
        guard let apiKey = apiKey.trimmedNonEmpty else {
            statusMessage = nil
            openCodeGoUsageError = L10n.text("OpenCode Go APIキーを入力してください")
            return
        }

        isOpenCodeGoUsageLoading = true
        statusMessage = nil
        openCodeGoUsageError = nil
        defer {
            isOpenCodeGoUsageLoading = false
            refreshDiagnosticsLog()
        }

        do {
            // The visible draft is authoritative when the user taps refresh, even if
            // the settings debounce has not fired yet.
            if ProviderReference(persistedID: settings.apiProvider).modelsDevID == "opencode-go" {
                let key = modelsDevFieldKey(providerID: "opencode-go", fieldName: "OPENCODE_API_KEY")
                try credentialStore.saveSecret(apiKey, key: key)
                modelsDevFieldCache.removeValue(forKey: key)
            } else {
                try credentialStore.setCredential(apiKey, for: .openCodeGo)
            }
        } catch {
            openCodeGoUsageError = error.localizedDescription
            DiagnosticsLogger.log(
                "OpenCode Go API key save failed before usage refresh",
                category: .settings,
                error: error
            )
            return
        }

        let result = await repository.retrieveOpenCodeGoUsage(apiKey: apiKey)
        switch result {
        case let .success(status):
            openCodeGoUsageStatus = status
            openCodeGoUsageLastUpdated = Date()
            statusMessage = L10n.text("OpenCode Go使用状況を更新しました")
            DiagnosticsLogger.log(
                "OpenCode Go usage refresh succeeded",
                category: .network,
                metadata: [
                    "rolling_percent": String(status.rolling.usedPercent),
                    "weekly_percent": String(status.weekly.usedPercent),
                    "monthly_percent": String(status.monthly.usedPercent)
                ]
            )
        case let .failure(error):
            openCodeGoUsageError = error.localizedDescription
            DiagnosticsLogger.log(
                "OpenCode Go usage refresh failed",
                category: .network,
                error: error
            )
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
        let catalogDefault = ProviderCatalog.defaultModel(for: provider)
        return catalogDefault.isEmpty ? settings.modelForProvider(provider.uppercased()) : catalogDefault
    }

    private func syncSystemPromptPresetName() {
        if let selected = settings.selectedSystemPromptPreset?.trimmedNonEmpty {
            systemPromptPresetNameInput = selected
        } else {
            systemPromptPresetNameInput = ""
        }
    }

    private func credentialProvider(for provider: String) -> CredentialProvider? {
        CredentialProvider(rawValue: provider.uppercased())
    }

    private func loadCurrentProviderAPIKey() {
        guard let credentialStore else { return }
        guard !["CODEX_AUTH", "SUPERGROK", "APPLE_INTELLIGENCE"].contains(settings.apiProvider.uppercased()),
              let provider = credentialProvider(for: settings.apiProvider) else {
            isHydratingFromPersistence = true
            apiKeyDraft = ""
            isHydratingFromPersistence = false
            return
        }
        do {
            isHydratingFromPersistence = true
            let providerKey = settings.apiProvider.uppercased()
            let storedValue = try credentialStore.credential(for: provider) ?? ""
            let value = apiKeyDraftsByProvider[providerKey] ?? storedValue
            apiKeyDraft = value
            apiKeyDraftsByProvider[providerKey] = value
            isHydratingFromPersistence = false
        } catch {
            isHydratingFromPersistence = false
            recordFailure(error)
            DiagnosticsLogger.log("API key load failed provider=\(settings.apiProvider)", error: error)
        }
    }

    private func loadAlibabaMCPAuthorizationToken() {
        guard let credentialStore else {
            isHydratingFromPersistence = true
            alibabaMCPAuthorizationTokenInput = ""
            isHydratingFromPersistence = false
            return
        }
        do {
            isHydratingFromPersistence = true
            alibabaMCPAuthorizationTokenInput = try credentialStore.readSecret(
                key: AppConstants.alibabaMCPAuthorizationTokenKey
            ) ?? ""
            isHydratingFromPersistence = false
        } catch {
            isHydratingFromPersistence = false
            recordFailure(error)
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
