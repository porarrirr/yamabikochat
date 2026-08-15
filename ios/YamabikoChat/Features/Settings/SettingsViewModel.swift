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
    @Published var openRouterEndpointOptions: [OpenRouterEndpointOption] = []
    @Published var openRouterEndpointQuantizations: [String] = []
    @Published var openRouterEndpointsLoading: Bool = false
    @Published var openRouterEndpointsError: String?
    @Published var openRouterEndpointModelId: String?
    @Published var modelSearchQuery: String = ""
    @Published var modelsDevCatalogState: CatalogLoadState = .init()
    @Published var openAICompatPresetNameInput: String = ""
    @Published var openAICompatPresetBaseURLInput: String = ""
    @Published var openAICompatApiKeyInput: String = ""
    @Published var geminiKeySlotNameInput: String = ""
    @Published var geminiKeySlotValueInput: String = ""
    @Published var geminiRotationModelInput: String = ""
    @Published var systemPromptPresetNameInput: String = ""
    @Published var alibabaMCPAuthorizationTokenInput: String = ""

    @Published var codexAuthState: CodexAuthState = .init()
    @Published var codexUsageStatus: CodexUsageStatus?
    @Published var isCodexAuthActionRunning: Bool = false

    @Published var superGrokAuthState: SuperGrokAuthState = .init()
    @Published var isSuperGrokAuthActionRunning: Bool = false
    @Published var superGrokEmailInput: String = ""

    @Published var codexAccountIdInput: String = ""
    @Published var codexEmailInput: String = ""
    @Published var codexPlanTypeInput: String = ""

    @Published var statusMessage: String?
    @Published var errorMessage: String?
    @Published var diagnosticsLogText: String = ""
    @Published var tokenUsageState: TokenUsageUiState = .init()
    @Published private(set) var installedAgentSkills: [InstalledAgentSkill] = []
    @Published var agentSkillInstallPreview: AgentSkillInstallPreview?

    private var repository: ChatRepository?
    private var credentialStore: SecureCredentialStore?
    private var modelsDevCatalogRepository: ModelsDevCatalogRepository?
    private var skillRepository: AgentSkillRepository?
    private var cancellables: Set<AnyCancellable> = []
    private var autoSaveWorkItem: DispatchWorkItem?
    private var isHydratingFromPersistence = false
    private var isPersistingSettings = false
    private var activeOpenRouterModelsFetchID = UUID()
    private var activeOpenRouterEndpointsFetchID = UUID()

    private static let autoSaveDebounceInterval: TimeInterval = 0.5

    func bind(
        repository: ChatRepository,
        credentialStore: SecureCredentialStore,
        modelsDevCatalogRepository: ModelsDevCatalogRepository? = nil,
        skillRepository: AgentSkillRepository? = nil
    ) {
        guard self.repository == nil else { return }
        self.repository = repository
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
                guard !self.isPersistingSettings else { return }
                self.isHydratingFromPersistence = true
                self.settings = newSettings
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
            loadCurrentProviderAPIKey()
            loadSelectedOpenAICompatApiKey()
            loadAlibabaMCPAuthorizationToken()
            syncSystemPromptPresetName()
        } catch {
            errorMessage = error.localizedDescription
            DiagnosticsLogger.log("Settings load failed", error: error)
        }

        setupAutoSave()

        Task {
            _ = await modelsDevCatalogRepository?.load(forceRefresh: false)
            await refreshOpenRouterModels(force: false)
            await refreshCodexAuth(force: false)
            refreshDiagnosticsLog()
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
                errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
        }
    }

    func discardAgentSkillPreview() {
        if let preview = agentSkillInstallPreview { skillRepository?.discard(preview) }
        agentSkillInstallPreview = nil
    }

    func setAgentSkillEnabled(_ enabled: Bool, name: String) {
        do { try skillRepository?.setEnabled(enabled, name: name) }
        catch { errorMessage = error.localizedDescription }
    }

    func deleteAgentSkill(name: String) {
        do {
            try skillRepository?.delete(name: name)
            statusMessage = "Agent Skillを削除しました。一時コンテナは遅くとも20分で失効します。"
        } catch { errorMessage = error.localizedDescription }
    }

    func modelsDevField(providerID: String, fieldName: String) -> String {
        guard let credentialStore else { return "" }
        return (try? credentialStore.readSecret(key: modelsDevFieldKey(providerID: providerID, fieldName: fieldName))) ?? ""
    }

    func saveModelsDevFields(providerID: String, fields: [String: String]) {
        if let rawBaseURL = fields["YAMABIKO_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !rawBaseURL.isEmpty,
           (URLComponents(string: rawBaseURL)?.scheme?.lowercased() != "https" || URLComponents(string: rawBaseURL)?.host == nil) {
            errorMessage = L10n.text("Base URL は有効な HTTPS URL を入力してください")
            return
        }
        do {
            for (name, value) in fields {
                try credentialStore?.saveSecret(
                    value.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank,
                    key: modelsDevFieldKey(providerID: providerID, fieldName: name)
                )
            }
            statusMessage = L10n.text("保存しました")
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
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
            try credentialStore?.saveSecret(
                normalized.nilIfBlank,
                key: modelsDevFieldKey(
                    providerID: providerID,
                    fieldName: ModelsDevReasoningPreference.fieldName(modelID: modelID)
                )
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func modelsDevFieldKey(providerID: String, fieldName: String) -> String {
        let provider = providerID.lowercased().replacingOccurrences(of: "[^a-z0-9._-]+", with: "_", options: .regularExpression)
        let field = fieldName.uppercased().replacingOccurrences(of: "[^A-Z0-9_]+", with: "_", options: .regularExpression)
        return "models_dev_\(provider)_\(field)"
    }

    func flushPendingSettingsSave() {
        autoSaveWorkItem?.cancel()
        autoSaveWorkItem = nil
        persistSettings(showSuccessMessage: false)
    }

    private func setupAutoSave() {
        $settings
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleAutoSave()
            }
            .store(in: &cancellables)

        $alibabaMCPAuthorizationTokenInput
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleAutoSave()
            }
            .store(in: &cancellables)

        $apiKeyDraft
            .dropFirst()
            .sink { [weak self] _ in
                self?.scheduleAutoSave()
            }
            .store(in: &cancellables)

        $openAICompatApiKeyInput
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
            self?.persistSettings(showSuccessMessage: false)
        }
        autoSaveWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.autoSaveDebounceInterval,
            execute: work
        )
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
    }

    func saveSettings() {
        persistSettings(showSuccessMessage: true)
    }

    private func persistSettings(showSuccessMessage: Bool) {
        guard let repository else { return }
        isPersistingSettings = true
        defer { isPersistingSettings = false }

        do {
            let previousPersistedSettings = try repository.loadSettings()
            let previousMCPToken = try credentialStore.flatMap {
                try $0.readSecret(key: AppConstants.alibabaMCPAuthorizationTokenKey)
            }
            var normalized = settings.normalizedForPersistence()
            if normalized.alibabaMCPEnabled && normalized.resolvedAlibabaMCPServerURL() == nil {
                errorMessage = L10n.text("Remote MCP URL に有効な https:// URL を入力してください。")
                if showSuccessMessage {
                    statusMessage = nil
                }
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
                try persistCredentialDrafts()
            } catch {
                try? repository.saveSettings(previousPersistedSettings)
                try? credentialStore?.saveSecret(
                    previousMCPToken,
                    key: AppConstants.alibabaMCPAuthorizationTokenKey
                )
                throw error
            }
            settings = normalized
            if showSuccessMessage {
                statusMessage = L10n.text("保存しました")
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            if showSuccessMessage {
                statusMessage = nil
            }
            DiagnosticsLogger.log("Settings save failed", error: error)
        }
    }

    private func persistCredentialDrafts() throws {
        try credentialStore?.saveSecret(
            alibabaMCPAuthorizationTokenInput.nilIfBlank,
            key: AppConstants.alibabaMCPAuthorizationTokenKey
        )

        let providerKey = settings.apiProvider.uppercased()
        if providerKey != "CODEX_AUTH", providerKey != "SUPERGROK", providerKey != "APPLE_INTELLIGENCE",
           let provider = credentialProvider(for: providerKey) {
            try credentialStore?.setCredential(apiKeyDraft.nilIfBlank, for: provider)
        }

        if providerKey == "OPENAI_COMPAT",
           let repository,
           let preset = settings.selectedOpenAICompatPreset?.nilIfBlank {
            let ok = repository.saveOpenAiCompatApiKey(
                name: preset,
                apiKey: openAICompatApiKeyInput.nilIfBlank
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
            : (providerMap[nextProvider] ?? (ProviderReference(persistedID: nextProvider).isModelsDev ? "" : defaultModelForProvider(nextProvider)))
        settings.defaultModel = nextModel
        providerMap[nextProvider] = nextModel

        if let data = try? JSONEncoder().encode(providerMap), let json = String(data: data, encoding: .utf8) {
            settings.providerDefaultModelsJSON = json
        }
        if nextProvider == "OPENROUTER" {
            resetOpenRouterEndpointState(forModelId: nextModel)
            reconcileOpenRouterReasoning(forModelId: nextModel)
            Task { await refreshOpenRouterEndpointOptions(forModelId: nextModel, force: false) }
        } else {
            resetOpenRouterEndpointState(forModelId: nil)
        }
        scheduleAPIKeyLoad(for: nextProvider)
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
        guard let name = geminiKeySlotNameInput.nilIfBlank else {
            errorMessage = L10n.text("キー名を入力してください")
            return
        }
        guard let value = geminiKeySlotValueInput.nilIfBlank else {
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
        guard let trimmed = model.nilIfBlank else { return }
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
            settings.isFusionModeEnabled = false
        }
    }

    func setFusionModeEnabled(_ enabled: Bool) {
        settings.isFusionModeEnabled = enabled
        if enabled {
            settings.isDualModeEnabled = false
            settings.isAutoConversationEnabled = false
            ensureFusionCustomPresetInitialized()
        }
    }

    var fusionCustomPreset: FusionPresetDefinition {
        settings.decodeFusionCustomPreset() ?? AppSettings.defaultFusionCustomPreset()
    }

    func ensureFusionCustomPresetInitialized() {
        if settings.decodeFusionCustomPreset() == nil {
            settings.fusionCustomPresetJSON = settings.encodeFusionCustomPreset(AppSettings.defaultFusionCustomPreset())
        }
    }

    private func saveFusionCustomPreset(_ preset: FusionPresetDefinition) {
        settings.fusionCustomPresetJSON = settings.encodeFusionCustomPreset(
            AppSettings.normalizedFusionPresetDefinition(preset)
        )
    }

    func updateFusionPanelModel(at index: Int, provider: String, modelId: String) {
        guard index >= 0 else { return }
        var preset = fusionCustomPreset
        guard index < preset.panelModels.count else { return }
        preset.panelModels[index].provider = provider.uppercased()
        preset.panelModels[index].modelId = modelId
        saveFusionCustomPreset(preset)
    }

    func addFusionPanel() {
        var preset = fusionCustomPreset
        guard preset.panelModels.count < FusionPresetLoader.maxPanelModelCount else { return }
        let template = preset.panelModels.last ?? PanelModelConfig(
            modelId: "gemini-2.5-flash",
            provider: "GEMINI",
            temperature: nil,
            timeoutMs: nil,
            role: "panel"
        )
        preset.panelModels.append(template)
        saveFusionCustomPreset(preset)
    }

    func removeFusionPanel(at index: Int) {
        var preset = fusionCustomPreset
        guard preset.panelModels.count > 1, index >= 0, index < preset.panelModels.count else { return }
        preset.panelModels.remove(at: index)
        saveFusionCustomPreset(preset)
    }

    func updateFusionJudgeModel(provider: String, modelId: String) {
        var preset = fusionCustomPreset
        preset.judgeModel.provider = provider.uppercased()
        preset.judgeModel.modelId = modelId
        saveFusionCustomPreset(preset)
    }

    func updateFusionSynthesizerModel(provider: String, modelId: String) {
        var preset = fusionCustomPreset
        preset.synthesizerModel.provider = provider.uppercased()
        preset.synthesizerModel.modelId = modelId
        saveFusionCustomPreset(preset)
    }

    func setAutoConversationEnabled(_ enabled: Bool) {
        settings.isAutoConversationEnabled = enabled
        if enabled {
            settings.isDualModeEnabled = false
            settings.isFusionModeEnabled = false
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
        openRouterEndpointModelId = modelId?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfBlank
    }

    func loginSuperGrokWithBrowser() async {
        guard let repository = requireRepository(action: "supergrok_login_browser") else { return }
        isSuperGrokAuthActionRunning = true
        statusMessage = L10n.text("SuperGrokログインを開始しました")
        errorMessage = nil
        defer { isSuperGrokAuthActionRunning = false }
        let result = await repository.loginSuperGrokWithBrowser()
        switch result {
        case let .success(state):
            superGrokAuthState = state
            superGrokEmailInput = state.email ?? ""
            statusMessage = L10n.text("SuperGrokにログインしました")
        case let .failure(error):
            errorMessage = error.localizedDescription
        }
    }

    func loginSuperGrokWithDeviceCode() async {
        guard let repository = requireRepository(action: "supergrok_login_device_code") else { return }
        isSuperGrokAuthActionRunning = true
        statusMessage = L10n.text("SuperGrok Device Code ログインを開始しました")
        errorMessage = nil
        defer { isSuperGrokAuthActionRunning = false }
        let result = await repository.loginSuperGrokWithDeviceCode()
        switch result {
        case let .success(state):
            superGrokAuthState = state
            superGrokEmailInput = state.email ?? ""
            statusMessage = L10n.text("SuperGrokにログインしました")
        case let .failure(error):
            errorMessage = error.localizedDescription
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
            statusMessage = L10n.text("SuperGrokからログアウトしました")
        case let .failure(error):
            errorMessage = error.localizedDescription
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
            statusMessage = L10n.text("SuperGrokトークンを更新しました")
        case let .failure(error):
            errorMessage = error.localizedDescription
        }
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
        let catalogDefault = ProviderCatalog.defaultModel(for: provider)
        return catalogDefault.isEmpty ? settings.modelForProvider(provider.uppercased()) : catalogDefault
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
            isHydratingFromPersistence = true
            apiKeyDraft = ""
            isHydratingFromPersistence = false
            return
        }
        do {
            isHydratingFromPersistence = true
            apiKeyDraft = try credentialStore.credential(for: provider) ?? ""
            isHydratingFromPersistence = false
        } catch {
            isHydratingFromPersistence = false
            errorMessage = error.localizedDescription
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
