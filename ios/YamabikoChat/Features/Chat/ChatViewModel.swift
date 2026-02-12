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
    @Published var autoConversationStatus: String?
    @Published var errorMessage: String?
    @Published var attachments: [AttachmentDraft] = []
    @Published private(set) var activeChatPresetName: String?
    @Published private(set) var activeSystemPromptPresetName: String?

    private let conversationID: Int64
    private var repository: ChatRepository?
    private var attachmentRepository: AttachmentRepository?
    private var cancellables: Set<AnyCancellable> = []
    private var autoConversationTask: Task<Void, Never>?
    private var conversationSystemPrompt: String?
    private var lastSettingsSnapshot: AppSettings?

    init(conversationID: Int64) {
        self.conversationID = conversationID
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

        repository.settingsPublisher()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self else { return }
                let previous = self.lastSettingsSnapshot
                self.lastSettingsSnapshot = $0
                self.settings = $0
                self.syncNewChatWithSettingsIfEmpty(settings: $0, previousSettings: previous)
                self.updateActiveChatPresetName()
                self.updateActiveSystemPromptPresetName()
            }
            .store(in: &cancellables)

        do {
            if let conversation = try repository.conversation(id: conversationID) {
                conversationSystemPrompt = conversation.systemPrompt
                updateActiveChatPresetName()
                updateActiveSystemPromptPresetName()
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

    func addAttachment(url: URL) {
        guard let attachmentRepository else { return }
        switch attachmentRepository.validate(url: url) {
        case .valid:
            do {
                let persistedURL = try attachmentRepository.persistAttachment(url: url)
                attachments.append(
                    AttachmentDraft(url: persistedURL, displayName: url.lastPathComponent)
                )
                errorMessage = nil
            } catch {
                errorMessage = "ファイルを読み込めませんでした。"
            }
        case let .tooLarge(sizeBytes):
            let sizeMB = Double(sizeBytes) / (1024 * 1024)
            errorMessage = String(format: "添付ファイルが%.1fMBで上限10MBを超えています。", sizeMB)
        case .unsupportedType:
            errorMessage = "サポート外のファイル形式です。"
        case .dangerousFile:
            errorMessage = "危険なファイル形式は添付できません。"
        case .unreadable:
            errorMessage = "ファイルを読み込めませんでした。"
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

    func sendMessage() {
        let trimmedText = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty || !attachments.isEmpty else { return }
        guard let repository else {
            errorMessage = "チャット初期化中です。少し待ってから再試行してください。"
            return
        }

        let text = trimmedText
        inputText = ""

        isSending = true
        errorMessage = nil

        let attachmentDrafts = attachments
        attachments = []

        Task {
            defer { isSending = false }
            do {
                let attachmentPaths = attachmentDrafts.map { $0.url.absoluteString }

                if settings.isDualModeEnabled {
                    guard !text.isEmpty || !attachmentPaths.isEmpty else {
                        errorMessage = "デュアルモードでは本文または添付を入力してください。"
                        attachments = attachmentDrafts
                        return
                    }
                    _ = try await repository.sendDualMessage(
                        conversationId: conversationID,
                        text: text,
                        attachments: attachmentPaths
                    )
                } else {
                    _ = try await repository.sendMessage(
                        conversationId: conversationID,
                        text: text,
                        attachments: attachmentPaths,
                        onStreamEvent: { [weak self] event in
                            guard case let .reasoningDelta(delta) = event else { return }
                            Task { @MainActor in
                                self?.autoConversationStatus = delta.isEmpty ? self?.autoConversationStatus : "推論中..."
                            }
                        }
                    )

                    if settings.isAutoConversationEnabled, !text.isEmpty {
                        startAutoConversation(initial: text)
                    }
                }
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

    var canRegenerateLastAssistant: Bool {
        !settings.isDualModeEnabled &&
            !isSending &&
            fullMessages.last(where: { $0.message.role == "model" })?.id ==
            fullMessages.last?.id
    }

    func regenerateLastAssistantVariant() {
        guard let repository else {
            errorMessage = "チャット初期化中です。少し待ってから再試行してください。"
            return
        }
        guard !settings.isDualModeEnabled else {
            errorMessage = "デュアルモードでは再生成できません。"
            return
        }
        guard let lastAssistant = fullMessages.last(where: { $0.message.role == "model" }),
              fullMessages.last?.id == lastAssistant.id
        else {
            errorMessage = "最後のAIメッセージのみ再生成できます。"
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
                            self?.autoConversationStatus = delta.isEmpty ? self?.autoConversationStatus : "推論中..."
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
            errorMessage = "チャット初期化中です。少し待ってから再試行してください。"
            return
        }
        do {
            var updated = settings
            updated.isDualModeEnabled.toggle()
            if updated.isDualModeEnabled {
                updated.isAutoConversationEnabled = false
            }
            try repository.saveSettings(updated)
        } catch {
            errorMessage = error.localizedDescription
            DiagnosticsLogger.log("Toggle dual mode failed", category: .chat, error: error)
        }
    }

    func toggleAutoConversation() {
        guard let repository else {
            errorMessage = "チャット初期化中です。少し待ってから再試行してください。"
            return
        }
        do {
            var updated = settings
            updated.isAutoConversationEnabled.toggle()
            if updated.isAutoConversationEnabled {
                updated.isDualModeEnabled = false
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

    nonisolated static func systemPromptContextLabel(activePresetName: String?, conversationSystemPrompt: String?) -> String {
        if let presetName = activePresetName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !presetName.isEmpty {
            return "Prompt: \(presetName)"
        }
        if let prompt = conversationSystemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !prompt.isEmpty {
            return "Prompt: Custom"
        }
        return "Prompt: なし"
    }

    func availableChatPresets() -> [ModelPreset] {
        let globalPresets = settings.buildGlobalProviderPresets()
        return globalPresets.filter { preset in
            settings.shouldShowGlobalProviderPresetInChat(provider: preset.apiProvider)
        }
    }

    func applyChatPreset(_ preset: ModelPreset) {
        guard let repository else {
            errorMessage = "チャット初期化中です。少し待ってから再試行してください。"
            return
        }

        do {
            let provider = preset.apiProvider.uppercased()
            try repository.updateConversationModelAndProvider(
                conversationId: conversationID,
                model: preset.model,
                provider: provider
            )

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

    func stopAutoConversation() {
        autoConversationTask?.cancel()
        autoConversationTask = nil
        isAutoConversationRunning = false
        autoConversationStatus = "自動会話を停止しました"
    }

    private func startAutoConversation(initial: String) {
        guard let repository else { return }
        autoConversationTask?.cancel()

        isAutoConversationRunning = true
        autoConversationStatus = "自動会話を開始しました"

        autoConversationTask = Task {
            do {
                try await repository.runAutoConversation(conversationId: conversationID, initialMessage: initial) { [weak self] turn, speaker, _ in
                    Task { @MainActor in
                        self?.autoConversationStatus = "\(turn)ターン目: \(speaker)"
                    }
                }
                await MainActor.run {
                    self.isAutoConversationRunning = false
                    self.autoConversationStatus = "自動会話が完了しました"
                }
            } catch {
                await MainActor.run {
                    self.isAutoConversationRunning = false
                    self.errorMessage = error.localizedDescription
                    self.autoConversationStatus = nil
                }
                DiagnosticsLogger.log(
                    "Auto conversation failed conversation=\(conversationID)",
                    category: .chat,
                    error: error
                )
            }
        }
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
                updateActiveChatPresetName()
                updateActiveSystemPromptPresetName()
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
}

private extension String {
    var nilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
