import Foundation
import Combine

struct SendMessageResult {
    var userMessageId: Int64
    var assistantMessageId: Int64
    var response: ProviderResponse
}

struct ShortcutRunResult: Sendable {
    var text: String
    var conversationId: Int64?
    var userMessageId: Int64?
    var assistantMessageId: Int64?
}

enum ProjectDeletionMode {
    case projectOnly
    case withConversations
}

final class ChatRepository {
    private static let defaultConversationTitles: Set<String> = ["New Chat", "Secret Chat"]
    private static let conversationTitleMaxLength = 50
    private static let branchSnippetMaxLength = 32

    private let conversations: ConversationRepository
    private let settings: SettingsRepository
    private let providers: ProviderGateway
    private let credentialStore: SecureCredentialStore
    private let modelService: OpenRouterModelService
    private let modelsDevCatalogRepository: ModelsDevCatalogRepository?
    private let skillRepository: AgentSkillRepository
    private let requestSettingsResolver: ProviderRequestSettingsResolver
    private let codexAuthRepository: CodexAuthRepository
    private let superGrokAuthRepository: SuperGrokAuthRepository
    private let openCodeGoUsageRepository: OpenCodeGoUsageRepository
    private let pricingRepository: any LiteLlmPricingEstimating
    private let fusionService: FusionService
    private let fusionTraceStore: FusionTraceStore
    private let fusionOrchestrator: FusionOrchestrator
    private let editorWorkspaces: EditorWorkspaceStore
    private let attachmentRepository: AttachmentRepository

    init(
        conversations: ConversationRepository,
        settings: SettingsRepository,
        providers: ProviderGateway,
        credentialStore: SecureCredentialStore,
        modelService: OpenRouterModelService,
        modelsDevCatalogRepository: ModelsDevCatalogRepository? = nil,
        skillRepository: AgentSkillRepository = AgentSkillRepository(),
        requestSettingsResolver: ProviderRequestSettingsResolver,
        codexAuthRepository: CodexAuthRepository,
        superGrokAuthRepository: SuperGrokAuthRepository,
        openCodeGoUsageRepository: OpenCodeGoUsageRepository? = nil,
        pricingRepository: any LiteLlmPricingEstimating = LiteLlmPricingRepository(),
        fusionService: FusionService,
        fusionTraceStore: FusionTraceStore,
        fusionOrchestrator: FusionOrchestrator = FusionOrchestrator(),
        editorWorkspaces: EditorWorkspaceStore = .shared,
        attachmentRepository: AttachmentRepository = AttachmentRepository()
    ) {
        self.conversations = conversations
        self.settings = settings
        self.providers = providers
        self.credentialStore = credentialStore
        self.modelService = modelService
        self.modelsDevCatalogRepository = modelsDevCatalogRepository
        self.skillRepository = skillRepository
        self.requestSettingsResolver = requestSettingsResolver
        self.codexAuthRepository = codexAuthRepository
        self.superGrokAuthRepository = superGrokAuthRepository
        self.openCodeGoUsageRepository = openCodeGoUsageRepository
            ?? OpenCodeGoUsageRepository()
        self.pricingRepository = pricingRepository
        self.fusionService = fusionService
        self.fusionTraceStore = fusionTraceStore
        self.fusionOrchestrator = fusionOrchestrator
        self.editorWorkspaces = editorWorkspaces
        self.attachmentRepository = attachmentRepository
    }

    // MARK: - Conversations

    func observeConversationList() -> AnyPublisher<[ConversationListEntry], Never> {
        conversations.observeConversationList()
    }

    func observeProjects() -> AnyPublisher<[ProjectListEntry], Never> {
        conversations.observeProjects()
    }

    func observeMessages(conversationId: Int64) -> AnyPublisher<[ChatMessageSummary], Never> {
        conversations.observeMessages(conversationId: conversationId)
    }

    func observeFullMessages(conversationId: Int64) -> AnyPublisher<[FullChatMessage], Never> {
        conversations.observeFullMessages(conversationId: conversationId)
    }

    func observeDualMessages(conversationId: Int64) -> AnyPublisher<[DualChatMessage], Never> {
        conversations.observeDualMessages(conversationId: conversationId)
    }

    func observeConversationStats(conversationId: Int64) -> AnyPublisher<ConversationStats, Never> {
        conversations.observeConversationStats(conversationId: conversationId)
    }

    func settingsPublisher() -> AnyPublisher<AppSettings, Never> {
        settings.observe()
    }

    func loadSettings() throws -> AppSettings {
        try settings.load()
    }

    func saveSettings(_ value: AppSettings) throws {
        let normalized = value.normalizedForPersistence()
        try settings.save(normalized)
    }

    func reasoningEffortCatalogPublisher() -> AnyPublisher<Void, Never> {
        let openRouter = modelService.modelsPublisher
            .map { _ in () }
            .eraseToAnyPublisher()
        guard let modelsDevCatalogRepository else { return openRouter }
        let modelsDev = modelsDevCatalogRepository.statePublisher
            .map { _ in () }
            .eraseToAnyPublisher()
        return Publishers.Merge(openRouter, modelsDev).eraseToAnyPublisher()
    }

    func refreshReasoningEffortCatalog(for provider: String) async {
        if provider.caseInsensitiveCompare("OPENROUTER") == .orderedSame {
            _ = await modelService.getAvailableModels()
            return
        }
        if ProviderReference(persistedID: provider).isModelsDev {
            _ = await modelsDevCatalogRepository?.load()
        }
    }

    func reasoningEffortConfiguration(
        settings: AppSettings,
        provider: String,
        model: String
    ) -> ChatReasoningEffortConfiguration? {
        let normalizedProvider = provider.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedProvider.isEmpty, !normalizedModel.isEmpty else { return nil }

        let reference = ProviderReference(persistedID: normalizedProvider)
        if let providerID = reference.modelsDevID {
            guard let catalogProvider = modelsDevCatalogRepository?.provider(for: reference),
                  let catalogModel = catalogProvider.models.first(where: { $0.id == normalizedModel })
            else { return nil }
            let saved = try? credentialStore.readSecret(
                key: ModelsDevReasoningPreference.storageKey(
                    providerID: providerID,
                    modelID: normalizedModel
                )
            )
            return makeReasoningEffortConfiguration(
                providerID: normalizedProvider,
                modelID: normalizedModel,
                modelLabel: catalogModel.name,
                options: catalogModel.supportedReasoningEfforts,
                selectedValue: saved ?? nil
            )
        }

        switch normalizedProvider {
        case "CODEX_AUTH":
            guard settings.codexReasoningEnabled,
                  let preset = CodexModelCatalog.findPreset(normalizedModel)
            else { return nil }
            return makeReasoningEffortConfiguration(
                providerID: normalizedProvider,
                modelID: normalizedModel,
                modelLabel: preset.displayName,
                options: preset.supportedReasoningEfforts.map(\.effort),
                selectedValue: settings.codexReasoningEffort
            )
        case "SUPERGROK":
            guard settings.superGrokReasoningEnabled,
                  let catalogModel = SuperGrokModelCatalog.model(for: normalizedModel),
                  catalogModel.supportsReasoning
            else { return nil }
            return makeReasoningEffortConfiguration(
                providerID: normalizedProvider,
                modelID: normalizedModel,
                modelLabel: catalogModel.displayName,
                options: ["low", "medium", "high"],
                selectedValue: settings.superGrokReasoningEffort
            )
        case "GEMINI":
            let options = GeminiModelUtils.getThinkingLevelOptions(model: normalizedModel)
            let selectedValue: String?
            if !GeminiModelUtils.isThinkingAlwaysOn(model: normalizedModel),
               !settings.geminiThinkingEnabled,
               let minimal = GeminiModelUtils.getMinimalThinkingLevel(model: normalizedModel) {
                selectedValue = minimal
            } else {
                selectedValue = GeminiModelUtils.normalizeThinkingLevel(
                    model: normalizedModel,
                    level: settings.geminiThinkingLevel
                ) ?? GeminiModelUtils.getDefaultThinkingLevel(model: normalizedModel)
            }
            return makeReasoningEffortConfiguration(
                providerID: normalizedProvider,
                modelID: normalizedModel,
                modelLabel: normalizedModel,
                options: options,
                selectedValue: selectedValue
            )
        case "OPENROUTER":
            guard let modelInfo = modelService.getModelById(normalizedModel),
                  let capabilities = modelInfo.reasoning,
                  capabilities.mandatory || settings.openRouterThinkingEnabled,
                  settings.openRouterReasoningMode.caseInsensitiveCompare("effort") == .orderedSame
            else { return nil }
            let options = capabilities.selectableEfforts
            let selectedValue = ChatReasoningEffortPresentationPolicy.matchingOption(
                settings.openRouterReasoningEffort,
                in: options
            ) ?? ChatReasoningEffortPresentationPolicy.matchingOption(
                capabilities.defaultEffort,
                in: options
            ) ?? options.first
            return makeReasoningEffortConfiguration(
                providerID: normalizedProvider,
                modelID: normalizedModel,
                modelLabel: modelInfo.name,
                options: options,
                selectedValue: selectedValue
            )
        default:
            return nil
        }
    }

    func setReasoningEffort(_ effort: String, provider: String, model: String) throws {
        let currentSettings = try loadSettings()
        guard let configuration = reasoningEffortConfiguration(
            settings: currentSettings,
            provider: provider,
            model: model
        ),
        let selectedValue = ChatReasoningEffortPresentationPolicy.matchingOption(
            effort,
            in: configuration.options
        ) else {
            throw ProviderClientError.parseFailure(
                L10n.text("このモデルでは推論エフォートを変更できません。")
            )
        }

        let reference = ProviderReference(persistedID: configuration.providerID)
        if let providerID = reference.modelsDevID {
            try credentialStore.saveSecret(
                selectedValue,
                key: ModelsDevReasoningPreference.storageKey(
                    providerID: providerID,
                    modelID: configuration.modelID
                )
            )
        } else {
            var updated = currentSettings
            switch configuration.providerID {
            case "CODEX_AUTH":
                updated.codexReasoningEnabled = true
                updated.codexReasoningEffort = selectedValue
            case "SUPERGROK":
                updated.superGrokReasoningEnabled = true
                updated.superGrokReasoningEffort = selectedValue
            case "GEMINI":
                updated.geminiThinkingEnabled = true
                updated.geminiThinkingLevel = selectedValue
            case "OPENROUTER":
                updated.openRouterThinkingEnabled = true
                updated.openRouterReasoningMode = "effort"
                updated.openRouterReasoningEffort = selectedValue
            default:
                throw ProviderClientError.parseFailure(
                    L10n.text("このプロバイダーでは推論エフォートを変更できません。")
                )
            }
            try saveSettings(updated)
        }

        DiagnosticsLogger.log(
            "Chat reasoning effort changed",
            category: .settings,
            metadata: [
                "provider": configuration.providerID,
                "model": configuration.modelID,
                "effort": selectedValue
            ]
        )
    }

    private func makeReasoningEffortConfiguration(
        providerID: String,
        modelID: String,
        modelLabel: String,
        options: [String],
        selectedValue: String?
    ) -> ChatReasoningEffortConfiguration? {
        let orderedOptions = ChatReasoningEffortPresentationPolicy.orderedOptions(options)
        guard orderedOptions.count > 1,
              let selectedValue = ChatReasoningEffortPresentationPolicy.matchingOption(
                  selectedValue,
                  in: orderedOptions
              )
        else { return nil }
        let normalizedLabel = modelLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        return ChatReasoningEffortConfiguration(
            providerID: providerID,
            modelID: modelID,
            modelLabel: normalizedLabel.isEmpty ? modelID : normalizedLabel,
            options: orderedOptions,
            selectedValue: selectedValue
        )
    }

    func setSelectedVariant(messageId: Int64, variantIndex: Int) throws {
        try conversations.updateMessageSelectedVariantIndex(messageId: messageId, variantIndex: variantIndex)
    }

    func conversation(id: Int64) throws -> Conversation? {
        try conversations.fetchConversation(id: id)
    }

