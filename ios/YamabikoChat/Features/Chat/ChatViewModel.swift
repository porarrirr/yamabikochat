import Combine
import Foundation

@MainActor
final class ChatViewModel: ObservableObject {
    let timelineStore = ChatTimelineStore()
    let composerStore = ChatComposerStore()
    let sessionController = ChatSessionController()
    @Published private(set) var messageSummaries: [ChatMessageSummary] = []
    @Published private(set) var fullMessages: [FullChatMessage] = []
    @Published private(set) var dualMessages: [DualChatMessage] = []
    @Published private(set) var settings: AppSettings = .init()

    @Published var inputText: String = ""
    @Published private(set) var speechAudioLevels = SpeechAudioLevelHistory().values
    @Published var isSending: Bool = false
    @Published var isAutoConversationRunning: Bool = false
    @Published var isAutoConversationPaused: Bool = false
    @Published var autoConversationStatus: String?
    @Published private(set) var generationStatus: String?
    @Published var fusionStreamingStatus: String?
    @Published var fusionProgress: FusionProgressSnapshot?
    @Published var errorMessage: String?
    var attachments: [AttachmentDraft] {
        get { composerStore.attachments }
        set { composerStore.attachments = newValue }
    }
    private(set) var isSpeechRecording: Bool {
        get { composerStore.isSpeechRecording }
        set { composerStore.isSpeechRecording = newValue }
    }
    @Published private(set) var activeChatPresetName: String?
    @Published private(set) var activeSystemPromptPresetName: String?
    @Published private(set) var contextUsage: ContextUsage?
    @Published private(set) var reasoningEffortConfiguration: ChatReasoningEffortConfiguration?
    private(set) var canAttachImages: Bool {
        get { composerStore.canAttachImages }
        set { composerStore.canAttachImages = newValue }
    }
    @Published private(set) var isSecretConversation: Bool = false
    @Published private(set) var conversationTitle: String = "New Chat"
    @Published private(set) var enabledSkillNames: [String] = []
    @Published private(set) var conversationStats: ConversationStats = .init()

    let speechService = SpeechRecognitionService()

    private let conversationID: Int64
    private var repository: ChatRepository?
    private var attachmentRepository: AttachmentRepository?
    private var cancellables: Set<AnyCancellable> = []
    private var autoConversationTask: Task<Void, Never>?
    private var activeSendTask: Task<Void, Never>?
    private var activeSendID: UUID?
    private var activeAutoConversationID: Int64?
    @Published private(set) var conversationSystemPrompt: String?
    private var lastSettingsSnapshot: AppSettings?
    private var inputTextBeforeSpeech: String = ""
    private var latestTokenUsageRecord: TokenUsageRecord?
    private var activeConversationProvider: String = ""
    private var activeConversationModel: String = ""

