import Foundation
import Combine

struct AttachmentDraft: Identifiable, Equatable {
    let id: UUID
    var url: URL
    var displayName: String

    init(url: URL, displayName: String? = nil) {
        id = UUID()
        self.url = url
        self.displayName = displayName ?? url.lastPathComponent
    }
}

@MainActor
final class ChatViewModel: ObservableObject {
    @Published private(set) var messageSummaries: [ChatMessageSummary] = []
    @Published private(set) var fullMessages: [FullChatMessage] = []
    @Published private(set) var dualMessages: [DualChatMessage] = []
    @Published private(set) var settings: AppSettings = .init()

    @Published var inputText: String = ""
    @Published var isSending: Bool = false
    @Published var isAutoConversationRunning: Bool = false
    @Published var isAutoConversationPaused: Bool = false
    @Published var autoConversationStatus: String?
    @Published var fusionStreamingStatus: String?
    @Published var errorMessage: String?
    @Published var attachments: [AttachmentDraft] = []
    @Published private(set) var isSpeechRecording: Bool = false
    @Published private(set) var activeChatPresetName: String?
    @Published private(set) var activeSystemPromptPresetName: String?
    @Published private(set) var contextUsageLabel: String?
    @Published private(set) var canAttachImages: Bool = false
    @Published private(set) var streamingSnapshots: [Int64: ChatStreamingSnapshot] = [:]
    @Published private(set) var isSecretConversation: Bool = false
    @Published private(set) var conversationTitle: String = "New Chat"

    let speechService = SpeechRecognitionService()

    private let conversationID: Int64
    private var repository: ChatRepository?
    private var attachmentRepository: AttachmentRepository?
    private var cancellables: Set<AnyCancellable> = []
    private var autoConversationTask: Task<Void, Never>?
    private var activeAutoConversationID: Int64?
    private var conversationSystemPrompt: String?
    private var lastSettingsSnapshot: AppSettings?
    private var inputTextBeforeSpeech: String = ""
    private var latestTokenUsageRecord: TokenUsageRecord?
    private var resolvedContextLimit: Int?
    private var activeConversationProvider: String = ""
    private var activeConversationModel: String = ""

    init(conversationID: Int64) {
        self.conversationID = conversationID
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
    }

    deinit {
        autoConversationTask?.cancel()
    }

    func bind(repository: ChatRepository, attachmentRepository: AttachmentRepository) {
        guard self.repository == nil else { return }
        self.repository = repository
        self.attachmentRepository = attachmentRepository

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
            }
            .store(in: &cancellables)