    func exportConversation(id: Int64, mode: ConversationExportMode = .standard) async throws -> URL {
        if try conversations.fetchConversation(id: id)?.isSecret == true {
            throw ProviderClientError.parseFailure(
                L10n.text("シークレットチャットは端末に平文アーカイブを残すため書き出せません。")
            )
        }
        let conversations = conversations
        return try await Task.detached(priority: .userInitiated) {
            let snapshot = try conversations.fetchDebugExport(conversationId: id)
            return try ConversationExportService.createArchive(snapshot: snapshot, mode: mode)
        }.value
    }

    func ensureInitialConversation() throws -> Int64 {
        if let existing = try conversations.fetchLatestEmptyConversation(title: "New Chat", projectId: nil), let id = existing.id {
            return id
        }

        let currentSettings = try settingsForNewConversation()
        return try conversations.createConversation(
            title: "New Chat",
            model: currentSettings.currentModel(),
            provider: currentSettings.apiProvider,
            systemPrompt: currentSettings.effectiveSystemPrompt()
        )
    }

    func createConversation(title: String = "New Chat", projectId: Int64? = nil) throws -> Int64 {
        if title == "New Chat",
           let existing = try conversations.fetchLatestEmptyConversation(title: title, projectId: projectId),
           let id = existing.id {
            return id
        }

        let currentSettings = try settingsForNewConversation()
        let resolvedPrompt = try resolveSystemPromptForProject(
            projectId: projectId,
            fallbackPrompt: currentSettings.effectiveSystemPrompt()
        )
        return try conversations.createConversation(
            title: title,
            model: currentSettings.currentModel(),
            provider: currentSettings.apiProvider,
            systemPrompt: resolvedPrompt,
            projectId: projectId
        )
    }

    func createConversationWithPendingInitialMessage(
        _ message: String,
        projectId: Int64
    ) throws -> Int64 {
        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedMessage.isEmpty else {
            throw ProviderClientError.parseFailure(L10n.text("開始メッセージを入力してください。"))
        }
        let currentSettings = try settingsForNewConversation()
        let resolvedPrompt = try resolveSystemPromptForProject(
            projectId: projectId,
            fallbackPrompt: currentSettings.effectiveSystemPrompt()
        )
        return try conversations.createConversation(
            title: "New Chat",
            model: currentSettings.currentModel(),
            provider: currentSettings.apiProvider,
            systemPrompt: resolvedPrompt,
            projectId: projectId,
            pendingInitialMessage: normalizedMessage
        )
    }

    func pendingInitialMessage(conversationId: Int64) throws -> String? {
        try conversations.pendingInitialMessage(conversationId: conversationId)
    }

    func createSecretConversation(projectId: Int64? = nil) throws -> Int64 {
        let currentSettings = try settingsForNewConversation()
        let resolvedPrompt = try resolveSystemPromptForProject(
            projectId: projectId,
            fallbackPrompt: currentSettings.effectiveSystemPrompt()
        )
        return try conversations.createConversation(
            title: "Secret Chat",
            model: currentSettings.currentModel(),
            provider: currentSettings.apiProvider,
            systemPrompt: resolvedPrompt,
            isSecret: true,
            projectId: projectId
        )
    }