    init(conversationID: Int64) {
        self.conversationID = conversationID
        composerStore.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
        sessionController.onSnapshot = { [weak self] snapshot in
            self?.timelineStore.applyStreamingSnapshot(snapshot)
        }
        sessionController.onClear = { [weak self] in
            self?.timelineStore.clearTransientStreamingSnapshots()
        }
        speechService.onTranscription = { [weak self] text in
            guard let self else { return }
            if self.inputTextBeforeSpeech.isEmpty {
                self.inputText = text
            } else {
                self.inputText = self.inputTextBeforeSpeech + " " + text
            }
        }
        speechService.$error
            .compactMap { $0 }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] speechError in
                self?.errorMessage = speechError.localizedDescription
                DiagnosticsLogger.log(
                    "Speech recognition error",
                    category: .app,
                    error: speechError
                )
            }
            .store(in: &cancellables)

        speechService.$isRecording
            .receive(on: DispatchQueue.main)
            .sink { [weak self] isRecording in
                self?.isSpeechRecording = isRecording
            }
            .store(in: &cancellables)

        speechService.$audioLevels
            .receive(on: DispatchQueue.main)
            .sink { [weak self] levels in
                self?.speechAudioLevels = levels
            }
            .store(in: &cancellables)
    }

    deinit {
        autoConversationTask?.cancel()
        activeSendTask?.cancel()
    }

    func bind(repository: ChatRepository, attachmentRepository: AttachmentRepository, skillRepository: AgentSkillRepository? = nil) {
        guard self.repository == nil else { return }
        self.repository = repository
        self.attachmentRepository = attachmentRepository

        skillRepository?.skillsPublisher
            .map { $0.filter(\.isEnabled).map { $0.manifest.name }.sorted() }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.enabledSkillNames = $0 }
            .store(in: &cancellables)

        repository.reasoningEffortCatalogPublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.refreshReasoningEffortConfiguration() }
            .store(in: &cancellables)

        repository.observeMessages(conversationId: conversationID)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.messageSummaries = $0
            }
            .store(in: &cancellables)

        repository.observeFullMessages(conversationId: conversationID)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.fullMessages = $0
                self?.timelineStore.update(messages: $0)
            }
            .store(in: &cancellables)

        repository.observeDualMessages(conversationId: conversationID)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.dualMessages = $0
                self?.timelineStore.update(dualMessages: $0)
            }
            .store(in: &cancellables)

        repository.observeConversationStats(conversationId: conversationID)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.conversationStats = $0 }
            .store(in: &cancellables)

        repository.observeLatestTokenUsage(conversationId: conversationID)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] record in
                self?.latestTokenUsageRecord = record
                self?.rebuildContextUsage()
            }
            .store(in: &cancellables)

        repository.settingsPublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                let previous = self.lastSettingsSnapshot
                self.lastSettingsSnapshot = $0
                self.settings = $0
                if !$0.isAutoConversationEnabled && (self.isAutoConversationRunning || self.isAutoConversationPaused) {
                    self.stopAutoConversation()
                }
                self.syncNewChatWithSettingsIfEmpty(settings: $0, previousSettings: previous)
                self.updateActiveChatPresetName()
                self.updateActiveSystemPromptPresetName()
                self.refreshReasoningEffortConfiguration()
                Task { [weak self] in
                    await self?.refreshVisionSupport()
                }
            }
            .store(in: &cancellables)

        do {
            if let conversation = try repository.conversation(id: conversationID) {
                conversationSystemPrompt = conversation.systemPrompt
                activeConversationProvider = conversation.apiProvider
                activeConversationModel = conversation.model
                isSecretConversation = conversation.isSecret
                conversationTitle = conversation.title
                updateActiveChatPresetName()
                updateActiveSystemPromptPresetName()
                refreshReasoningEffortConfiguration()
                Task { [weak self] in
                    await self?.refreshVisionSupport()
                    await self?.refreshReasoningEffortCatalog()
                }
            }
        } catch {
            DiagnosticsLogger.log(
                "Load conversation failed conversation=\(conversationID)",
                category: .chat,
                error: error
            )
        }
    }

    var skillAutocompleteSuggestions: [String] {
        guard let match = inputText.range(of: #"(?:^|\s)\$([a-z0-9-]*)$"#, options: .regularExpression),
              let dollar = inputText[match].lastIndex(of: "$") else { return [] }
        let prefix = String(inputText[inputText.index(after: dollar)...])
        return enabledSkillNames.filter { prefix.isEmpty || $0.hasPrefix(prefix) }.prefix(6).map { $0 }
    }

    var visibleContextUsage: ContextUsage? {
        guard !settings.isDualModeEnabled,
              !settings.isFusionModeEnabled,
              !settings.isAutoConversationEnabled else { return nil }
        return contextUsage
    }

    func selectSkillAutocomplete(_ name: String) {
        guard let match = inputText.range(of: #"(?:^|\s)\$([a-z0-9-]*)$"#, options: .regularExpression),
              let dollar = inputText[match].lastIndex(of: "$") else { return }
        inputText.replaceSubrange(dollar..<inputText.endIndex, with: "$\(name) ")
    }

    func applySharedText(_ text: String?) {
        guard let text, !text.isEmpty else { return }
        inputText = text
    }

    func exportConversation(mode: ConversationExportMode = .standard) async throws -> URL {
        guard let repository else {
            throw ProviderClientError.parseFailure(
                L10n.text("チャット初期化中です。少し待ってから再試行してください。")
            )
        }
        return try await repository.exportConversation(id: conversationID, mode: mode)
    }

    @discardableResult
    func addAttachment(
        url: URL,
        displayName: String? = nil,
        deleteSourceWhenHandled: Bool = false
    ) -> Bool {
        defer {
            if deleteSourceWhenHandled {
                try? FileManager.default.removeItem(at: url)
            }
        }
        guard let attachmentRepository else {
            errorMessage = L10n.text("チャット初期化中です。少し待ってから再試行してください。")
            DiagnosticsLogger.log(
                "Attachment repository not bound conversation=\(conversationID)",
                level: .warning,
                category: .chat
            )
            return false
        }
        switch attachmentRepository.validate(url: url) {
        case .valid:
            if attachmentRepository.requiresVision(url: url), !canAttachImages {
                errorMessage = L10n.text("このモデルは画像入力に対応していません。")
                return false
            }
            do {
                let persistedURL = try attachmentRepository.persistAttachment(url: url)
                attachments.append(
                    AttachmentDraft(url: persistedURL, displayName: displayName ?? url.lastPathComponent)
                )
                errorMessage = nil
                return true
            } catch {
                errorMessage = L10n.text("ファイルを読み込めませんでした。")
                DiagnosticsLogger.log(
                    "Persist attachment failed conversation=\(conversationID) file=\(url.lastPathComponent)",
                    category: .chat,
                    error: error
                )
                return false
            }
        case let .tooLarge(sizeBytes):
            let sizeMB = Double(sizeBytes) / (1024 * 1024)
            errorMessage = L10n.format("添付ファイルが%.1fMBで上限10MBを超えています。", sizeMB)
        case .unsupportedType:
            errorMessage = L10n.text("サポート外のファイル形式です。")
        case .dangerousFile:
            errorMessage = L10n.text("危険なファイル形式は添付できません。")
        case .unreadable:
            errorMessage = L10n.text("ファイルを読み込めませんでした。")
        }
        if let errorMessage {
            DiagnosticsLogger.log(
                "Attachment validation failed",
                category: .chat,
                error: ProviderClientError.parseFailure(errorMessage)
            )
        }
        return false
    }

    func removeAttachment(id: UUID) {
        attachments.removeAll { $0.id == id }
        errorMessage = nil
    }

    func clearErrorMessage() {
        errorMessage = nil
    }

    func clearAttachments() {
        attachments.removeAll()
        errorMessage = nil
    }

    func toggleSpeechRecognition() {
        if isSpeechRecording {
            stopSpeechRecognition()
        } else {
            inputTextBeforeSpeech = inputText
            speechService.startRecording()
        }
    }

    func cancelSpeechRecognition() {
        speechService.stopRecording()
        inputText = inputTextBeforeSpeech
    }

    func stopSpeechRecognition() {
        speechService.stopRecording()
    }

    func sendMessage() {
        guard !isSending else { return }
        // Stop immediately to prevent late-start recording after send.
        speechService.stopRecording()
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || !attachments.isEmpty else { return }
        guard let repository else {
            errorMessage = L10n.text("チャット初期化中です。少し待ってから再試行してください。")
            return
        }

        let text = trimmedText
        inputText = ""

        isSending = true
        errorMessage = nil

        let attachmentDrafts = attachments
        attachments = []
        let runSettings = settings
        let runStartedAtMs = Int64(Date().timeIntervalSince1970 * 1_000)
        let isAutoConversationEnabled = runSettings.isAutoConversationEnabled
        let shouldStartAutoConversation = isAutoConversationEnabled && AutoConversationTrigger.matches(text)
        let runID = UUID()
        activeSendID = runID

        activeSendTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.activeSendID == runID {
                    self.clearStreamingState()
                    self.generationStatus = nil
                    self.fusionStreamingStatus = nil
                    self.fusionProgress = nil
                    self.isSending = false
                    self.activeSendID = nil
                    self.activeSendTask = nil
                }
            }
            do {
                // Provider requests use filesystem paths. Serializing these URLs with
                // absoluteString would produce `file:///...`, which is not a path and
                // causes the Pi runtime to look for a non-existent file.
                let attachmentPaths = attachmentDrafts.map { $0.url.path }

                if runSettings.isFusionModeEnabled {
                    guard !text.isEmpty || !attachmentPaths.isEmpty else {
                        errorMessage = L10n.text("Fusion モードでは本文または添付を入力してください。")
                        attachments = attachmentDrafts
                        return
                    }
                    fusionProgress = nil
                    _ = try await repository.sendFusionMessage(
                        conversationId: conversationID,
                        text: text,
                        attachments: attachmentPaths,
                        settingsOverride: runSettings,
                        onFusionProgress: { [self] snapshot in
                            Task { @MainActor in
                                guard self.activeSendID == runID else { return }
                                self.fusionProgress = snapshot
                            }
                        },
                        onStreamEvent: { [self] event in
                            guard case let .reasoningDelta(delta) = event else { return }
                            Task { @MainActor in
                                guard self.activeSendID == runID else { return }
                                let reasoningStatus = delta.isEmpty ? nil : L10n.text("推論中...")
                                self.fusionStreamingStatus = reasoningStatus
                                if var progress = self.fusionProgress {
                                    progress.substatus = reasoningStatus
                                    self.fusionProgress = progress
                                }
                            }
                        },
                        onStreamingSnapshot: { [self] snapshot in
                            Task { @MainActor in
                                guard self.activeSendID == runID else { return }
                                self.handleStreamingSnapshot(snapshot)
                            }
                        }
                    )
                    fusionStreamingStatus = nil
                    fusionProgress = nil
                } else if runSettings.isDualModeEnabled {
                    guard !text.isEmpty || !attachmentPaths.isEmpty else {
                        errorMessage = L10n.text("デュアルモードでは本文または添付を入力してください。")
                        attachments = attachmentDrafts
                        return
                    }
                    _ = try await repository.sendDualMessage(
                        conversationId: conversationID,
                        text: text,
                        attachments: attachmentPaths,
                        settingsOverride: runSettings
                    )
                } else if shouldStartAutoConversation,
                          !isAutoConversationRunning,
                          !isAutoConversationPaused {
                    try repository.sendUserMessageOnly(
                        conversationId: conversationID,
                        text: text,
                        attachments: attachmentPaths
                    )
                    startAutoConversation(initialMessage: text, insertSeedInChat: false)
                } else {
                    _ = try await repository.sendMessage(
                        conversationId: conversationID,
                        text: text,
                        attachments: attachmentPaths,
                        settingsOverride: runSettings,
                        onStreamEvent: { [self] event in
                            guard case let .reasoningDelta(delta) = event else { return }
                            Task { @MainActor in
                                guard self.activeSendID == runID else { return }
                                self.generationStatus = delta.isEmpty ? self.generationStatus : L10n.text("推論中...")
                            }
                        },
                        onStreamingSnapshot: { [self] snapshot in
                            Task { @MainActor in
                                guard self.activeSendID == runID else { return }
                                self.handleStreamingSnapshot(snapshot)
                            }
                        }
                    )
                }
                refreshConversationTitle()
            } catch is CancellationError {
                restoreDraftIfUncommitted(
                    repository: repository,
                    text: text,
                    attachmentDrafts: attachmentDrafts,
                    settings: runSettings,
                    startedAtMs: runStartedAtMs
                )
            } catch {
                errorMessage = error.localizedDescription
                restoreDraftIfUncommitted(
                    repository: repository,
                    text: text,
                    attachmentDrafts: attachmentDrafts,
                    settings: runSettings,
                    startedAtMs: runStartedAtMs
                )
                DiagnosticsLogger.log(
                    "Send message failed conversation=\(conversationID)",
                    category: .chat,
                    error: error
                )
            }
        }
    }

    func cancelActiveRun() {
        activeSendTask?.cancel()
    }

    private func restoreDraft(text: String, attachmentDrafts: [AttachmentDraft]) {
        let current = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        if current.isEmpty {
            inputText = text
        } else if current != text, !text.isEmpty {
            inputText = text + "\n" + inputText
        }
        let existingIDs = Set(attachments.map(\.id))
        attachments = attachmentDrafts.filter { !existingIDs.contains($0.id) } + attachments
    }

    private func restoreDraftIfUncommitted(
        repository: ChatRepository,
        text: String,
        attachmentDrafts: [AttachmentDraft],
        settings: AppSettings,
        startedAtMs: Int64
    ) {
        let paths = attachmentDrafts.map { $0.url.path }
        let committed = (try? repository.isUserTurnCommitted(
            conversationId: conversationID,
            text: text,
            attachments: paths,
            dualMode: settings.isDualModeEnabled,
            startedAtMs: startedAtMs
        )) ?? false
        if !committed {
            restoreDraft(text: text, attachmentDrafts: attachmentDrafts)
        }
    }

    private func clearStreamingState() {
        sessionController.clear()
    }

    private func handleStreamingSnapshot(_ snapshot: ChatStreamingSnapshot) {
        sessionController.handle(snapshot)
    }

    var canRegenerateLastAssistant: Bool {
        !settings.isDualModeEnabled &&
            !settings.isFusionModeEnabled &&
            !isSending &&
            fullMessages.last(where: { $0.message.role == "model" })?.id ==
            fullMessages.last?.id
    }

    func regenerateLastAssistantVariant() {
        guard !isSending else { return }
        guard let repository else {
            errorMessage = L10n.text("チャット初期化中です。少し待ってから再試行してください。")
            return
        }
        guard !settings.isDualModeEnabled else {
            errorMessage = L10n.text("デュアルモードでは再生成できません。")
            return
        }
        guard !settings.isFusionModeEnabled else {
            errorMessage = L10n.text("Fusion モードでは再生成できません。")
            return
        }
        guard let lastAssistant = fullMessages.last(where: { $0.message.role == "model" }),
              fullMessages.last?.id == lastAssistant.id
        else {
            errorMessage = L10n.text("最後のAIメッセージのみ再生成できます。")
            return
        }

        isSending = true
        errorMessage = nil
        let runSettings = settings
        let runID = UUID()
        activeSendID = runID
        activeSendTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.activeSendID == runID {
                    self.clearStreamingState()
                    self.generationStatus = nil
                    self.isSending = false
                    self.activeSendID = nil
                    self.activeSendTask = nil
                }
            }
            do {
                _ = try await repository.regenerateLastAssistantVariant(
                    conversationId: conversationID,
                    settingsOverride: runSettings,
                    onStreamEvent: { [self] event in
                        guard case let .reasoningDelta(delta) = event else { return }
                        Task { @MainActor in
                            guard self.activeSendID == runID else { return }
                            self.generationStatus = delta.isEmpty ? self.generationStatus : L10n.text("推論中...")
                        }
                    },
                    onStreamingSnapshot: { [self] snapshot in
                        Task { @MainActor in
                            guard self.activeSendID == runID else { return }
                            self.handleStreamingSnapshot(snapshot)
                        }
                    }
                )
            } catch is CancellationError {
                return
            } catch {
                errorMessage = error.localizedDescription
                DiagnosticsLogger.log(
                    "Regenerate last assistant failed conversation=\(conversationID)",
                    category: .chat,
                    error: error
                )
            }
        }
    }

    func branchConversation(from messageId: Int64) -> Int64? {
        guard let repository else {
            errorMessage = L10n.text("チャット初期化中です。少し待ってから再試行してください。")
            return nil
        }

        do {
            errorMessage = nil
            return try repository.branchConversation(from: conversationID, messageId: messageId)
        } catch {
            errorMessage = L10n.format("ブランチの作成に失敗しました: %@", error.localizedDescription)
            DiagnosticsLogger.log(
                "Branch conversation failed conversation=\(conversationID) message=\(messageId)",
                category: .chat,
                error: error
            )
            return nil
        }
    }

    func showPrevVariant(messageId: Int64) {
        shiftVariantSelection(messageId: messageId, delta: -1)
    }

    func showNextVariant(messageId: Int64) {
        shiftVariantSelection(messageId: messageId, delta: 1)
    }

    private func shiftVariantSelection(messageId: Int64, delta: Int) {
        guard let repository,
              let target = fullMessages.first(where: { $0.id == messageId })
        else {
            return
        }
        let nextIndex = target.normalizedSelectedVariantIndex + delta
        guard nextIndex >= 0, nextIndex < target.variantCount else {
            return
        }
        do {
            try repository.setSelectedVariant(messageId: messageId, variantIndex: nextIndex)
        } catch {
            errorMessage = error.localizedDescription
            DiagnosticsLogger.log(
                "Switch message variant failed conversation=\(conversationID) message=\(messageId)",
                category: .chat,
                error: error
            )
        }
    }

    func toggleDualMode() {
        guard !isSending else { return }
        guard let repository else {
            errorMessage = L10n.text("チャット初期化中です。少し待ってから再試行してください。")
            return
        }
        do {
            var updated = settings
            let enablingDual = !updated.isDualModeEnabled
            updated.isDualModeEnabled.toggle()
            if updated.isDualModeEnabled, enablingDual {
                if isAutoConversationRunning || isAutoConversationPaused {
                    stopAutoConversation()
                }
                updated.isAutoConversationEnabled = false
                updated.isFusionModeEnabled = false
            }
            try repository.saveSettings(updated)
        } catch {
            errorMessage = error.localizedDescription
            DiagnosticsLogger.log("Toggle dual mode failed", category: .chat, error: error)
        }
    }

    func setChatMode(_ mode: ChatMode) {
        guard !isSending else { return }
        guard let repository else {
            errorMessage = L10n.text("チャット初期化中です。少し待ってから再試行してください。")
            return
        }
        if mode != .autoConversation, isAutoConversationRunning || isAutoConversationPaused {
            stopAutoConversation()
        }
        do {
            try repository.setChatMode(mode)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            DiagnosticsLogger.log("Set chat mode failed", category: .chat, metadata: ["mode": mode.rawValue], error: error)
        }
    }

    func toggleFusionMode() {
        guard !isSending else { return }
        guard let repository else {
            errorMessage = L10n.text("チャット初期化中です。少し待ってから再試行してください。")
            return
        }
        do {
            var updated = settings
            let enablingFusion = !updated.isFusionModeEnabled
            updated.isFusionModeEnabled.toggle()
            if updated.isFusionModeEnabled, enablingFusion {
                if isAutoConversationRunning || isAutoConversationPaused {
                    stopAutoConversation()
                }
                updated.isDualModeEnabled = false
                updated.isAutoConversationEnabled = false
            }
            try repository.saveSettings(updated)
        } catch {
            errorMessage = error.localizedDescription
            DiagnosticsLogger.log("Toggle fusion mode failed", category: .chat, error: error)
        }
    }

    func fetchFusionTrace(id: String) -> FusionTrace? {
        try? repository?.fetchFusionTrace(id: id)
    }

    func fusionTrace(for message: ChatMessage) -> FusionTrace? {
        guard let traceId = message.fusionTraceId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !traceId.isEmpty else {
            return nil
        }
        return fetchFusionTrace(id: traceId)
    }

    var isFusionAnalyzing: Bool {
        settings.isFusionModeEnabled && isSending && sessionController.isEmpty
    }

    var fusionActivePhaseLabel: String? {
        guard let fusionProgress else { return nil }
        switch fusionProgress.phase {
        case .panel:
            return L10n.format(
                "panels %d/%d",
                fusionProgress.completedPanelCount,
                fusionProgress.totalPanelCount
            )
        case .judge:
            return L10n.text("judging")
        case .synthesizer:
            return L10n.text("synthesizing")
        }
    }

    var fusionAnalyzingStatus: String? {
        if fusionProgress != nil {
            return nil
        }
        if let fusionStreamingStatus, !fusionStreamingStatus.isEmpty {
            return fusionStreamingStatus
        }
        return isFusionAnalyzing ? L10n.text("Fusion 分析中…") : nil
    }

    var fusionStatusLabel: String {
        let panelCount = FusionPresetLoader.panelCount(customPresetJSON: settings.fusionCustomPresetJSON)
        if panelCount > 0 {
            return L10n.format("FUSION · %d panels", panelCount)
        }
        return "FUSION"
    }

    var fusionModelSummaryLabel: String? {
        guard settings.isFusionModeEnabled else { return nil }
        guard let definition = try? FusionPresetLoader.resolveDefinition(
            customPresetJSON: settings.fusionCustomPresetJSON
        ) else {
            return nil
        }
        let judge = Self.shortModelLabel(definition.judgeModel.modelId)
        let synth = Self.shortModelLabel(definition.synthesizerModel.modelId)
        return L10n.format("judge: %@ · synth: %@", judge, synth)
    }

    func toggleAutoConversation() {
        guard !isSending else { return }
        guard let repository else {
            errorMessage = L10n.text("チャット初期化中です。少し待ってから再試行してください。")
            return
        }
        do {
            var updated = settings
            let enablingAuto = !updated.isAutoConversationEnabled
            updated.isAutoConversationEnabled.toggle()
            if updated.isAutoConversationEnabled, enablingAuto {
                updated.isDualModeEnabled = false
                updated.isFusionModeEnabled = false
            } else if !updated.isAutoConversationEnabled,
                      isAutoConversationRunning || isAutoConversationPaused {
                stopAutoConversation()
            }
            try repository.saveSettings(updated)
        } catch {
            errorMessage = error.localizedDescription
            DiagnosticsLogger.log("Toggle auto conversation failed", category: .chat, error: error)
        }
    }

    func availableSystemPromptPresets() -> [SystemPromptPreset] {
        settings.systemPromptPresets()
    }

    var systemPromptContextLabel: String {
        Self.systemPromptContextLabel(
            activePresetName: activeSystemPromptPresetName,
            conversationSystemPrompt: conversationSystemPrompt
        )
    }

    var isSystemPromptDisabledForConversation: Bool {
        conversationSystemPrompt?.nilIfBlank == nil
    }

    var isCustomSystemPromptActive: Bool {
        activeSystemPromptPresetName?.nilIfBlank == nil && !isSystemPromptDisabledForConversation
    }

    var workspaceTitleLabel: String {
        if isSecretConversation {
            return L10n.text("シークレット")
        }
        if settings.isFusionModeEnabled {
            return L10n.text("Fusion")
        }
        if settings.isDualModeEnabled {
            return L10n.text("デュアル")
        }
        if settings.isAutoConversationEnabled {
            return L10n.text("自動会話")
        }
        let model = settings.currentModel().trimmingCharacters(in: .whitespacesAndNewlines)
        return model.isEmpty ? L10n.text("Chat") : model
    }

    var workspaceConversationTitleLabel: String {
        let title = conversationTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != "New Chat" else {
            return L10n.text("新しいチャット")
        }
        return title
    }

    var workspaceSubtitleLabel: String? {
        if isSecretConversation {
            let provider = activeConversationProvider.isEmpty
                ? settings.apiProvider.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                : activeConversationProvider
            let model = activeConversationModel.isEmpty
                ? settings.currentModel().trimmingCharacters(in: .whitespacesAndNewlines)
                : activeConversationModel
            let base = model.isEmpty ? provider : "\(provider) · \(Self.shortModelLabel(model))"
            return L10n.format("別の会話を開くと破棄 · %@", base)
        }
        if settings.isFusionModeEnabled {
            var parts = [fusionStatusLabel]
            if let modelSummary = fusionModelSummaryLabel {
                parts.append(modelSummary)
            }
            if let phaseLabel = fusionActivePhaseLabel {
                parts.append(phaseLabel)
            } else if isFusionAnalyzing {
                parts.append(L10n.text("analyzing"))
            }
            return parts.joined(separator: " · ")
        }
        if settings.isDualModeEnabled {
            return L10n.format(
                "%@ %@ vs %@ %@",
                settings.dualProviderA,
                Self.shortModelLabel(settings.dualModelA),
                settings.dualProviderB,
                Self.shortModelLabel(settings.dualModelB)
            )
        }
        if settings.isAutoConversationEnabled {
            let status = isAutoConversationRunning
                ? L10n.text("実行中")
                : (isAutoConversationPaused ? L10n.text("一時停止") : L10n.text("待機中"))
            return L10n.format(
                "%@ · %@ %@ ⇄ %@ %@",
                status,
                settings.autoProviderA,
                Self.shortModelLabel(settings.autoModelA),
                settings.autoProviderB,
                Self.shortModelLabel(settings.autoModelB)
            )
        }
        let provider = settings.apiProvider.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let model = settings.currentModel().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { return nil }
        return "\(provider) · \(Self.shortModelLabel(model))"
    }

    var composerContextLabel: String {
        let secretPrefix = L10n.text("シークレット")
        if settings.isFusionModeEnabled {
            var parts = [fusionStatusLabel]
            if let modelSummary = fusionModelSummaryLabel {
                parts.append(modelSummary)
            }
            if let phaseLabel = fusionActivePhaseLabel {
                parts.append(phaseLabel)
            } else if isFusionAnalyzing {
                parts.append(L10n.text("analyzing"))
            }
            let label = parts.joined(separator: " · ")
            return isSecretConversation ? "\(secretPrefix) · \(label)" : label
        }
        if settings.isDualModeEnabled {
            let label = L10n.format(
                "DUAL · %@ %@ vs %@ %@",
                settings.dualProviderA,
                Self.shortModelLabel(settings.dualModelA),
                settings.dualProviderB,
                Self.shortModelLabel(settings.dualModelB)
            )
            return isSecretConversation ? "\(secretPrefix) · \(label)" : label
        }
        if settings.isAutoConversationEnabled {
            let label = L10n.format(
                "AUTO · %@ %@ ⇄ %@ %@",
                settings.autoProviderA,
                Self.shortModelLabel(settings.autoModelA),
                settings.autoProviderB,
                Self.shortModelLabel(settings.autoModelB)
            )
            return isSecretConversation ? "\(secretPrefix) · \(label)" : label
        }
        let provider = activeConversationProvider.isEmpty
            ? settings.apiProvider.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            : activeConversationProvider
        let model = activeConversationModel.isEmpty
            ? settings.currentModel().trimmingCharacters(in: .whitespacesAndNewlines)
            : activeConversationModel
        let label = model.isEmpty ? provider : "\(provider) · \(Self.shortModelLabel(model))"
        return isSecretConversation ? "\(secretPrefix) · \(label)" : label
    }

    var composerPlaceholder: String {
        settings.isAutoConversationEnabled
            ? L10n.text("AIへの指示…")
            : L10n.text("質問してみましょう")
    }

    var showsAutoConversationStatusBanner: Bool {
        settings.isAutoConversationEnabled &&
            (isAutoConversationRunning || isAutoConversationPaused || !(autoConversationStatus?.isEmpty ?? true))
    }

    nonisolated static func shortModelLabel(_ model: String) -> String {
        let core = model.split(separator: "/").last.map(String.init) ?? model
        if core.count > 32 {
            return String(core.prefix(31)) + "…"
        }
        return core
    }

    nonisolated static func systemPromptContextLabel(activePresetName: String?, conversationSystemPrompt: String?) -> String {
        if let presetName = activePresetName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !presetName.isEmpty {
            return L10n.format("Prompt: %@", presetName)
        }
        if let prompt = conversationSystemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty {
            return L10n.text("Prompt: Custom")
        }
        return L10n.text("Prompt: なし")
    }

    private func refreshConversationTitle() {
        guard let repository else { return }
        do {
            if let conversation = try repository.conversation(id: conversationID) {
                conversationTitle = conversation.title
            }
        } catch {
            DiagnosticsLogger.log(
                "Refresh conversation title failed conversation=\(conversationID)",
                category: .chat,
                error: error
            )
        }
    }

    func availableChatPresets() -> [ModelPreset] {
        settings.chatVisibleGlobalProviderPresets()
    }

    func applyChatPreset(_ preset: ModelPreset) {
        guard !isSending else { return }
        guard let repository else {
            errorMessage = L10n.text("チャット初期化中です。少し待ってから再試行してください。")
            return
        }

        do {
            let provider = preset.apiProvider.uppercased()
            try repository.updateConversationModelAndProvider(
                conversationId: conversationID,
                model: preset.model,
                provider: provider
            )
            activeConversationProvider = provider
            activeConversationModel = preset.model

            var updated = settings
            updated.apiProvider = provider
            updated.defaultModel = preset.model
            var providerMap = updated.providerModelMap()
            providerMap[provider] = preset.model
            if let data = try? JSONEncoder().encode(providerMap),
               let json = String(data: data, encoding: .utf8) {
                updated.providerDefaultModelsJSON = json
            }

            try repository.saveSettings(updated)
            settings = updated
            updateActiveChatPresetName()
            refreshReasoningEffortConfiguration()
            Task { [weak self] in
                await self?.refreshVisionSupport()
                await self?.refreshReasoningEffortCatalog()
            }
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            DiagnosticsLogger.log(
                "Apply chat preset failed conversation=\(conversationID)",
                category: .chat,
                error: error
            )
        }
    }

    func setReasoningEffort(_ effort: String) {
        guard !isSending,
              let repository,
              var configuration = reasoningEffortConfiguration,
              let selectedValue = ChatReasoningEffortPresentationPolicy.matchingOption(
                  effort,
                  in: configuration.options
              ),
              selectedValue != configuration.selectedValue
        else { return }

        do {
            try repository.setReasoningEffort(
                selectedValue,
                provider: configuration.providerID,
                model: configuration.modelID
            )
            configuration.selectedValue = selectedValue
            reasoningEffortConfiguration = configuration
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            DiagnosticsLogger.log(
                "Chat reasoning effort update failed",
                category: .settings,
                metadata: [
                    "provider": configuration.providerID,
                    "model": configuration.modelID,
                    "effort": selectedValue
                ],
                error: error
            )
        }
    }

    func disableSystemPromptForConversation() {
        applySystemPrompt(nil, presetName: nil)
    }

    func applyCustomSystemPrompt() {
        applySystemPrompt(settings.systemPrompt?.nilIfBlank, presetName: nil)
    }

    func applySystemPromptPreset(name: String) {
        guard !isSending else { return }

        let selectedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedPreset = settings.systemPromptPresets().first {
            guard !selectedName.isEmpty else { return false }
            return $0.name.caseInsensitiveCompare(selectedName) == .orderedSame
        }
        guard let selectedPreset else { return }

        applySystemPrompt(selectedPreset.prompt.nilIfBlank, presetName: selectedPreset.name)
    }

    private func applySystemPrompt(_ prompt: String?, presetName: String?) {
        guard !isSending else { return }
        guard let repository else { return }

        do {
            try repository.updateConversationSystemPrompt(
                conversationId: conversationID,
                systemPrompt: prompt
            )
            conversationSystemPrompt = prompt
            activeSystemPromptPresetName = presetName
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            DiagnosticsLogger.log(
                "Apply system prompt preset failed conversation=\(conversationID)",
                category: .chat,
                error: error
            )
        }
    }

    func startAutoConversationManually() {
        guard settings.isAutoConversationEnabled else {
            errorMessage = L10n.text("先に自動会話をONにしてください。")
            return
        }
        guard !isAutoConversationRunning else { return }

        let initial = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !initial.isEmpty else {
            errorMessage = L10n.text("開始メッセージを入力してください。")
            return
        }

        inputText = ""
        startAutoConversation(initialMessage: initial, insertSeedInChat: true)
    }

    private func startAutoConversation(initialMessage: String, insertSeedInChat: Bool) {
        guard let repository else { return }
        guard !isAutoConversationRunning else { return }

        let normalized = initialMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }

        autoConversationTask?.cancel()
        isAutoConversationRunning = true
        isAutoConversationPaused = false
        autoConversationStatus = L10n.text("自動会話を開始しています...")
        errorMessage = nil

        do {
            if insertSeedInChat {
                try repository.prepareAutoConversationSeedMessage(
                    conversationId: conversationID,
                    text: normalized
                )
            }
            let autoConversationId = try repository.createAutoConversation(
                conversationId: conversationID,
                initialMessage: normalized
            )
            activeAutoConversationID = autoConversationId
            launchAutoConversationTask(autoConversationId: autoConversationId)
        } catch {
            isAutoConversationRunning = false
            isAutoConversationPaused = false
            activeAutoConversationID = nil
            errorMessage = error.localizedDescription
            autoConversationStatus = L10n.text("自動会話の初期化に失敗しました")
            DiagnosticsLogger.log(
                "Auto conversation setup failed conversation=\(conversationID)",
                category: .chat,
                error: error
            )
        }
    }

    private func launchAutoConversationTask(autoConversationId: Int64) {
        guard let repository else { return }

        autoConversationTask = Task {
            do {
                try await repository.resumeAutoConversation(
                    autoConversationId: autoConversationId
                ) { [self] turn, speaker, _ in
                    Task { @MainActor in
                        self.autoConversationStatus = L10n.format("%dターン目: %@", turn, speaker)
                    }
                }
                await MainActor.run {
                    self.isAutoConversationRunning = false
                    self.isAutoConversationPaused = false
                    self.autoConversationStatus = L10n.text("自動会話が完了しました")
                    self.activeAutoConversationID = nil
                }
            } catch is CancellationError {
                // pause/stopで明示更新するため何もしない
            } catch {
                await MainActor.run {
                    self.isAutoConversationRunning = false
                    self.isAutoConversationPaused = false
                    self.errorMessage = error.localizedDescription
                    self.autoConversationStatus = L10n.text("自動会話でエラーが発生しました")
                    self.activeAutoConversationID = nil
                }
                DiagnosticsLogger.log(
                    "Auto conversation start failed conversation=\(conversationID)",
                    category: .chat,
                    error: error
                )
            }
        }
    }

    func pauseAutoConversation() {
        guard let repository, let autoConversationID = activeAutoConversationID else { return }
        do {
            autoConversationTask?.cancel()
            autoConversationTask = nil
            try repository.pauseAutoConversation(autoConversationId: autoConversationID)
            isAutoConversationRunning = false
            isAutoConversationPaused = true
            autoConversationStatus = L10n.text("自動会話を一時停止しました")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resumeAutoConversation() {
        guard let autoConversationID = activeAutoConversationID else { return }
        guard !isAutoConversationRunning else { return }

        isAutoConversationRunning = true
        isAutoConversationPaused = false
        autoConversationStatus = L10n.text("自動会話を再開しています...")
        launchAutoConversationTask(autoConversationId: autoConversationID)
    }

    func stopAutoConversation() {
        guard let repository else { return }
        let autoConversationID = activeAutoConversationID
        autoConversationTask?.cancel()
        autoConversationTask = nil
        if let autoConversationID {
            do {
                try repository.stopAutoConversation(
                    autoConversationId: autoConversationID,
                    reason: AutoConversationEndReason.userStop
                )
            } catch {
                DiagnosticsLogger.log(
                    "Auto conversation stop failed conversation=\(conversationID)",
                    category: .chat,
                    error: error
                )
            }
        }
        isAutoConversationRunning = false
        isAutoConversationPaused = false
        autoConversationStatus = L10n.text("自動会話を停止しました")
        activeAutoConversationID = nil
    }

    private func syncNewChatWithSettingsIfEmpty(settings: AppSettings, previousSettings: AppSettings?) {
        guard let repository else { return }
        do {
            if let conversation = try repository.syncNewChatWithSettingsIfEmpty(
                conversationId: conversationID,
                settings: settings,
                previousSettings: previousSettings
            ) {
                conversationSystemPrompt = conversation.systemPrompt
                activeConversationProvider = conversation.apiProvider
                activeConversationModel = conversation.model
                isSecretConversation = conversation.isSecret
                updateActiveChatPresetName()
                updateActiveSystemPromptPresetName()
                refreshReasoningEffortConfiguration()
                Task { [weak self] in
                    await self?.refreshVisionSupport()
                    await self?.refreshReasoningEffortCatalog()
                }
            }
        } catch {
            DiagnosticsLogger.log(
                "Sync new chat with settings failed conversation=\(conversationID)",
                category: .chat,
                error: error
            )
        }
    }

    private func updateActiveSystemPromptPresetName() {
        let normalizedPrompt = conversationSystemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedPrompt, !normalizedPrompt.isEmpty else {
            activeSystemPromptPresetName = nil
            return
        }

        activeSystemPromptPresetName = settings.systemPromptPresets()
            .first {
                $0.prompt.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedPrompt
            }?
            .name
    }

    private func updateActiveChatPresetName() {
        let currentProvider = (activeConversationProvider.isEmpty ? settings.apiProvider : activeConversationProvider)
            .uppercased()
        let currentModel = (activeConversationModel.isEmpty ? settings.currentModel() : activeConversationModel)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !currentModel.isEmpty else {
            activeChatPresetName = nil
            return
        }

        activeChatPresetName = availableChatPresets()
            .first {
                $0.apiProvider.uppercased() == currentProvider &&
                    $0.model.trimmingCharacters(in: .whitespacesAndNewlines) == currentModel
            }?
            .name
    }

    private func refreshReasoningEffortConfiguration() {
        guard ChatMode(settings: settings) == .standard, let repository else {
            reasoningEffortConfiguration = nil
            return
        }
        reasoningEffortConfiguration = repository.reasoningEffortConfiguration(
            settings: settings,
            provider: conversationProvider,
            model: conversationModel
        )
    }

    private func refreshReasoningEffortCatalog() async {
        guard let repository else { return }
        await repository.refreshReasoningEffortCatalog(for: conversationProvider)
        guard !Task.isCancelled else { return }
        refreshReasoningEffortConfiguration()
    }

    private func refreshVisionSupport() async {
        guard let repository else {
            canAttachImages = false
            return
        }
        let supportsVision = await repository.resolveCanAttachImages(
            settings: settings,
            conversationProvider: activeConversationProvider,
            conversationModel: activeConversationModel
        )
        canAttachImages = supportsVision
        if !supportsVision {
            let unsupportedImages = attachments.filter { attachmentRepository?.requiresVision(url: $0.url) == true }
            if !unsupportedImages.isEmpty {
                let unsupportedIDs = Set(unsupportedImages.map(\.id))
                attachments.removeAll { unsupportedIDs.contains($0.id) }
                errorMessage = L10n.text("画像入力に対応していないモデルのため、画像添付を外しました。")
            }
        }
    }

    var conversationProvider: String {
        activeConversationProvider.isEmpty ? settings.apiProvider : activeConversationProvider
    }

    var conversationModel: String {
        activeConversationModel.isEmpty ? settings.currentModel() : activeConversationModel
    }

    private func rebuildContextUsage() {
        contextUsage = ContextUsage(record: latestTokenUsageRecord)
    }

    var chatStatsGroups: [String] {
        let visible = settings.visibleChatStatsFields()
        let stats = conversationStats
        var groups: [String] = []
        if visible.contains(.turns), stats.turns > 0 {
            groups.append(L10n.format("%dターン", Int(stats.turns)))
        }
        if visible.contains(.steps), stats.steps > 0 {
            groups.append(L10n.format("%dステップ", Int(stats.steps)))
        }
        if visible.contains(.llmDuration), stats.llmDurationMs > 0 {
            groups.append(L10n.format("LLM %@", ChatStatsFormatter.duration(milliseconds: Double(stats.llmDurationMs))))
        }
        if visible.contains(.toolDuration), stats.toolDurationMs > 0 {
            groups.append(L10n.format("ツール %@", ChatStatsFormatter.duration(milliseconds: Double(stats.toolDurationMs))))
        }
        if visible.contains(.averageTTFT), let average = stats.averageTTFTMs {
            groups.append(L10n.format("平均 TTFT %@", ChatStatsFormatter.duration(milliseconds: average)))
        }
        if visible.contains(.tokensPerSecond), let throughput = stats.tokensPerSecond {
            groups.append(L10n.format("%@ tok/s", ChatStatsFormatter.throughput(throughput)))
        }
        if visible.contains(.cacheHit), let percent = stats.cacheHitPercent {
            groups.append(L10n.format("キャッシュヒット %d%%", percent))
        }
        if visible.contains(.tokens), stats.billedInputTokens > 0 || stats.outputTokens > 0 {
            groups.append(L10n.format(
                "入力 %@ tok · 出力 %@ tok",
                ChatStatsFormatter.tokens(stats.billedInputTokens),
                ChatStatsFormatter.tokens(stats.outputTokens)
            ))
        }
        return groups
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