        repository.observeDualMessages(conversationId: conversationID)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.dualMessages = $0
            }
            .store(in: &cancellables)

        repository.observeLatestTokenUsage(conversationId: conversationID)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] record in
                self?.latestTokenUsageRecord = record
                self?.rebuildContextUsageLabel()
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
                Task { [weak self] in
                    await self?.refreshContextLimit()
                    await self?.refreshVisionSupport()
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

    func applySharedText(_ text: String?) {
        guard let text, !text.isEmpty else { return }
        inputText = text
    }

    func addAttachment(
        url: URL,
        displayName: String? = nil,
        deleteSourceWhenHandled: Bool = false
    ) {
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
            return
        }
        switch attachmentRepository.validate(url: url) {
        case .valid:
            if attachmentRepository.requiresVision(url: url), !canAttachImages {
                errorMessage = L10n.text("このモデルは画像入力に対応していません。")
                return
            }
            do {
                let persistedURL = try attachmentRepository.persistAttachment(url: url)
                attachments.append(
                    AttachmentDraft(url: persistedURL, displayName: displayName ?? url.lastPathComponent)
                )
                errorMessage = nil
            } catch {
                errorMessage = L10n.text("ファイルを読み込めませんでした。")
                DiagnosticsLogger.log(
                    "Persist attachment failed conversation=\(conversationID) file=\(url.lastPathComponent)",
                    category: .chat,
                    error: error
                )
                return
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
    }

    func removeAttachment(id: UUID) {
        attachments.removeAll { $0.id == id }
        errorMessage = nil
    }

    func clearAttachments() {
        attachments.removeAll()
        errorMessage = nil
    }

    func toggleSpeechRecognition() {
        if isSpeechRecording {
            speechService.stopRecording()
        } else {
            inputTextBeforeSpeech = inputText
            speechService.startRecording()
        }
    }

    func sendMessage() {
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

        let isAutoConversationEnabled = settings.isAutoConversationEnabled
        let shouldStartAutoConversation = isAutoConversationEnabled && AutoConversationTrigger.matches(text)

        Task {
            defer { isSending = false }
            do {
                let attachmentPaths = attachmentDrafts.map { $0.url.absoluteString }

                if settings.isFusionModeEnabled {
                    guard !text.isEmpty || !attachmentPaths.isEmpty else {
                        errorMessage = L10n.text("Fusion モードでは本文または添付を入力してください。")
                        attachments = attachmentDrafts
                        return
                    }
                    _ = try await repository.sendFusionMessage(
                        conversationId: conversationID,
                        text: text,
                        attachments: attachmentPaths,
                        onStreamEvent: { [weak self] event in
                            guard case let .reasoningDelta(delta) = event else { return }
                            Task { @MainActor in
                                self?.fusionStreamingStatus = delta.isEmpty
                                    ? self?.fusionStreamingStatus
                                    : L10n.text("推論中...")
                            }
                        },
                        onStreamingSnapshot: { [weak self] snapshot in
                            Task { @MainActor in
                                self?.handleStreamingSnapshot(snapshot)
                            }
                        }
                    )
                    fusionStreamingStatus = nil
                } else if settings.isDualModeEnabled {
                    guard !text.isEmpty || !attachmentPaths.isEmpty else {
                        errorMessage = L10n.text("デュアルモードでは本文または添付を入力してください。")
                        attachments = attachmentDrafts
                        return
                    }
                    _ = try await repository.sendDualMessage(
                        conversationId: conversationID,
                        text: text,
                        attachments: attachmentPaths
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
                        onStreamEvent: { [weak self] event in
                            guard case let .reasoningDelta(delta) = event else { return }
                            Task { @MainActor in
                                self?.autoConversationStatus = delta.isEmpty ? self?.autoConversationStatus : L10n.text("推論中...")
                            }
                        },
                        onStreamingSnapshot: { [weak self] snapshot in
                            Task { @MainActor in
                                self?.handleStreamingSnapshot(snapshot)
                            }
                        }
                    )
                }
                refreshConversationTitle()
            } catch {
                errorMessage = error.localizedDescription
                attachments = attachmentDrafts
                DiagnosticsLogger.log(
                    "Send message failed conversation=\(conversationID)",
                    category: .chat,
                    error: error
                )
            }
        }
    }

    func streamingSnapshot(for messageId: Int64) -> ChatStreamingSnapshot? {
        streamingSnapshots[messageId]
    }

    func isMessageStreaming(_ messageId: Int64) -> Bool {
        guard isSending, let snapshot = streamingSnapshots[messageId] else { return false }
        return !snapshot.isFinal
    }

    private func handleStreamingSnapshot(_ snapshot: ChatStreamingSnapshot) {
        if snapshot.isFinal {
            streamingSnapshots.removeValue(forKey: snapshot.targetId)
        } else {
            streamingSnapshots[snapshot.targetId] = snapshot
        }
    }

    var canRegenerateLastAssistant: Bool {
        !settings.isDualModeEnabled &&
            !settings.isFusionModeEnabled &&
            !isSending &&
            fullMessages.last(where: { $0.message.role == "model" })?.id ==
            fullMessages.last?.id
    }

    func regenerateLastAssistantVariant() {
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
        Task {
            defer { isSending = false }
            do {
                _ = try await repository.regenerateLastAssistantVariant(
                    conversationId: conversationID,
                    onStreamEvent: { [weak self] event in
                        guard case let .reasoningDelta(delta) = event else { return }
                        Task { @MainActor in
                            self?.autoConversationStatus = delta.isEmpty ? self?.autoConversationStatus : L10n.text("推論中...")
                        }
                    },
                    onStreamingSnapshot: { [weak self] snapshot in
                        Task { @MainActor in
                            self?.handleStreamingSnapshot(snapshot)
                        }
                    }
                )
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

    func toggleFusionMode() {
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
        settings.isFusionModeEnabled && isSending && streamingSnapshots.isEmpty
    }

    var fusionAnalyzingStatus: String? {
        if let fusionStreamingStatus, !fusionStreamingStatus.isEmpty {
            return fusionStreamingStatus
        }
        return isFusionAnalyzing ? L10n.text("Fusion 分析中…") : nil
    }

    var fusionStatusLabel: String {
        let preset = settings.fusionPresetName
        let panelCount = FusionPresetLoader.panelCount(
            for: preset,
            customPresetJSON: settings.fusionCustomPresetJSON
        )
        if panelCount > 0 {
            return L10n.format("FUSION · %@ · %d panels", preset, panelCount)
        }
        return L10n.format("FUSION · %@", preset)
    }

    func toggleAutoConversation() {
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
            return L10n.format("閉じると破棄 · %@", base)
        }
        if settings.isFusionModeEnabled {
            if isFusionAnalyzing {
                return L10n.format("%@ · analyzing", fusionStatusLabel)
            }
            return fusionStatusLabel
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
            let label = isFusionAnalyzing
                ? L10n.format("%@ · analyzing", fusionStatusLabel)
                : fusionStatusLabel
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
        let globalPresets = settings.buildGlobalProviderPresets()
        return globalPresets.filter { preset in
            settings.shouldShowGlobalProviderPresetInChat(provider: preset.apiProvider)
        }
    }

    func applyChatPreset(_ preset: ModelPreset) {
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
            Task { [weak self] in
                await self?.refreshContextLimit()
                await self?.refreshVisionSupport()
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

    func applySystemPromptPreset(name: String?) {
        guard let repository else { return }

        let selectedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let selectedPreset = settings.systemPromptPresets().first {
            guard let selectedName, !selectedName.isEmpty else { return false }
            return $0.name.caseInsensitiveCompare(selectedName) == .orderedSame
        }

        let targetPrompt = selectedPreset?.prompt.nilIfBlank ?? settings.systemPrompt?.nilIfBlank

        do {
            try repository.updateConversationSystemPrompt(
                conversationId: conversationID,
                systemPrompt: targetPrompt
            )
            conversationSystemPrompt = targetPrompt
            activeSystemPromptPresetName = selectedPreset?.name
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
                ) { [weak self] turn, speaker, _ in
                    Task { @MainActor in
                        self?.autoConversationStatus = L10n.format("%dターン目: %@", turn, speaker)
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
                Task { [weak self] in
                    await self?.refreshContextLimit()
                    await self?.refreshVisionSupport()
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
        let currentProvider = settings.apiProvider.uppercased()
        let currentModel = settings.currentModel().trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func refreshContextLimit() async {
        guard let repository else { return }
        let limit = await repository.resolveContextLimit(
            provider: activeConversationProvider,
            model: activeConversationModel
        )
        resolvedContextLimit = limit
        rebuildContextUsageLabel()
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
        if !supportsVision, !attachments.isEmpty {
            attachments = []
        }
    }

    private func rebuildContextUsageLabel() {
        guard let record = latestTokenUsageRecord else {
            contextUsageLabel = nil
            return
        }

        let used = max(
            0,
            max(
                record.totalTokens,
                record.inputTokens +
                    record.outputTokens +
                    max(0, record.reasoningTokens ?? 0) +
                    max(0, record.cachedInputTokens ?? 0) +
                    max(0, record.cacheCreationInputTokens ?? 0)
            )
        )
        guard used > 0 else {
            contextUsageLabel = nil
            return
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let usedText = formatter.string(from: NSNumber(value: used)) ?? "\(used)"

        if let limit = resolvedContextLimit, limit > 0 {
            let limitText = formatter.string(from: NSNumber(value: limit)) ?? "\(limit)"
            let usage = Int((Double(used) / Double(limit) * 100.0).rounded())
            contextUsageLabel = "\(usage)%  \(usedText)/\(limitText)"
        } else {
            contextUsageLabel = "\(usedText)/-"
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