    func createProject(title: String, instructions: String?) throws -> Int64 {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw ProviderClientError.parseFailure(L10n.text("プロジェクト名を入力してください。"))
        }
        return try conversations.createProject(title: normalizedTitle, instructions: instructions)
    }

    func fetchProject(id: Int64) throws -> ChatProject? {
        try conversations.fetchProject(id: id)
    }

    func updateProject(
        id: Int64,
        title: String,
        instructions: String?,
        iconName: String? = nil,
        colorHex: String? = nil,
        updateConversationsPrompt: Bool = true
    ) throws {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else {
            throw ProviderClientError.parseFailure(L10n.text("プロジェクト名を入力してください。"))
        }
        let normalizedInstructions = instructions?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalInstructions = (normalizedInstructions?.isEmpty == false) ? normalizedInstructions : nil

        var conversationsSystemPrompt: String?
        if updateConversationsPrompt {
            let defaultPrompt = try loadSettings().systemPrompt
            conversationsSystemPrompt = finalInstructions ?? defaultPrompt
        }

        try conversations.updateProject(
            id: id,
            title: normalizedTitle,
            instructions: finalInstructions,
            iconName: iconName,
            colorHex: colorHex,
            updateConversationsPrompt: updateConversationsPrompt,
            conversationsSystemPrompt: conversationsSystemPrompt
        )
    }

    func updateProjectInstructions(id: Int64, instructions: String?) throws {
        guard let project = try conversations.fetchProject(id: id) else {
            throw ProviderClientError.parseFailure("Project not found")
        }
        try updateProject(
            id: id,
            title: project.title,
            instructions: instructions,
            iconName: project.iconName,
            colorHex: project.colorHex,
            updateConversationsPrompt: true
        )
    }

    func projectConversationCount(projectId: Int64) throws -> Int {
        try conversations.countConversations(projectId: projectId)
    }

    func assignConversationToProject(conversationId: Int64, projectId: Int64?) throws {
        guard var conversation = try conversations.fetchConversation(id: conversationId) else {
            throw ProviderClientError.parseFailure("Conversation not found")
        }

        if let projectId {
            let project = try conversations.fetchProject(id: projectId)
            guard let project else {
                throw ProviderClientError.parseFailure("Project not found")
            }
            if let instructions = project.instructions?.trimmingCharacters(in: .whitespacesAndNewlines), !instructions.isEmpty {
                conversation.systemPrompt = instructions
                _ = try conversations.upsertConversation(conversation)
            }
        }

        try conversations.assignConversationToProject(conversationId: conversationId, projectId: projectId)
    }

    func deleteConversation(id: Int64) throws {
        let ownedPaths = try conversations.attachmentPathsForConversation(id: id)
        try attachmentRepository.deleteOwnedFiles(paths: ownedPaths)
        try attachmentRepository.deleteConversationArtifacts(conversationID: id)
        try conversations.deleteConversation(id: id)
        try editorWorkspaces.delete(sessionID: String(id))
        Task { await PythonWorker.shared.resetSession(sessionID: String(id)) }
    }

    func deleteConversations(ids: Set<Int64>) throws {
        let paths = try ids.flatMap { try conversations.attachmentPathsForConversation(id: $0) }
        try attachmentRepository.deleteOwnedFiles(paths: paths)
        for id in ids {
            try attachmentRepository.deleteConversationArtifacts(conversationID: id)
        }
        try conversations.deleteConversations(ids: ids)
        for id in ids {
            try editorWorkspaces.delete(sessionID: String(id))
            Task { await PythonWorker.shared.resetSession(sessionID: String(id)) }
        }
    }

    @discardableResult
    func deleteSecretConversationIfNeeded(id: Int64) throws -> Bool {
        let ownedPaths = try conversations.attachmentPathsForSecretConversation(id: id)
        guard try conversations.fetchConversation(id: id)?.isSecret == true else { return false }
        try attachmentRepository.deleteOwnedFiles(paths: ownedPaths)
        try attachmentRepository.deleteConversationArtifacts(conversationID: id)
        let deleted = try conversations.deleteSecretConversationIfNeeded(id: id)
        if deleted {
            try editorWorkspaces.delete(sessionID: String(id))
            Task { await PythonWorker.shared.resetSession(sessionID: String(id)) }
        }
        return deleted
    }

    func purgeSecretConversations() throws {
        let ids = try conversations.secretConversationIDs()
        let paths = try ids.flatMap { try conversations.attachmentPathsForSecretConversation(id: $0) }
        try attachmentRepository.deleteOwnedFiles(paths: paths)
        for id in ids {
            try attachmentRepository.deleteConversationArtifacts(conversationID: id)
            try editorWorkspaces.delete(sessionID: String(id))
            Task { await PythonWorker.shared.resetSession(sessionID: String(id)) }
        }
        try conversations.purgeSecretConversations()
    }

    func deleteProject(id: Int64, mode: ProjectDeletionMode) throws {
        switch mode {
        case .projectOnly:
            try conversations.deleteProject(id: id)
        case .withConversations:
            let conversationIDs = try conversations.conversationIDs(projectId: id)
            let paths = try conversationIDs.flatMap { try conversations.attachmentPathsForConversation(id: $0) }
            try attachmentRepository.deleteOwnedFiles(paths: paths)
            for conversationID in conversationIDs {
                try attachmentRepository.deleteConversationArtifacts(conversationID: conversationID)
            }
            try conversations.deleteProjectWithConversations(id: id)
            for conversationID in conversationIDs {
                try editorWorkspaces.delete(sessionID: String(conversationID))
                Task { await PythonWorker.shared.resetSession(sessionID: String(conversationID)) }
            }
        }
    }

    @discardableResult
    func setSecretMode(conversationId: Int64, enabled: Bool) throws -> Conversation {
        try conversations.setSecretModeIfEmpty(id: conversationId, enabled: enabled)
    }

    func updateConversationSystemPrompt(conversationId: Int64, systemPrompt: String?) throws {
        guard var conversation = try conversations.fetchConversation(id: conversationId) else {
            throw ProviderClientError.parseFailure("Conversation not found")
        }
        conversation.systemPrompt = systemPrompt
        _ = try conversations.upsertConversation(conversation)
    }

    func updateConversationModelAndProvider(
        conversationId: Int64,
        model: String,
        provider: String
    ) throws {
        guard var conversation = try conversations.fetchConversation(id: conversationId) else {
            throw ProviderClientError.parseFailure("Conversation not found")
        }
        conversation.model = model
        conversation.apiProvider = provider.uppercased()
        _ = try conversations.upsertConversation(conversation)
    }

    func branchConversation(from conversationId: Int64, messageId: Int64) throws -> Int64 {
        guard let baseConversation = try conversations.fetchConversation(id: conversationId) else {
            throw ProviderClientError.parseFailure("Conversation not found")
        }

        let summaries = try conversations.fetchMessageSummaries(conversationId: conversationId)
        guard let targetIndex = summaries.firstIndex(where: { $0.id == messageId }) else {
            throw ProviderClientError.parseFailure("Message not found")
        }

        let selected = summaries.prefix(targetIndex + 1)
        let branchSourceText = try conversations.fetchFullMessage(id: messageId)?.displayText
        let title = buildBranchTitle(baseTitle: baseConversation.title, messageText: branchSourceText)
        let newConversationId = try conversations.createConversation(
            title: title,
            model: baseConversation.model,
            provider: baseConversation.apiProvider,
            systemPrompt: baseConversation.systemPrompt,
            isSecret: baseConversation.isSecret,
            projectId: baseConversation.projectId
        )

        for summary in selected {
            guard let full = try conversations.fetchFullMessage(id: summary.id) else { continue }
            let newMessageId = try conversations.insertMessage(
                ChatMessage(
                    conversationId: newConversationId,
                    role: full.message.role,
                    text: full.displayText,
                    attachmentsJSON: full.displayAttachmentsJSON
                )
            )
            if let thinking = full.displayThinkingStream, !thinking.isEmpty {
                try conversations.saveThinking(messageId: newMessageId, stream: thinking)
            }
        }

        return newConversationId
    }

    func syncNewChatWithSettingsIfEmpty(
        conversationId: Int64,
        settings currentSettings: AppSettings,
        previousSettings: AppSettings?
    ) throws -> Conversation? {
        guard var conversation = try conversations.fetchConversation(id: conversationId) else {
            return nil
        }
        guard conversation.title == "New Chat" else {
            return conversation
        }
        guard conversation.projectId == nil else {
            return conversation
        }
        guard try conversations.isConversationEmpty(conversationId: conversationId) else {
            return conversation
        }

        let shouldSync: Bool
        if let previousSettings {
            let previousProvider = previousSettings.apiProvider.uppercased()
            let previousModel = previousSettings.currentModel()
            let previousPrompt = previousSettings.effectiveSystemPrompt()?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            let conversationProvider = conversation.apiProvider.uppercased()
            let conversationModel = conversation.model.trimmingCharacters(in: .whitespacesAndNewlines)
            let conversationPrompt = conversation.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)

            shouldSync = conversationProvider == previousProvider &&
                (conversationModel.isEmpty ? previousModel : conversationModel) == previousModel &&
                conversationPrompt == previousPrompt
        } else {
            shouldSync = true
        }

        guard shouldSync else {
            return conversation
        }

        let nextProvider = currentSettings.apiProvider.uppercased()
        let nextModel = currentSettings.currentModel()
        let nextPrompt = currentSettings.effectiveSystemPrompt()?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if conversation.apiProvider.uppercased() == nextProvider &&
            conversation.model == nextModel &&
            conversation.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines) == nextPrompt {
            return conversation
        }

        conversation.apiProvider = nextProvider
        conversation.model = nextModel
        conversation.systemPrompt = nextPrompt
        _ = try conversations.upsertConversation(conversation)
        return try conversations.fetchConversation(id: conversationId) ?? conversation
    }

    // MARK: - Message Send

    func isUserTurnCommitted(
        conversationId: Int64,
        text: String,
        attachments: [String],
        dualMode: Bool,
        startedAtMs: Int64
    ) throws -> Bool {
        if dualMode {
            return try conversations.fetchDualMessages(conversationId: conversationId).contains { message in
                message.parsedRole == .user &&
                    message.createdAtMs >= startedAtMs &&
                    message.userText == text &&
                    message.attachments == attachments
            }
        }
        let expectedAttachments = encodeArray(attachments)
        return try conversations.fetchMessages(conversationId: conversationId).contains { message in
            message.role == "user" &&
                message.createdAtMs >= startedAtMs &&
                message.text == text &&
                message.attachmentsJSON == expectedAttachments
        }
    }

    func sendMessage(
        conversationId: Int64,
        text: String,
        attachments: [String],
        settingsOverride: AppSettings? = nil,
        onStreamEvent: (@Sendable (ProviderStreamEvent) -> Void)? = nil,
        onStreamingSnapshot: (@Sendable (ChatStreamingSnapshot) -> Void)? = nil
    ) async throws -> SendMessageResult {
        try await withConversationMetrics(conversationId: conversationId) {
            try await self.sendMessageMeasured(
                conversationId: conversationId,
                text: text,
                attachments: attachments,
                settingsOverride: settingsOverride,
                onStreamEvent: onStreamEvent,
                onStreamingSnapshot: onStreamingSnapshot
            )
        }
    }

    private func sendMessageMeasured(
        conversationId: Int64,
        text: String,
        attachments: [String],
        settingsOverride: AppSettings? = nil,
        onStreamEvent: (@Sendable (ProviderStreamEvent) -> Void)? = nil,
        onStreamingSnapshot: (@Sendable (ChatStreamingSnapshot) -> Void)? = nil
    ) async throws -> SendMessageResult {
        let settings = try settingsOverride ?? self.settings.load()
        guard var conversation = try conversations.fetchConversation(id: conversationId) else {
            throw ProviderClientError.parseFailure("Conversation not found")
        }
        guard !conversation.isSecret || attachments.isEmpty else {
            throw ProviderClientError.parseFailure(
                L10n.text("シークレットチャットでは添付ファイルを送信できません。")
            )
        }
        let isFirstMessage = try conversations.isConversationEmpty(conversationId: conversationId)

        var requestMessages = try conversations.fetchProviderHistory(conversationId: conversationId)
            .flatMap(\.providerMessages)
        requestMessages.append(
            ProviderRequestMessage(role: "user", content: text, attachments: attachments)
        )
        let request = try await buildProviderRequest(
            conversation: conversation,
            settings: settings,
            conversationId: conversationId,
            providerMessages: requestMessages
        )
        let provider = conversation.apiProvider

        let userMessageId = try conversations.insertMessage(
            ChatMessage(
                conversationId: conversationId,
                role: "user",
                text: text,
                attachmentsJSON: encodeArray(attachments)
            )
        )
        try updateConversationTitleIfNeeded(
            conversation: &conversation,
            firstPrompt: text,
            isFirstMessage: isFirstMessage
        )

        if settings.isStreamingEnabled {
            return try await streamMessage(
                conversationId: conversationId,
                userMessageId: userMessageId,
                request: request,
                provider: provider,
                onStreamEvent: onStreamEvent,
                onStreamingSnapshot: onStreamingSnapshot
            )
        }

        let assistantMessageId = try conversations.insertMessage(
            ChatMessage(
                conversationId: conversationId,
                role: "model",
                text: ""
            )
        )
        let response = try await runToolCallingTurn(
            request: request,
            provider: provider,
            conversationId: conversationId,
            persistenceKind: .message(messageId: assistantMessageId),
            streamEnabled: false,
            onStreamEvent: onStreamEvent,
            onStreamingSnapshot: onStreamingSnapshot
        )
        await recordTokenUsageIfAvailable(
            provider: conversation.apiProvider,
            model: conversation.model,
            usage: response.usage,
            usageSamples: response.usageSamples,
            conversationId: conversationId,
            requestType: "chat_non_stream"
        )

        return SendMessageResult(
            userMessageId: userMessageId,
            assistantMessageId: assistantMessageId,
            response: response
        )
    }

    func regenerateLastAssistantVariant(
        conversationId: Int64,
        settingsOverride: AppSettings? = nil,
        onStreamEvent: (@Sendable (ProviderStreamEvent) -> Void)? = nil,
        onStreamingSnapshot: (@Sendable (ChatStreamingSnapshot) -> Void)? = nil
    ) async throws -> Int64 {
        try await withConversationMetrics(conversationId: conversationId) {
            try await self.regenerateLastAssistantVariantMeasured(
                conversationId: conversationId,
                settingsOverride: settingsOverride,
                onStreamEvent: onStreamEvent,
                onStreamingSnapshot: onStreamingSnapshot
            )
        }
    }

    private func regenerateLastAssistantVariantMeasured(
        conversationId: Int64,
        settingsOverride: AppSettings? = nil,
        onStreamEvent: (@Sendable (ProviderStreamEvent) -> Void)? = nil,
        onStreamingSnapshot: (@Sendable (ChatStreamingSnapshot) -> Void)? = nil
    ) async throws -> Int64 {
        let settings = try settingsOverride ?? self.settings.load()
        guard let conversation = try conversations.fetchConversation(id: conversationId) else {
            throw ProviderClientError.parseFailure("Conversation not found")
        }

        let history = try conversations.fetchProviderHistory(conversationId: conversationId)
        guard let targetIndex = history.lastIndex(where: { $0.role == "assistant" }) else {
            throw ProviderClientError.parseFailure(L10n.text("再生成できるAIメッセージがありません。"))
        }
        guard targetIndex == history.count - 1 else {
            throw ProviderClientError.parseFailure(L10n.text("最後のAIメッセージのみ再生成できます。"))
        }
        guard targetIndex > 0, history[targetIndex - 1].role == "user" else {
            throw ProviderClientError.parseFailure(L10n.text("再生成対象の直前にユーザーメッセージがありません。"))
        }

        let targetMessageID = history[targetIndex].messageId
        let requestMessages = Array(history.prefix(targetIndex)).flatMap(\.providerMessages)
        let request = try await buildProviderRequest(
            conversation: conversation,
            settings: settings,
            conversationId: conversationId,
            providerMessages: requestMessages
        )
        let provider = conversation.apiProvider

        if settings.isStreamingEnabled {
            try await streamRegeneratedVariant(
                request: request,
                provider: provider,
                conversationId: conversationId,
                baseMessageId: targetMessageID,
                onStreamEvent: onStreamEvent,
                onStreamingSnapshot: onStreamingSnapshot
            )
            return targetMessageID
        }

        let variant = try conversations.insertMessageVariant(
            baseMessageId: targetMessageID,
            text: "",
            attachmentsJSON: "[]",
            thinkingStream: nil
        )
        guard let variantId = variant.id else {
            throw ProviderClientError.parseFailure("Variant creation failed")
        }
        let response = try await runToolCallingTurn(
            request: request,
            provider: provider,
            conversationId: conversationId,
            persistenceKind: .variant(variantId: variantId, snapshotMessageId: targetMessageID),
            streamEnabled: false,
            onStreamEvent: onStreamEvent,
            onStreamingSnapshot: onStreamingSnapshot
        )
        await recordTokenUsageIfAvailable(
            provider: conversation.apiProvider,
            model: conversation.model,
            usage: response.usage,
            usageSamples: response.usageSamples,
            conversationId: conversationId,
            requestType: "regenerate_non_stream"
        )
        return targetMessageID
    }

    private func streamMessage(
        conversationId: Int64,
        userMessageId: Int64,
        request: ProviderRequest,
        provider: String,
        onStreamEvent: (@Sendable (ProviderStreamEvent) -> Void)?,
        onStreamingSnapshot: (@Sendable (ChatStreamingSnapshot) -> Void)?
    ) async throws -> SendMessageResult {
        let bgGuard = BackgroundTaskGuard()
        bgGuard.begin(name: "YamabikoChatStreaming")
        defer { bgGuard.end() }

        let assistantMessageId = try conversations.insertMessage(
            ChatMessage(
                conversationId: conversationId,
                role: "model",
                text: ""
            )
        )

        let response = try await runToolCallingTurn(
            request: request,
            provider: provider,
            conversationId: conversationId,
            persistenceKind: .message(messageId: assistantMessageId),
            streamEnabled: true,
            onStreamEvent: onStreamEvent,
            onStreamingSnapshot: onStreamingSnapshot
        )

        await recordTokenUsageIfAvailable(
            provider: provider,
            model: request.model,
            usage: response.usage,
            usageSamples: response.usageSamples,
            conversationId: conversationId,
            requestType: "chat_stream"
        )

        return SendMessageResult(
            userMessageId: userMessageId,
            assistantMessageId: assistantMessageId,
            response: response
        )
    }

    private func streamRegeneratedVariant(
        request: ProviderRequest,
        provider: String,
        conversationId: Int64,
        baseMessageId: Int64,
        onStreamEvent: (@Sendable (ProviderStreamEvent) -> Void)?,
        onStreamingSnapshot: (@Sendable (ChatStreamingSnapshot) -> Void)?
    ) async throws {
        let variant = try conversations.insertMessageVariant(
            baseMessageId: baseMessageId,
            text: "",
            attachmentsJSON: "[]",
            thinkingStream: nil
        )
        guard let variantId = variant.id else {
            throw ProviderClientError.parseFailure("Variant creation failed")
        }

        let response = try await runToolCallingTurn(
            request: request,
            provider: provider,
            conversationId: conversationId,
            persistenceKind: .variant(variantId: variantId, snapshotMessageId: baseMessageId),
            streamEnabled: true,
            onStreamEvent: onStreamEvent,
            onStreamingSnapshot: onStreamingSnapshot
        )

        await recordTokenUsageIfAvailable(
            provider: provider,
            model: request.model,
            usage: response.usage,
            usageSamples: response.usageSamples,
            conversationId: conversationId,
            requestType: "regenerate_stream"
        )
    }

    private func buildProviderRequest(
        conversation: Conversation,
        settings: AppSettings,
        conversationId: Int64,
        providerMessages: [ProviderRequestMessage]? = nil
    ) async throws -> ProviderRequest {
        let resolvedMessages: [ProviderRequestMessage]
        if let providerMessages {
            resolvedMessages = providerMessages
        } else {
            let history = try conversations.fetchProviderHistory(conversationId: conversationId)
            resolvedMessages = history.flatMap(\.providerMessages)
        }

        let resolvedSettings = try await requestSettingsResolver.resolve(
            settings: settings,
            provider: conversation.apiProvider,
            model: conversation.model,
            enablesUserQuestions: true
        )
        var metadata = resolvedSettings.metadata
        if conversation.isSecret {
            metadata["supportsClientTools"] = "false"
        }
        if conversation.apiProvider.uppercased() == "CODEX_AUTH" {
            let sessionId = try conversations.getOrCreateCodexSessionId(conversationId: conversationId)
            metadata["codexSessionId"] = sessionId
        }
        metadata["provider"] = conversation.apiProvider
        metadata["promptCacheKey"] = "conversation-\(conversationId)"
        metadata["pythonSessionId"] = String(conversationId)
        metadata["editorSessionId"] = String(conversationId)
        metadata["supportsVision"] = await visionMetadataFlag(
            provider: conversation.apiProvider,
            model: conversation.model
        )

        let skillApplication = conversation.isSecret
            ? AgentSkillPromptApplication(messages: resolvedMessages, currentContext: nil)
            : try applySkillContext(
                messages: resolvedMessages,
                conversationID: String(conversationId),
                clientToolsSupported: resolvedSettings.metadata["supportsClientTools"] == "true"
            )
        return ProviderRequest(
            model: conversation.model,
            messages: skillApplication.messages,
            systemPrompt: SystemPromptComposer.composeForAPI(
                conversation.systemPrompt,
                enablesAgenticWebSearch: !conversation.isSecret && resolvedSettings.tools.containsWebSearchTool,
                enablesEditorInstructions: !conversation.isSecret && resolvedSettings.tools.containsEditorTool,
                enablesUserQuestionInstructions: !conversation.isSecret && resolvedSettings.tools.containsAskUserQuestionTool
            ),
            stream: settings.isStreamingEnabled,
            tools: conversation.isSecret ? [] : resolvedSettings.tools,
            thinking: resolvedSettings.thinking,
            provider: resolvedSettings.routing,
            metadata: metadata,
            skillContext: skillApplication.currentContext
        )
    }

    private func runToolCallingTurn(
        request: ProviderRequest,
        provider: String,
        conversationId: Int64,
        persistenceKind: ChatStreamPersistenceKind,
        streamEnabled: Bool,
        persistResults: Bool = true,
        onStreamEvent: (@Sendable (ProviderStreamEvent) -> Void)?,
        onStreamingSnapshot: (@Sendable (ChatStreamingSnapshot) -> Void)?
    ) async throws -> ProviderResponse {
        do {
            let response = try await executeProviderRound(
                request: request,
                provider: provider,
                persistenceKind: persistenceKind,
                streamEnabled: streamEnabled,
                persistResults: persistResults,
                onStreamEvent: onStreamEvent,
                onStreamingSnapshot: onStreamingSnapshot
            )
            if persistResults {
                try persistProviderResponse(response, kind: persistenceKind)
            }
            return response
        } catch {
            if persistResults {
                let target = ChatStreamSessionTarget(conversations: conversations, kind: persistenceKind)
                try? target.writeErrorPlaceholder(error)
            }
            throw error
        }
    }

    private func executeProviderRound(
        request: ProviderRequest,
        provider: String,
        persistenceKind: ChatStreamPersistenceKind,
        streamEnabled: Bool,
        persistResults: Bool = true,
        onStreamEvent: (@Sendable (ProviderStreamEvent) -> Void)?,
        onStreamingSnapshot: (@Sendable (ChatStreamingSnapshot) -> Void)?
    ) async throws -> ProviderResponse {
        if streamEnabled {
            let stream = try await providers.stream(request: request, providerID: provider)
            let session = try await ChatStreamSession.run(
                stream: stream,
                conversations: conversations,
                kind: persistenceKind,
                onStreamEvent: onStreamEvent,
                onStreamingSnapshot: onStreamingSnapshot
            )
            let response = ProviderResponse(
                text: session.text,
                reasoningSummary: session.reasoningText.trimmedNonEmpty,
                raw: nil,
                usage: session.usage,
                usageSamples: session.usageSamples,
                toolCalls: session.toolCalls,
                toolActivity: session.toolActivity,
                piExecution: session.toolActivity?.piExecution
            )
            if persistResults {
                try persistProviderResponse(response, kind: persistenceKind)
            }
            return response
        }

        let response = try await providers.generate(request: request, providerID: provider)
        if persistResults {
            try persistProviderResponse(response, kind: persistenceKind)
        }
        return response
    }

    private func persistProviderResponse(
        _ response: ProviderResponse,
        kind: ChatStreamPersistenceKind
    ) throws {
        let target = ChatStreamSessionTarget(conversations: conversations, kind: kind)
        try target.persist(
            text: response.text,
            thinking: response.reasoningSummary ?? ""
        )
        var activity = response.toolActivity ?? ToolActivityPayload()
        activity.piExecution = response.piExecution ?? activity.piExecution
        if activity.hasPersistableContent {
            try target.persistToolActivity(activity)
            try target.persistAttachments(activity.attachmentPaths)
        }
    }

    func sendDualMessage(
        conversationId: Int64,
        text: String,
        attachments: [String] = [],
        settingsOverride: AppSettings? = nil
    ) async throws -> DualChatMessage {
        try await withConversationMetrics(conversationId: conversationId) {
            try await self.sendDualMessageMeasured(
                conversationId: conversationId,
                text: text,
                attachments: attachments,
                settingsOverride: settingsOverride
            )
        }
    }

    private func sendDualMessageMeasured(
        conversationId: Int64,
        text: String,
        attachments: [String],
        settingsOverride: AppSettings?
    ) async throws -> DualChatMessage {
        let bgGuard = BackgroundTaskGuard()
        bgGuard.begin(name: "YamabikoChatDualStreaming")
        defer { bgGuard.end() }

        let settings = try settingsOverride ?? self.settings.load()
        guard var conversation = try conversations.fetchConversation(id: conversationId) else {
            throw ProviderClientError.parseFailure("Conversation not found")
        }
        guard !conversation.isSecret || attachments.isEmpty else {
            throw ProviderClientError.parseFailure(
                L10n.text("シークレットチャットでは添付ファイルを送信できません。")
            )
        }
        let isFirstMessage = try conversations.isConversationEmpty(conversationId: conversationId)

        let normalizedAttachments = attachments.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let userMessage = DualChatMessage(
            conversationId: conversationId,
            role: DualChatMessage.Role.user.rawValue,
            userText: text,
            modelAText: "",
            modelBText: "",
            modelAName: settings.dualModelA,
            modelBName: settings.dualModelB,
            providerA: settings.dualProviderA,
            providerB: settings.dualProviderB,
            attachmentsJSON: encodeArray(normalizedAttachments)
        )
        let previousDualMessages = try conversations.fetchDualMessages(conversationId: conversationId)
        var historyA = try buildDualHistory(
            conversationId: conversationId,
            dualMessages: previousDualMessages,
            modelSide: .a
        )
        var historyB = try buildDualHistory(
            conversationId: conversationId,
            dualMessages: previousDualMessages,
            modelSide: .b
        )
        let currentUserMessage = ProviderRequestMessage(
            role: "user",
            content: text,
            attachments: normalizedAttachments
        )
        historyA.append(currentUserMessage)
        historyB.append(currentUserMessage)

        let requestA = try await buildSingleTurnRequest(
            model: settings.dualModelA,
            text: text,
            systemPrompt: settings.dualSystemPromptA,
            provider: settings.dualProviderA,
            settings: settings,
            stream: false,
            messages: historyA,
            context: .dualA,
            promptCacheKey: "conversation-\(conversationId)-dual-a",
            clientToolsAllowed: !conversation.isSecret
        )

        let requestB = try await buildSingleTurnRequest(
            model: settings.dualModelB,
            text: text,
            systemPrompt: settings.dualSystemPromptB,
            provider: settings.dualProviderB,
            settings: settings,
            stream: false,
            messages: historyB,
            context: .dualB,
            promptCacheKey: "conversation-\(conversationId)-dual-b",
            clientToolsAllowed: !conversation.isSecret
        )

        _ = try conversations.insertDualMessage(userMessage)

        let modelCreatedAt = max(
            Int64(Date().timeIntervalSince1970 * 1000),
            userMessage.createdAtMs + 1
        )
        var modelRow = DualChatMessage(
            conversationId: conversationId,
            role: DualChatMessage.Role.dualModel.rawValue,
            userText: "",
            modelAText: "",
            modelBText: "",
            modelAName: settings.dualModelA,
            modelBName: settings.dualModelB,
            providerA: settings.dualProviderA,
            providerB: settings.dualProviderB,
            modelAStatus: DualChatMessage.SideStatus.pending.rawValue,
            modelBStatus: DualChatMessage.SideStatus.pending.rawValue,
            createdAtMs: modelCreatedAt
        )
        let modelRowId = try conversations.insertDualMessage(modelRow)
        modelRow.id = modelRowId
        let dualActivityQueue = DispatchQueue(label: "com.porarri.yamabikochat.dual-tool-activity.\(modelRowId)")

        var resultA: DualSideResult?
        var resultB: DualSideResult?
        try await withThrowingTaskGroup(of: (DualHistorySide, DualSideResult).self) { group in
            group.addTask { [self, conversations] in
                let result = await generateDualSideResponse(
                    request: requestA,
                    provider: settings.dualProviderA,
                    model: settings.dualModelA,
                    onToolActivity: { event in
                        dualActivityQueue.sync {
                            try? Self.persistDualToolEvent(
                                event,
                                side: .a,
                                rowId: modelRowId,
                                conversationId: conversationId,
                                conversations: conversations
                            )
                        }
                    }
                )
                return (.a, result)
            }
            group.addTask { [self, conversations] in
                let result = await generateDualSideResponse(
                    request: requestB,
                    provider: settings.dualProviderB,
                    model: settings.dualModelB,
                    onToolActivity: { event in
                        dualActivityQueue.sync {
                            try? Self.persistDualToolEvent(
                                event,
                                side: .b,
                                rowId: modelRowId,
                                conversationId: conversationId,
                                conversations: conversations
                            )
                        }
                    }
                )
                return (.b, result)
            }

            for try await (side, result) in group {
                switch side {
                case .a:
                    resultA = result
                    modelRow.modelAText = result.text
                    modelRow.modelAThinking = result.reasoning
                    modelRow.modelAToolActivityJSON = DualChatMessage.encodeToolActivity(result.toolActivity)
                    modelRow.modelAStatus = result.error == nil
                        ? DualChatMessage.SideStatus.completed.rawValue
                        : DualChatMessage.SideStatus.failed.rawValue
                    modelRow.modelAError = result.error?.localizedDescription
                case .b:
                    resultB = result
                    modelRow.modelBText = result.text
                    modelRow.modelBThinking = result.reasoning
                    modelRow.modelBToolActivityJSON = DualChatMessage.encodeToolActivity(result.toolActivity)
                    modelRow.modelBStatus = result.error == nil
                        ? DualChatMessage.SideStatus.completed.rawValue
                        : DualChatMessage.SideStatus.failed.rawValue
                    modelRow.modelBError = result.error?.localizedDescription
                }
                try conversations.updateDualMessage(modelRow)
            }
        }

        guard let resultA, let resultB else {
            throw ProviderClientError.parseFailure(L10n.text("Dual response did not complete."))
        }

        await recordTokenUsageIfAvailable(
            provider: settings.dualProviderA,
            model: settings.dualModelA,
            usage: resultA.usage,
            usageSamples: resultA.usageSamples,
            conversationId: conversationId,
            requestType: "dual_a"
        )
        await recordTokenUsageIfAvailable(
            provider: settings.dualProviderB,
            model: settings.dualModelB,
            usage: resultB.usage,
            usageSamples: resultB.usageSamples,
            conversationId: conversationId,
            requestType: "dual_b"
        )

        if let errA = resultA.error {
            DiagnosticsLogger.log(
                "Dual response A failed",
                category: .network,
                metadata: [
                    "provider": settings.dualProviderA.uppercased(),
                    "model": settings.dualModelA
                ],
                error: errA
            )
        }
        if let errB = resultB.error {
            DiagnosticsLogger.log(
                "Dual response B failed",
                category: .network,
                metadata: [
                    "provider": settings.dualProviderB.uppercased(),
                    "model": settings.dualModelB
                ],
                error: errB
            )
        }

        try updateConversationTitleIfNeeded(
            conversation: &conversation,
            firstPrompt: text,
            isFirstMessage: isFirstMessage
        )

        return modelRow
    }

    func sendFusionMessage(
        conversationId: Int64,
        text: String,
        attachments: [String] = [],
        settingsOverride: AppSettings? = nil,
        onFusionProgress: (@Sendable (FusionProgressSnapshot) -> Void)? = nil,
        onStreamEvent: (@Sendable (ProviderStreamEvent) -> Void)? = nil,
        onStreamingSnapshot: (@Sendable (ChatStreamingSnapshot) -> Void)? = nil
    ) async throws -> SendMessageResult {
        try await withConversationMetrics(conversationId: conversationId) {
            try await self.sendFusionMessageMeasured(
                conversationId: conversationId,
                text: text,
                attachments: attachments,
                settingsOverride: settingsOverride,
                onFusionProgress: onFusionProgress,
                onStreamEvent: onStreamEvent,
                onStreamingSnapshot: onStreamingSnapshot
            )
        }
    }

    private func sendFusionMessageMeasured(
        conversationId: Int64,
        text: String,
        attachments: [String] = [],
        settingsOverride: AppSettings?,
        onFusionProgress: (@Sendable (FusionProgressSnapshot) -> Void)? = nil,
        onStreamEvent: (@Sendable (ProviderStreamEvent) -> Void)? = nil,
        onStreamingSnapshot: (@Sendable (ChatStreamingSnapshot) -> Void)? = nil
    ) async throws -> SendMessageResult {
        let bgGuard = BackgroundTaskGuard()
        bgGuard.begin(name: "YamabikoChatFusion")
        defer { bgGuard.end() }

        let settings = try settingsOverride ?? self.settings.load()
        guard settings.isFusionModeEnabled else {
            throw ProviderClientError.parseFailure(L10n.text("Fusion モードが有効ではありません。"))
        }
        guard var conversation = try conversations.fetchConversation(id: conversationId) else {
            throw ProviderClientError.parseFailure("Conversation not found")
        }
        guard !conversation.isSecret || attachments.isEmpty else {
            throw ProviderClientError.parseFailure(
                L10n.text("シークレットチャットでは添付ファイルを送信できません。")
            )
        }
        let isFirstMessage = try conversations.isConversationEmpty(conversationId: conversationId)
        let normalizedAttachments = attachments.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        let allowWebSearchOverride: Bool? = settings.clientWebSearchToolEnabled ? nil : false
        let fusionRequest: FusionRequest
        do {
            fusionRequest = try FusionPresetLoader.buildRequest(
                userPrompt: text,
                systemPrompt: conversation.systemPrompt,
                allowWebSearchOverride: allowWebSearchOverride,
                customPresetJSON: settings.fusionCustomPresetJSON
            )
        } catch {
            DiagnosticsLogger.log("Fusion preset load failed", category: .fusion, error: error)
            throw error
        }

        var history = try conversations.fetchProviderHistory(conversationId: conversationId)
            .flatMap(\.providerMessages)
        history.append(
            ProviderRequestMessage(role: "user", content: text, attachments: normalizedAttachments)
        )

        let userMessageId = try conversations.insertMessage(
            ChatMessage(
                conversationId: conversationId,
                role: "user",
                text: text,
                attachmentsJSON: encodeArray(normalizedAttachments)
            )
        )
        try updateConversationTitleIfNeeded(
            conversation: &conversation,
            firstPrompt: text,
            isFirstMessage: isFirstMessage
        )

        let context = FusionContext(
            fusionDepth: 0,
            debugMode: settings.fusionDebugModeEnabled,
            logPrompts: !conversation.isSecret && settings.fusionLogPromptsEnabled,
            conversationId: conversationId,
            clientToolsAllowed: !conversation.isSecret
        )

        let judgeOutcome = try await fusionService.runThroughJudge(
            request: fusionRequest,
            context: context,
            conversationHistory: history,
            userAttachments: normalizedAttachments,
            onProgress: onFusionProgress
        )

        for usage in judgeOutcome.panelTokenUsages {
            await recordTokenUsageIfAvailable(
                provider: usage.provider,
                model: usage.model,
                usage: usage.usage,
                conversationId: conversationId,
                requestType: usage.requestType
            )
        }
        if let judgeUsage = judgeOutcome.judgeTokenUsage {
            await recordTokenUsageIfAvailable(
                provider: judgeUsage.provider,
                model: judgeUsage.model,
                usage: judgeUsage.usage,
                conversationId: conversationId,
                requestType: "fusion_judge"
            )
        }

        let assistantMessageId = try conversations.insertMessage(
            ChatMessage(
                conversationId: conversationId,
                role: "model",
                text: "",
                fusionTraceId: judgeOutcome.trace.requestId
            )
        )

        let synthPanelChips = judgeOutcome.trace.panelResults.map { result in
            FusionPanelChipStatus(
                modelId: result.modelId,
                provider: result.provider,
                state: result.success ? .succeeded : .failed
            )
        }
        onFusionProgress?(
            FusionProgressSnapshot.phaseOnly(.synthesizer, panels: synthPanelChips)
        )

        let synthStarted = Date()
        let stream = try await providers.stream(
            request: judgeOutcome.synthesisRequest,
            providerID: judgeOutcome.synthesizerModel.provider
        )
        let session = try await ChatStreamSession.run(
            stream: stream,
            conversations: conversations,
            kind: .message(messageId: assistantMessageId),
            onStreamEvent: onStreamEvent,
            onStreamingSnapshot: onStreamingSnapshot
        )
        guard let finalText = session.text.trimmedNonEmpty else {
            throw ProviderClientError.parseFailure(
                L10n.text("Fusion synthesizer returned no answer text.")
            )
        }
        let synthUsage = session.usage
        let latencyMs = Int64(Date().timeIntervalSince(synthStarted) * 1000)
        let cost = await pricingRepository.estimateCostUsd(
            provider: judgeOutcome.synthesizerModel.provider,
            model: judgeOutcome.synthesizerModel.modelId,
            inputTokens: synthUsage?.inputTokens ?? 0,
            outputTokens: synthUsage?.outputTokens ?? 0,
            cachedInputTokens: synthUsage?.cachedInputTokens,
            cacheCreationInputTokens: synthUsage?.cacheCreationInputTokens,
            reasoningTokens: synthUsage?.reasoningTokens
        )
        let synthesisResult = SynthesisPhaseResult(
            modelId: judgeOutcome.synthesizerModel.modelId,
            provider: judgeOutcome.synthesizerModel.provider.uppercased(),
            success: true,
            content: finalText,
            latencyMs: latencyMs,
            inputTokens: synthUsage?.inputTokens,
            outputTokens: synthUsage?.outputTokens,
            cost: cost,
            error: nil,
            piExecution: session.toolActivity?.piExecution
        )

        await recordTokenUsageIfAvailable(
            provider: judgeOutcome.synthesizerModel.provider,
            model: judgeOutcome.synthesizerModel.modelId,
            usage: synthUsage,
            usageSamples: session.usageSamples,
            conversationId: conversationId,
            requestType: "fusion_synth"
        )

        let finalTrace = fusionOrchestrator.finalizeTrace(
            trace: judgeOutcome.trace,
            synthesisResult: synthesisResult,
            finalAnswer: finalText,
            logPrompts: context.logPrompts
        )
        try fusionTraceStore.save(trace: finalTrace, conversationId: conversationId)

        return SendMessageResult(
            userMessageId: userMessageId,
            assistantMessageId: assistantMessageId,
            response: ProviderResponse(
                text: finalText,
                reasoningSummary: nil,
                raw: nil,
                usage: synthUsage,
                toolCalls: []
            )
        )
    }

    func fetchFusionTrace(id: String) throws -> FusionTrace? {
        try fusionTraceStore.fetch(id: id)
    }

    func sendUserMessageOnly(
        conversationId: Int64,
        text: String,
        attachments: [String] = []
    ) throws {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAttachments = attachments.filter {
            !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !normalized.isEmpty || !normalizedAttachments.isEmpty else { return }
        guard var conversation = try conversations.fetchConversation(id: conversationId) else {
            throw ProviderClientError.parseFailure("Conversation not found")
        }
        let isFirstMessage = try conversations.isConversationEmpty(conversationId: conversationId)
        _ = try conversations.insertMessage(
            ChatMessage(
                conversationId: conversationId,
                role: "user",
                text: normalized,
                attachmentsJSON: encodeArray(normalizedAttachments)
            )
        )
        try updateConversationTitleIfNeeded(
            conversation: &conversation,
            firstPrompt: normalized.isEmpty ? normalizedAttachments.first ?? "" : normalized,
            isFirstMessage: isFirstMessage
        )
    }

    // MARK: - Shortcuts

    func runShortcut(
        prompt: String,
        provider: String,
        model: String,
        systemPromptOverride: String? = nil,
        saveToNewConversation: Bool
    ) async throws -> ShortcutRunResult {
        let bgGuard = BackgroundTaskGuard()
        bgGuard.begin(name: "YamabikoChatShortcut")
        defer { bgGuard.end() }

        let normalizedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedPrompt.isEmpty else {
            let error = ProviderClientError.parseFailure(L10n.text("Shortcuts: プロンプトを入力してください。"))
            DiagnosticsLogger.log("Shortcut rejected empty prompt", category: .chat, error: error)
            throw error
        }

        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedModel.isEmpty else {
            let error = ProviderClientError.parseFailure(L10n.text("Shortcuts: モデル ID を入力してください。"))
            DiagnosticsLogger.log("Shortcut rejected empty model", category: .chat, error: error)
            throw error
        }

        let normalizedProvider = try validateShortcutProvider(provider)
        let resolvedProvider = normalizedProvider

        let settings = try self.settings.load()
        let trimmedOverride = systemPromptOverride?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedSystemPrompt: String?
        if let trimmedOverride, !trimmedOverride.isEmpty {
            resolvedSystemPrompt = trimmedOverride
        } else {
            resolvedSystemPrompt = settings.effectiveSystemPrompt()
        }

        let request = try await buildSingleTurnRequest(
            model: normalizedModel,
            text: normalizedPrompt,
            systemPrompt: resolvedSystemPrompt,
            provider: normalizedProvider,
            settings: settings,
            stream: false
        )

        if saveToNewConversation {
            _ = try settingsForNewConversation()
            let conversationId = try conversations.createConversation(
                title: "New Chat",
                model: normalizedModel,
                provider: normalizedProvider,
                systemPrompt: resolvedSystemPrompt
            )
            guard var conversation = try conversations.fetchConversation(id: conversationId) else {
                throw ProviderClientError.parseFailure("Conversation not found")
            }

            let userMessageId = try conversations.insertMessage(
                ChatMessage(
                    conversationId: conversationId,
                    role: "user",
                    text: normalizedPrompt
                )
            )
            try updateConversationTitleIfNeeded(
                conversation: &conversation,
                firstPrompt: normalizedPrompt,
                isFirstMessage: true
            )

            let assistantMessageId = try conversations.insertMessage(
                ChatMessage(
                    conversationId: conversationId,
                    role: "model",
                    text: ""
                )
            )

            do {
                let response = try await withConversationMetrics(conversationId: conversationId) {
                    try await self.runToolCallingTurn(
                        request: request,
                        provider: resolvedProvider,
                        conversationId: conversationId,
                        persistenceKind: .message(messageId: assistantMessageId),
                        streamEnabled: false,
                        persistResults: true,
                        onStreamEvent: nil,
                        onStreamingSnapshot: nil
                    )
                }
                await recordTokenUsageIfAvailable(
                    provider: normalizedProvider,
                    model: normalizedModel,
                    usage: response.usage,
                    usageSamples: response.usageSamples,
                    conversationId: conversationId,
                    requestType: "shortcut"
                )
                return ShortcutRunResult(
                    text: response.text,
                    conversationId: conversationId,
                    userMessageId: userMessageId,
                    assistantMessageId: assistantMessageId
                )
            } catch {
                DiagnosticsLogger.log(
                    "Shortcut save run failed",
                    category: .chat,
                    metadata: [
                        "provider": normalizedProvider,
                        "model": normalizedModel,
                        "conversationId": String(conversationId)
                    ],
                    error: error
                )
                throw error
            }
        }

        do {
            let response = try await runToolCallingTurn(
                request: request,
                provider: resolvedProvider,
                conversationId: 0,
                persistenceKind: .message(messageId: -1),
                streamEnabled: false,
                persistResults: false,
                onStreamEvent: nil,
                onStreamingSnapshot: nil
            )
            return ShortcutRunResult(text: response.text)
        } catch {
            DiagnosticsLogger.log(
                "Shortcut run failed",
                category: .chat,
                metadata: [
                    "provider": normalizedProvider,
                    "model": normalizedModel
                ],
                error: error
            )
            throw error
        }
    }

    func prepareAutoConversationSeedMessage(conversationId: Int64, text: String) throws {
        try sendUserMessageOnly(conversationId: conversationId, text: text)
    }

    @discardableResult
    func runAutoConversation(
        conversationId: Int64,
        initialMessage: String,
        progress: @escaping @Sendable (_ turn: Int, _ speaker: String, _ text: String) -> Void
    ) async throws -> Int64 {
        let autoConversationId = try createAutoConversation(
            conversationId: conversationId,
            initialMessage: initialMessage
        )
        try await resumeAutoConversation(autoConversationId: autoConversationId, progress: progress)
        return autoConversationId
    }

    func createAutoConversation(
        conversationId: Int64,
        initialMessage: String
    ) throws -> Int64 {
        if try conversations.fetchConversation(id: conversationId)?.isSecret == true {
            throw ProviderClientError.parseFailure(
                L10n.text("シークレットチャットでは自動会話を利用できません。")
            )
        }
        let normalizedInitialMessage = initialMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentSettings = try settings.load()
        let config = AutoConversationConfig(
            title: L10n.format("自動会話: %@", String(normalizedInitialMessage.prefix(20))),
            modelA: currentSettings.autoModelA,
            modelB: currentSettings.autoModelB,
            providerA: currentSettings.autoProviderA,
            providerB: currentSettings.autoProviderB,
            systemPromptA: currentSettings.autoSystemPromptA,
            systemPromptB: currentSettings.autoSystemPromptB,
            maxTurns: max(0, currentSettings.autoMaxTurns),
            endSignal: "[END]"
        )

        let autoConversationId = try conversations.createAutoConversation(
            config: config,
            boundChatConversationId: conversationId
        )

        _ = try conversations.insertAutoConversationMessage(
            AutoConversationMessage(
                autoConversationId: autoConversationId,
                speakerModel: .user,
                content: normalizedInitialMessage,
                turnNumber: 0
            )
        )
        return autoConversationId
    }

    func resumeAutoConversation(
        autoConversationId: Int64,
        progress: @escaping @Sendable (_ turn: Int, _ speaker: String, _ text: String) -> Void
    ) async throws {
        let bgGuard = BackgroundTaskGuard()
        bgGuard.begin(name: "YamabikoChatAutoConversation")
        defer { bgGuard.end() }

        guard var conversation = try conversations.fetchAutoConversation(id: autoConversationId) else {
            throw ProviderClientError.parseFailure("Auto conversation not found")
        }
        guard conversation.status != .ended else { return }
        if conversation.status == .paused {
            conversation.status = .active
            conversation.endReason = nil
            try conversations.updateAutoConversation(conversation)
        }
        guard conversation.status == .active else { return }

        do {
            try await runAutoConversationLoop(autoConversationId: autoConversationId, progress: progress)
        } catch is CancellationError {
            // pause/stop is handled by explicit status updates from caller
        }
    }

    func pauseAutoConversation(autoConversationId: Int64) throws {
        guard var conversation = try conversations.fetchAutoConversation(id: autoConversationId) else { return }
        guard conversation.status == .active else { return }
        conversation.status = .paused
        try conversations.updateAutoConversation(conversation)
    }

    func stopAutoConversation(
        autoConversationId: Int64,
        reason: String = AutoConversationEndReason.userStop
    ) throws {
        try markAutoConversationEnded(autoConversationId: autoConversationId, reason: reason)
    }

    func autoConversation(id: Int64) throws -> AutoConversation? {
        try conversations.fetchAutoConversation(id: id)
    }

    func observeAutoConversationMessages(autoConversationId: Int64) -> AnyPublisher<[AutoConversationMessage], Never> {
        conversations.observeAutoConversationMessages(autoConversationId: autoConversationId)
    }

    func observeTokenUsageTotals(sinceEpochMs: Int64) -> AnyPublisher<TokenUsageTotals, Never> {
        conversations.observeTokenUsageTotals(sinceEpochMs: sinceEpochMs)
    }

    func observeLatestTokenUsage(conversationId: Int64) -> AnyPublisher<TokenUsageRecord?, Never> {
        conversations.observeLatestTokenUsage(conversationId: conversationId)
    }

    func observeTokenUsageByModel(
        sinceEpochMs: Int64,
        limit: Int
    ) -> AnyPublisher<[TokenUsageByModel], Never> {
        conversations.observeTokenUsageByModel(sinceEpochMs: sinceEpochMs, limit: limit)
    }

    func observeTokenUsageDaily(sinceEpochMs: Int64) -> AnyPublisher<[TokenUsageDailyPoint], Never> {
        conversations.observeTokenUsageDaily(sinceEpochMs: sinceEpochMs)
    }

    func searchConversations(query: String) throws -> [ConversationListEntry] {
        try conversations.searchConversations(query: query)
    }

    // MARK: - Auth APIs

    func codexAuthStatePublisher() -> AnyPublisher<CodexAuthState, Never> {
        codexAuthRepository.state
    }

    func loginCodexAuthWithBrowser() async -> Result<CodexAuthState, Error> {
        await codexAuthRepository.loginWithBrowser()
    }

    func logoutCodexAuth() async -> Result<CodexAuthState, Error> {
        await codexAuthRepository.logout()
    }

    func refreshCodexAuth(force: Bool = false) async -> Result<CodexAuthState, Error> {
        await codexAuthRepository.refreshIfNeeded(force: force)
    }

    func retrieveCodexAuthUsage() async -> Result<CodexUsageStatus, Error> {
        await codexAuthRepository.retrieveUsageStatus()
    }

    func retrieveOpenCodeGoUsage(apiKey: String) async -> Result<OpenCodeGoUsageStatus, Error> {
        await openCodeGoUsageRepository.retrieveUsage(apiKey: apiKey)
    }

    func superGrokAuthStatePublisher() -> AnyPublisher<SuperGrokAuthState, Never> {
        superGrokAuthRepository.state
    }

    func loginSuperGrokWithBrowser() async -> Result<SuperGrokAuthState, Error> {
        await superGrokAuthRepository.loginWithBrowser()
    }

    func loginSuperGrokWithDeviceCode() async -> Result<SuperGrokAuthState, Error> {
        await superGrokAuthRepository.loginWithDeviceCode()
    }

    func logoutSuperGrok() async -> Result<SuperGrokAuthState, Error> {
        await superGrokAuthRepository.logout()
    }

    func refreshSuperGrok(force: Bool = false) async -> Result<SuperGrokAuthState, Error> {
        await superGrokAuthRepository.refreshIfNeeded(force: force)
    }

    func saveOpenAiCompatApiKey(name: String, apiKey: String?) -> Bool {
        do {
            try credentialStore.setOpenAICompatAPIKey(name: name, value: apiKey)
            return true
        } catch {
            return false
        }
    }

    func peekOpenAiCompatApiKey(name: String) -> String? {
        try? credentialStore.openAICompatAPIKey(name: name)
    }

    func hasOpenAiCompatApiKey(name: String?) -> Bool {
        guard let name = name, let value = try? credentialStore.openAICompatAPIKey(name: name) else { return false }
        return !value.isEmpty
    }

    func saveGeminiApiKey(name: String, apiKey: String?) -> Bool {
        do {
            try credentialStore.setGeminiAPIKey(name: name, value: apiKey)
            return true
        } catch {
            return false
        }
    }

    func peekGeminiApiKey(name: String) -> String? {
        try? credentialStore.geminiAPIKey(name: name)
    }

    func removeGeminiApiKey(name: String) {
        try? credentialStore.clearGeminiAPIKey(name: name)
    }

    func clearOpenAiCompatApiKey(name: String) {
        try? credentialStore.clearOpenAICompatAPIKey(name: name)
    }

    // MARK: - Model APIs

    func getOpenRouterModels(forceRefresh: Bool = false) async -> [SimpleModel] {
        await modelService.getAvailableModels(forceRefresh: forceRefresh)
    }

    func getOpenRouterModelsPublisher() -> AnyPublisher<[SimpleModel], Never> {
        modelService.modelsPublisher
    }

    func getOpenRouterModelsLoadingPublisher() -> AnyPublisher<Bool, Never> {
        modelService.loadingPublisher
    }

    func getOpenRouterModelsErrorPublisher() -> AnyPublisher<String?, Never> {
        modelService.errorPublisher
    }

    func searchOpenRouterModels(query: String) -> [SimpleModel] {
        modelService.searchModels(query: query)
    }

    func getOpenRouterModelsByProvider(_ provider: String) -> [SimpleModel] {
        modelService.getModelsByProvider(provider)
    }

    func getFreeOpenRouterModels() -> [SimpleModel] {
        modelService.getFreeModels()
    }

    func getOpenRouterModelById(_ modelId: String) -> SimpleModel? {
        modelService.getModelById(modelId)
    }

    func clearOpenRouterModelsCache() {
        modelService.clearCache()
    }

    func getAvailableProvidersForModel(_ modelId: String) async -> [String] {
        await modelService.getAvailableProviders(for: modelId)
    }

    func getAvailableQuantizationsForModel(_ modelId: String) async -> [String] {
        await modelService.getAvailableQuantizations(for: modelId)
    }

    func getModelEndpoints(_ modelId: String) async -> [ModelEndpoint] {
        await modelService.getModelEndpoints(modelId: modelId)
    }

    func getOpenRouterModelEndpointOptions(
        _ modelId: String,
        forceRefresh: Bool = false
    ) async throws -> OpenRouterModelEndpointOptions {
        try await modelService.getModelEndpointOptions(
            modelId: modelId,
            forceRefresh: forceRefresh
        )
    }

    func resolveModelSupportsVision(provider: String, model: String) async -> Bool {
        await pricingRepository.modelSupportsVision(provider: provider, model: model)
    }

    func resolveCanAttachImages(
        settings: AppSettings,
        conversationProvider: String,
        conversationModel: String
    ) async -> Bool {
        if settings.isDualModeEnabled {
            async let modelA = pricingRepository.modelSupportsVision(
                provider: settings.dualProviderA,
                model: settings.dualModelA
            )
            async let modelB = pricingRepository.modelSupportsVision(
                provider: settings.dualProviderB,
                model: settings.dualModelB
            )
            let (supportsA, supportsB) = await (modelA, modelB)
            return supportsA && supportsB
        }
        if settings.isAutoConversationEnabled {
            async let modelA = pricingRepository.modelSupportsVision(
                provider: settings.autoProviderA,
                model: settings.autoModelA
            )
            async let modelB = pricingRepository.modelSupportsVision(
                provider: settings.autoProviderB,
                model: settings.autoModelB
            )
            let (supportsA, supportsB) = await (modelA, modelB)
            return supportsA && supportsB
        }
        if settings.isFusionModeEnabled {
            if let preset = try? FusionPresetLoader.resolveDefinition(
                customPresetJSON: settings.fusionCustomPresetJSON
            ) {
                var allSupport = true
                for panel in preset.panelModels {
                    let supports = await pricingRepository.modelSupportsVision(
                        provider: panel.provider,
                        model: panel.modelId
                    )
                    if !supports {
                        allSupport = false
                        break
                    }
                }
                return allSupport
            }
        }
        return await pricingRepository.modelSupportsVision(
            provider: conversationProvider,
            model: conversationModel
        )
    }

    func getProvidersDirectory() async -> ProviderDirectory {
        await modelService.getProvidersDirectory()
    }

    // MARK: - Helpers

    private func visionMetadataFlag(provider: String, model: String) async -> String {
        let supports = await pricingRepository.modelSupportsVision(provider: provider, model: model)
        return supports ? "true" : "false"
    }

    private enum AutoSpeaker {
        case a
        case b

        var modelLabel: String {
            switch self {
            case .a:
                return "AI-A"
            case .b:
                return "AI-B"
            }
        }

        var modelCode: AutoConversationSpeakerModel {
            switch self {
            case .a:
                return .a
            case .b:
                return .b
            }
        }

        var context: AppSettings.ReasoningContext {
            switch self {
            case .a:
                return .autoA
            case .b:
                return .autoB
            }
        }
    }

    private static let autoConversationTurnDelayNs: UInt64 = 2_000_000_000
    private static let autoConversationUnlimitedTurnSafetyLimit = 100
    private static let autoConversationSessionDurationLimitMs: Int64 = 30 * 60 * 1_000
    private static let autoConversationEndRegexes: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: "(?:会話|議論|討論|対話)(?:を)?(?:(?:ここ|これ|以上)で)?終(?:了|わ)り(?:に)?(?:いたします|ます|ましょう|とします)", options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: "これ(?:にて|で)(?:終(?:了|わ)り|終了)とさせていただきます", options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: "(?:ここ|これ|以上|本件)(?:で|にて)(?:終(?:了|わ)り|終了)(?:とします|です)", options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: "\\bend of (?:this )?(?:conversation|discussion)\\b", options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: "\\bthis concludes (?:our )?(?:conversation|discussion)\\b", options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: "\\blet'?s end (?:the )?(?:conversation|discussion)\\b", options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: "\\bconversation (?:has )?(?:ended|is over)\\b", options: [.caseInsensitive])
    ]

    private func runAutoConversationLoop(
        autoConversationId: Int64,
        progress: @escaping @Sendable (_ turn: Int, _ speaker: String, _ text: String) -> Void
    ) async throws {
        while true {
            try Task.checkCancellation()

            guard var autoConversation = try conversations.fetchAutoConversation(id: autoConversationId) else {
                throw ProviderClientError.parseFailure("Auto conversation not found")
            }
            guard autoConversation.status == .active else {
                return
            }

            let messages = try conversations.fetchAutoConversationMessages(autoConversationId: autoConversationId)
            let (nextTurn, speaker) = determineAutoConversationNextStep(messages: messages)

            let nowMs = Int64(Date().timeIntervalSince1970 * 1_000)
            if autoConversation.maxTurns == 0,
               nextTurn > Self.autoConversationUnlimitedTurnSafetyLimit ||
                nowMs - autoConversation.createdAtMs >= Self.autoConversationSessionDurationLimitMs {
                try appendAutoConversationSystemMessage(
                    autoConversation: autoConversation,
                    text: L10n.text("**[SYSTEM]**\n\n安全上限（100ターンまたは30分）に達したため、自動会話を停止しました。")
                )
                try markAutoConversationEnded(
                    autoConversationId: autoConversationId,
                    reason: AutoConversationEndReason.safetyLimit
                )
                return
            }

            if autoConversation.maxTurns > 0, nextTurn > autoConversation.maxTurns {
                try appendAutoConversationSystemMessage(
                    autoConversation: autoConversation,
                    text: L10n.format(
                        "**[SYSTEM]**\n\n🎯 自動会話が完了しました！\n\n• 実行ターン数: %d/%dターン\n• 参加モデル: %@ vs %@\n• 終了理由: 最大ターン数に達したため",
                        max(0, nextTurn - 1),
                        autoConversation.maxTurns,
                        autoConversation.modelA,
                        autoConversation.modelB
                    )
                )
                try markAutoConversationEnded(
                    autoConversationId: autoConversationId,
                    reason: AutoConversationEndReason.maxTurns
                )
                return
            }

            let turnModel: String
            let turnProvider: String
            let turnPrompt: String
            switch speaker {
            case .a:
                turnModel = autoConversation.modelA
                turnProvider = autoConversation.providerA
                turnPrompt = autoConversation.systemPromptA
            case .b:
                turnModel = autoConversation.modelB
                turnProvider = autoConversation.providerB
                turnPrompt = autoConversation.systemPromptB
            }

            let history = buildAutoConversationHistory(messages: messages, speaker: speaker)
            let currentSettings = try settings.load()
            let request = try await buildSingleTurnRequest(
                model: turnModel,
                text: "",
                systemPrompt: turnPrompt,
                provider: turnProvider,
                settings: currentSettings,
                stream: false,
                messages: history,
                context: speaker.context,
                promptCacheKey: "auto-conversation-\(autoConversationId)-\(speaker.modelCode)"
            )

            let response: ProviderResponse
            do {
                if let chatConversationId = autoConversation.boundChatConversationId {
                    response = try await withConversationMetrics(conversationId: chatConversationId) {
                        try await self.generateNonStreamingResponse(
                            request: request,
                            provider: turnProvider
                        )
                    }
                } else {
                    response = try await generateNonStreamingResponse(
                        request: request,
                        provider: turnProvider
                    )
                }
                await recordTokenUsageIfAvailable(
                    provider: turnProvider,
                    model: turnModel,
                    usage: response.usage,
                    usageSamples: response.usageSamples,
                    conversationId: autoConversation.boundChatConversationId,
                    requestType: "auto_turn"
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try markAutoConversationEnded(
                    autoConversationId: autoConversationId,
                    reason: AutoConversationEndReason.apiError
                )
                throw error
            }

            let responseText = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            let reasoning = response.reasoningSummary?.trimmingCharacters(in: .whitespacesAndNewlines)
            if responseText.isEmpty, (reasoning ?? "").isEmpty {
                try markAutoConversationEnded(
                    autoConversationId: autoConversationId,
                    reason: AutoConversationEndReason.error
                )
                throw ProviderClientError.parseFailure(L10n.text("自動会話で空の応答を受信しました。"))
            }

            guard let latestConversation = try conversations.fetchAutoConversation(id: autoConversationId),
                  latestConversation.status == .active else {
                return
            }
            autoConversation = latestConversation

            let hasEndSignal = containsAutoConversationEndSignal(
                text: responseText,
                configuredEndSignal: autoConversation.endSignal
            )
            let piExecutionJSON = try response.piExecution.map {
                String(decoding: try JSONEncoder().encode($0), as: UTF8.self)
            }
            _ = try conversations.insertAutoConversationMessage(
                AutoConversationMessage(
                    autoConversationId: autoConversationId,
                    speakerModel: speaker.modelCode,
                    content: responseText,
                    reasoning: reasoning?.isEmpty == true ? nil : reasoning,
                    turnNumber: nextTurn,
                    isEndSignal: hasEndSignal,
                    piExecutionJSON: piExecutionJSON
                )
            )

            autoConversation.currentTurn = nextTurn
            autoConversation.status = .active
            autoConversation.endReason = nil
            try conversations.updateAutoConversation(autoConversation)

            let display = formatAutoConversationDisplay(content: responseText, reasoning: reasoning)
            if let chatConversationId = autoConversation.boundChatConversationId {
                _ = try conversations.insertMessage(
                    ChatMessage(
                        conversationId: chatConversationId,
                        role: "model",
                        text: "**[\(speaker.modelLabel)]**\n\n\(display)"
                    )
                )
            }
            progress(nextTurn, speaker.modelLabel, display)

            if hasEndSignal {
                try appendAutoConversationSystemMessage(
                    autoConversation: autoConversation,
                    text: L10n.format(
                        "**[SYSTEM]**\n\n🏁 自動会話が終了しました\n\n• 実行ターン数: %d/%@ターン\n• 参加モデル: %@ vs %@\n• 終了理由: AIモデルが会話終了を宣言",
                        nextTurn,
                        autoConversation.maxTurns > 0
                            ? String(autoConversation.maxTurns)
                            : L10n.text("無制限"),
                        autoConversation.modelA,
                        autoConversation.modelB
                    )
                )
                try markAutoConversationEnded(
                    autoConversationId: autoConversationId,
                    reason: AutoConversationEndReason.endSignal
                )
                return
            }

            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: Self.autoConversationTurnDelayNs)
        }
    }

    private func determineAutoConversationNextStep(messages: [AutoConversationMessage]) -> (turn: Int, speaker: AutoSpeaker) {
        let ordered = messages.sorted {
            if $0.turnNumber == $1.turnNumber {
                return ($0.id ?? 0) < ($1.id ?? 0)
            }
            return $0.turnNumber < $1.turnNumber
        }
        let lastModelMessage = ordered.last(where: {
            $0.speakerModel == .a || $0.speakerModel == .b
        })

        guard let lastModelMessage else {
            return (1, .a)
        }
        let nextSpeaker: AutoSpeaker = (lastModelMessage.speakerModel == .a) ? .b : .a
        return (lastModelMessage.turnNumber + 1, nextSpeaker)
    }

    private func buildAutoConversationHistory(
        messages: [AutoConversationMessage],
        speaker: AutoSpeaker
    ) -> [ProviderRequestMessage] {
        let ordered = messages.sorted {
            if $0.turnNumber == $1.turnNumber {
                return ($0.id ?? 0) < ($1.id ?? 0)
            }
            return $0.turnNumber < $1.turnNumber
        }
        return ordered.compactMap { message in
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            switch message.speakerModel {
            case .user:
                return ProviderRequestMessage(role: "user", content: content)
            case .a, .b:
                let role: String
                switch (speaker, message.speakerModel) {
                case (.a, .a), (.b, .b):
                    role = "assistant"
                default:
                    role = "user"
                }
                return ProviderRequestMessage(role: role, content: content)
            }
        }
    }

    private func containsAutoConversationEndSignal(text: String, configuredEndSignal: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        let endSignal = configuredEndSignal.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetSignal = endSignal.isEmpty ? "[END]" : endSignal
        if normalized.range(of: targetSignal, options: [.caseInsensitive, .widthInsensitive]) != nil {
            return true
        }

        let range = NSRange(location: 0, length: (normalized as NSString).length)
        return Self.autoConversationEndRegexes.contains { regex in
            regex.firstMatch(in: normalized, options: [], range: range) != nil
        }
    }

    private func appendAutoConversationSystemMessage(
        autoConversation: AutoConversation,
        text: String
    ) throws {
        guard let chatConversationId = autoConversation.boundChatConversationId else { return }
        _ = try conversations.insertMessage(
            ChatMessage(
                conversationId: chatConversationId,
                role: "model",
                text: text
            )
        )
    }

    private func markAutoConversationEnded(autoConversationId: Int64, reason: String) throws {
        guard var conversation = try conversations.fetchAutoConversation(id: autoConversationId) else { return }
        conversation.status = .ended
        conversation.endReason = reason
        conversation.boundChatConversationId = nil
        try conversations.updateAutoConversation(conversation)
    }

    private func recordTokenUsageIfAvailable(
        provider: String,
        model: String,
        usage: ProviderUsage?,
        usageSamples: [ProviderUsage]? = nil,
        conversationId: Int64?,
        requestType: String
    ) async {
        let samples: [ProviderUsage]
        if let usageSamples, !usageSamples.isEmpty {
            samples = usageSamples
        } else if let usage {
            samples = [usage]
        } else {
            return
        }
        for sample in samples {
            await recordSingleTokenUsageIfAvailable(
                provider: provider,
                model: model,
                usage: sample,
                conversationId: conversationId,
                requestType: requestType
            )
        }
    }

    private func recordSingleTokenUsageIfAvailable(
        provider: String,
        model: String,
        usage: ProviderUsage,
        conversationId: Int64?,
        requestType: String
    ) async {
        guard let normalized = usage
            .normalizedNonEmpty()
        else { return }
        let resolvedInput = max(0, normalized.inputTokens ?? 0)
        let resolvedOutput = max(0, normalized.outputTokens ?? 0)
        let resolvedCached = max(0, normalized.cachedInputTokens ?? 0)
        let resolvedCacheCreation = max(0, normalized.cacheCreationInputTokens ?? 0)
        let resolvedTotal = max(
            max(0, normalized.totalTokens ?? 0),
            resolvedInput + resolvedCached + resolvedCacheCreation + resolvedOutput
        )

        let costUsd = await pricingRepository.estimateCostUsd(
            provider: provider,
            model: model,
            inputTokens: resolvedInput,
            outputTokens: resolvedOutput,
            cachedInputTokens: normalized.cachedInputTokens,
            cacheCreationInputTokens: normalized.cacheCreationInputTokens,
            reasoningTokens: normalized.reasoningTokens
        )

        do {
            try conversations.insertTokenUsage(
                TokenUsageRecord(
                    provider: provider.uppercased(),
                    model: model.trimmingCharacters(in: .whitespacesAndNewlines).ifBlank("unknown"),
                    requestType: requestType,
                    conversationId: conversationId,
                    inputTokens: resolvedInput,
                    outputTokens: resolvedOutput,
                    totalTokens: resolvedTotal,
                    reasoningTokens: normalized.reasoningTokens,
                    cachedInputTokens: normalized.cachedInputTokens,
                    cacheCreationInputTokens: normalized.cacheCreationInputTokens,
                    contextTokens: normalized.contextTokens,
                    contextWindow: normalized.contextWindow,
                    costUsd: costUsd
                )
            )
        } catch {
            DiagnosticsLogger.log(
                "Token usage record failed",
                category: .chat,
                metadata: [
                    "provider": provider.uppercased(),
                    "model": model,
                    "requestType": requestType
                ],
                error: error
            )
        }
    }

    private func withConversationMetrics<T>(
        conversationId: Int64,
        operation: () async throws -> T
    ) async rethrows -> T {
        let context = ProviderMetricsContext(
            conversationId: conversationId,
            turnId: UUID().uuidString,
            recorder: { [conversations] metric in
                do {
                    try conversations.insertExecutionMetric(metric)
                } catch {
                    DiagnosticsLogger.log(
                        "Conversation execution metric persistence failed",
                        category: .chat,
                        metadata: [
                            "conversation": String(metric.conversationId),
                            "turn": metric.turnId,
                            "kind": metric.kind.rawValue
                        ],
                        error: error
                    )
                }
            }
        )
        return try await ProviderMetricsContext.$current.withValue(context) {
            try await operation()
        }
    }

    private func buildSingleTurnRequest(
        model: String,
        text: String,
        systemPrompt: String?,
        provider: String,
        settings: AppSettings,
        stream: Bool? = nil,
        messages: [ProviderRequestMessage]? = nil,
        context: AppSettings.ReasoningContext = .default,
        promptCacheKey: String? = nil,
        clientToolsAllowed: Bool = true
    ) async throws -> ProviderRequest {
        let resolvedSettings = try await requestSettingsResolver.resolve(
            settings: settings,
            provider: provider,
            model: model,
            context: context
        )
        var metadata = resolvedSettings.metadata
        metadata["provider"] = provider
        if let promptCacheKey = promptCacheKey?.trimmingCharacters(in: .whitespacesAndNewlines), !promptCacheKey.isEmpty {
            metadata["promptCacheKey"] = promptCacheKey
            if promptCacheKey.hasPrefix("conversation-") {
                metadata["pythonSessionId"] = String(promptCacheKey.dropFirst("conversation-".count))
                let suffix = promptCacheKey.dropFirst("conversation-".count)
                metadata["editorSessionId"] = String(suffix.split(separator: "-").first ?? suffix[...])
            }
        }
        metadata["supportsVision"] = await visionMetadataFlag(provider: provider, model: model)
        if !clientToolsAllowed {
            metadata["supportsClientTools"] = "false"
        }
        let baseMessages = messages ?? [ProviderRequestMessage(role: "user", content: text)]
        let skillApplication: AgentSkillPromptApplication
        if clientToolsAllowed {
            skillApplication = try applySkillContext(
                messages: baseMessages,
                conversationID: promptCacheKey,
                clientToolsSupported: resolvedSettings.metadata["supportsClientTools"] == "true"
            )
        } else {
            skillApplication = AgentSkillPromptApplication(messages: baseMessages, currentContext: nil)
        }
        return ProviderRequest(
            model: model,
            messages: skillApplication.messages,
            systemPrompt: SystemPromptComposer.composeForAPI(
                systemPrompt,
                enablesAgenticWebSearch: clientToolsAllowed && resolvedSettings.tools.containsWebSearchTool,
                enablesEditorInstructions: clientToolsAllowed && resolvedSettings.tools.containsEditorTool
            ),
            stream: stream ?? settings.isStreamingEnabled,
            tools: clientToolsAllowed ? resolvedSettings.tools : [],
            thinking: resolvedSettings.thinking,
            provider: resolvedSettings.routing,
            metadata: metadata,
            skillContext: skillApplication.currentContext
        )
    }

    private func applySkillContext(
        messages: [ProviderRequestMessage],
        conversationID: String?,
        clientToolsSupported: Bool
    ) throws -> AgentSkillPromptApplication {
        return try AgentSkillPromptComposer.apply(
            repository: skillRepository,
            to: messages,
            conversationID: conversationID,
            providerSupportsTools: clientToolsSupported
        )
    }

    private enum DualHistorySide: Sendable {
        case a
        case b
    }

    private struct DualSideResult {
        var text: String
        var reasoning: String?
        var usage: ProviderUsage?
        var usageSamples: [ProviderUsage]?
        var toolActivity: ToolActivityPayload?
        var error: Error?
    }

    private func generateDualSideResponse(
        request: ProviderRequest,
        provider: String,
        model: String,
        onToolActivity: (@Sendable (ToolActivityEvent) -> Void)? = nil
    ) async -> DualSideResult {
        let activityState = DualToolActivityState()
        do {
            let response = try await generateNonStreamingResponse(
                request: request,
                provider: provider,
                onStreamEvent: { event in
                    switch event {
                    case let .toolActivity(toolEvent):
                        activityState.apply(toolEvent)
                        onToolActivity?(toolEvent)
                    case let .executionSnapshot(execution):
                        activityState.setExecution(execution)
                    case .answerStart, .textDelta, .reasoningDelta, .completed:
                        break
                    }
                }
            )
            var activity = response.toolActivity ?? activityState.snapshot() ?? ToolActivityPayload()
            activity.piExecution = response.piExecution ?? activity.piExecution
            return DualSideResult(
                text: response.text,
                reasoning: response.reasoningSummary,
                usage: response.usage,
                usageSamples: response.usageSamples,
                toolActivity: activity.hasPersistableContent ? activity : nil,
                error: nil
            )
        } catch {
            let failedActivity = activityState.failRunning()
            return DualSideResult(
                text: "",
                reasoning: nil,
                usage: nil,
                usageSamples: nil,
                toolActivity: failedActivity,
                error: error
            )
        }
    }

    private func generateNonStreamingResponse(
        request: ProviderRequest,
        provider: String,
        onStreamEvent: (@Sendable (ProviderStreamEvent) -> Void)? = nil
    ) async throws -> ProviderResponse {
        try await providers.generate(
            request: request,
            providerID: provider,
            onStreamEvent: onStreamEvent
        )
    }

    private static func persistDualToolEvent(
        _ event: ToolActivityEvent,
        side: DualHistorySide,
        rowId: Int64,
        conversationId: Int64,
        conversations: ConversationRepository
    ) throws {
        guard var row = try conversations.fetchDualMessages(conversationId: conversationId)
            .first(where: { $0.id == rowId }) else { return }
        var payload = side == .a ? (row.modelAToolActivity ?? ToolActivityPayload()) :
            (row.modelBToolActivity ?? ToolActivityPayload())
        payload.apply(event)
        if side == .a {
            row.modelAToolActivityJSON = DualChatMessage.encodeToolActivity(payload)
        } else {
            row.modelBToolActivityJSON = DualChatMessage.encodeToolActivity(payload)
        }
        try conversations.updateDualMessage(row)
    }

    private func buildDualHistory(
        conversationId: Int64,
        dualMessages: [DualChatMessage],
        modelSide: DualHistorySide
    ) throws -> [ProviderRequestMessage] {
        var messages: [ProviderRequestMessage] = try conversations
            .fetchProviderHistory(conversationId: conversationId)
            .flatMap(\.providerMessages)

        let sortedDual = dualMessages.sorted {
            if $0.createdAtMs == $1.createdAtMs {
                return ($0.id ?? 0) < ($1.id ?? 0)
            }
            return $0.createdAtMs < $1.createdAtMs
        }
        for dual in sortedDual {
            switch dual.parsedRole {
            case .user:
                let text = dual.userText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty || !dual.attachments.isEmpty {
                    messages.append(
                        ProviderRequestMessage(
                            role: "user",
                            content: text,
                            attachments: dual.attachments
                        )
                    )
                }
            case .dualModel:
                let content = modelSide == .a ? dual.modelAText : dual.modelBText
                let activity = modelSide == .a ? dual.modelAToolActivity : dual.modelBToolActivity
                messages.append(contentsOf: activity?.providerTranscript ?? [])
                let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    messages.append(
                        ProviderRequestMessage(
                            role: "assistant",
                            content: trimmed
                        )
                    )
                }
            case .legacy:
                let userText = dual.userText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !userText.isEmpty {
                    messages.append(
                        ProviderRequestMessage(
                            role: "user",
                            content: userText
                        )
                    )
                }
                let legacyModelText = (modelSide == .a ? dual.modelAText : dual.modelBText)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !legacyModelText.isEmpty {
                    messages.append(
                        ProviderRequestMessage(
                            role: "assistant",
                            content: legacyModelText
                        )
                    )
                }
            }
        }
        return messages
    }

    private func encodeArray(_ values: [String]) -> String {
        guard let data = try? JSONEncoder().encode(values), let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }

    private func decodeArray(_ raw: String) -> [String] {
        guard let data = raw.data(using: .utf8),
              let values = try? JSONDecoder().decode([String].self, from: data) else {
            return []
        }
        return values
    }

    private func updateConversationTitleIfNeeded(
        conversation: inout Conversation,
        firstPrompt: String,
        isFirstMessage: Bool
    ) throws {
        guard isFirstMessage else { return }

        let normalizedCurrentTitle = conversation.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.defaultConversationTitles.contains(normalizedCurrentTitle) else { return }

        guard let nextTitle = firstPrompt.normalizedConversationTitle(maxLength: Self.conversationTitleMaxLength),
              nextTitle != normalizedCurrentTitle
        else {
            return
        }

        conversation.title = nextTitle
        _ = try conversations.upsertConversation(conversation)
    }

    private func buildBranchTitle(baseTitle: String, messageText: String?) -> String {
        let normalizedText = messageText?
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let snippet: String
        if normalizedText.count > Self.branchSnippetMaxLength {
            snippet = String(normalizedText.prefix(Self.branchSnippetMaxLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
        } else {
            snippet = normalizedText
        }

        if baseTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || baseTitle == "New Chat" {
            return snippet.isEmpty
                ? L10n.text("ブランチ")
                : L10n.format("ブランチ: %@", snippet)
        }
        return L10n.format("ブランチ: %@", baseTitle)
    }

    private func settingsForNewConversation() throws -> AppSettings {
        var currentSettings = try settings.load()
        guard currentSettings.isDualModeEnabled || currentSettings.isAutoConversationEnabled else {
            return currentSettings
        }

        currentSettings.isDualModeEnabled = false
        currentSettings.isAutoConversationEnabled = false
        try saveSettings(currentSettings)
        return currentSettings
    }

    private func validateShortcutProvider(_ provider: String) throws -> String {
        let normalized = provider.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard ProviderReference(persistedID: normalized).isModelsDev
            || ProviderCatalog.options.contains(where: { $0.key == normalized }) else {
            let error = ProviderClientError.parseFailure(L10n.text("Shortcuts: 不明なプロバイダです。"))
            DiagnosticsLogger.log(
                "Shortcut rejected unknown provider",
                category: .chat,
                metadata: ["provider": provider],
                error: error
            )
            throw error
        }
        return normalized
    }

    private func resolveSystemPromptForProject(projectId: Int64?, fallbackPrompt: String?) throws -> String? {
        guard let projectId else { return fallbackPrompt }
        let project = try conversations.fetchProject(id: projectId)
        let projectPrompt = project?.instructions?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let projectPrompt, !projectPrompt.isEmpty {
            return projectPrompt
        }
        return fallbackPrompt
    }
}

private final class DualToolActivityState: @unchecked Sendable {
    private let lock = NSLock()
    private var activity = ToolActivityPayload()

    func apply(_ event: ToolActivityEvent) {
        lock.lock()
        activity.apply(event)
        lock.unlock()
    }

    func snapshot() -> ToolActivityPayload? {
        lock.lock()
        let value = activity
        lock.unlock()
        return value.hasPersistableContent ? value : nil
    }

    func setExecution(_ execution: JSONValue) {
        lock.lock()
        activity.piExecution = execution
        lock.unlock()
    }

    func failRunning() -> ToolActivityPayload? {
        lock.lock()
        activity.failRunning(message: L10n.text("ツールの実行が中断されました"))
        let value = activity
        lock.unlock()
        return value.hasPersistableContent ? value : nil
    }
}

private extension String {
    func ifBlank(_ fallback: String) -> String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    func normalizedConversationTitle(maxLength: Int) -> String? {
        let normalized = components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !normalized.isEmpty else { return nil }
        guard maxLength > 0, normalized.count > maxLength else { return normalized }
        return String(normalized.prefix(maxLength))
    }
}
