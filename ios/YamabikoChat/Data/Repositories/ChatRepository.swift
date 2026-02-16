import Foundation
import Combine

struct SendMessageResult {
    var userMessageId: Int64
    var assistantMessageId: Int64
    var response: ProviderResponse
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
    private let codexAuthRepository: CodexAuthRepository
    private let geminiAuthRepository: GeminiAuthRepository

    init(
        conversations: ConversationRepository,
        settings: SettingsRepository,
        providers: ProviderGateway,
        credentialStore: SecureCredentialStore,
        modelService: OpenRouterModelService,
        codexAuthRepository: CodexAuthRepository,
        geminiAuthRepository: GeminiAuthRepository
    ) {
        self.conversations = conversations
        self.settings = settings
        self.providers = providers
        self.credentialStore = credentialStore
        self.modelService = modelService
        self.codexAuthRepository = codexAuthRepository
        self.geminiAuthRepository = geminiAuthRepository
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

    func setSelectedVariant(messageId: Int64, variantIndex: Int) throws {
        try conversations.updateMessageSelectedVariantIndex(messageId: messageId, variantIndex: variantIndex)
    }

    func conversation(id: Int64) throws -> Conversation? {
        try conversations.fetchConversation(id: id)
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
            systemPrompt: currentSettings.systemPrompt
        )
    }

    func createConversation(title: String = "New Chat", projectId: Int64? = nil) throws -> Int64 {
        let currentSettings = try settingsForNewConversation()
        let resolvedPrompt = try resolveSystemPromptForProject(projectId: projectId, fallbackPrompt: currentSettings.systemPrompt)
        return try conversations.createConversation(
            title: title,
            model: currentSettings.currentModel(),
            provider: currentSettings.apiProvider,
            systemPrompt: resolvedPrompt,
            projectId: projectId
        )
    }

    func createSecretConversation(projectId: Int64? = nil) throws -> Int64 {
        let currentSettings = try settingsForNewConversation()
        let resolvedPrompt = try resolveSystemPromptForProject(projectId: projectId, fallbackPrompt: currentSettings.systemPrompt)
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
            throw ProviderClientError.parseFailure("プロジェクト名を入力してください。")
        }
        return try conversations.createProject(title: normalizedTitle, instructions: instructions)
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
        try conversations.deleteConversation(id: id)
    }

    func deleteProject(id: Int64, mode: ProjectDeletionMode) throws {
        switch mode {
        case .projectOnly:
            try conversations.deleteProject(id: id)
        case .withConversations:
            try conversations.deleteProjectWithConversations(id: id)
        }
    }

    func setSecretMode(conversationId: Int64, enabled: Bool) throws {
        guard var conversation = try conversations.fetchConversation(id: conversationId) else {
            throw ProviderClientError.parseFailure("Conversation not found")
        }
        conversation.isSecret = enabled
        _ = try conversations.upsertConversation(conversation)
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
            let previousPrompt = previousSettings.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)

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
        let nextPrompt = currentSettings.systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines)

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

    func sendMessage(
        conversationId: Int64,
        text: String,
        attachments: [String],
        onStreamEvent: (@Sendable (ProviderStreamEvent) -> Void)? = nil
    ) async throws -> SendMessageResult {
        let settings = try self.settings.load()
        guard var conversation = try conversations.fetchConversation(id: conversationId) else {
            throw ProviderClientError.parseFailure("Conversation not found")
        }
        let isFirstMessage = try conversations.isConversationEmpty(conversationId: conversationId)

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

        let request = try buildProviderRequest(
            conversation: conversation,
            settings: settings,
            conversationId: conversationId
        )
        let provider = LLMProvider(rawOrDefault: conversation.apiProvider)

        if settings.isStreamingEnabled {
            return try await streamMessage(
                conversationId: conversationId,
                userMessageId: userMessageId,
                request: request,
                provider: provider,
                onStreamEvent: onStreamEvent
            )
        }

        let response = try await providers.generate(request: request, provider: provider)

        let assistantMessageId = try conversations.insertMessage(
            ChatMessage(
                conversationId: conversationId,
                role: "model",
                text: response.text
            )
        )

        if let reasoning = response.reasoningSummary, !reasoning.isEmpty {
            try conversations.saveThinking(messageId: assistantMessageId, stream: reasoning)
        }

        return SendMessageResult(
            userMessageId: userMessageId,
            assistantMessageId: assistantMessageId,
            response: response
        )
    }

    func regenerateLastAssistantVariant(
        conversationId: Int64,
        onStreamEvent: (@Sendable (ProviderStreamEvent) -> Void)? = nil
    ) async throws -> Int64 {
        let settings = try self.settings.load()
        guard let conversation = try conversations.fetchConversation(id: conversationId) else {
            throw ProviderClientError.parseFailure("Conversation not found")
        }

        let history = try conversations.fetchProviderHistory(conversationId: conversationId)
        guard let targetIndex = history.lastIndex(where: { $0.role == "assistant" }) else {
            throw ProviderClientError.parseFailure("再生成できるAIメッセージがありません。")
        }
        guard targetIndex == history.count - 1 else {
            throw ProviderClientError.parseFailure("最後のAIメッセージのみ再生成できます。")
        }
        guard targetIndex > 0, history[targetIndex - 1].role == "user" else {
            throw ProviderClientError.parseFailure("再生成対象の直前にユーザーメッセージがありません。")
        }

        let targetMessageID = history[targetIndex].messageId
        let requestMessages = Array(history.prefix(targetIndex)).map {
            ProviderRequestMessage(role: $0.role, content: $0.text, attachments: $0.attachments)
        }
        let request = try buildProviderRequest(
            conversation: conversation,
            settings: settings,
            conversationId: conversationId,
            providerMessages: requestMessages
        )
        let provider = LLMProvider(rawOrDefault: conversation.apiProvider)

        if settings.isStreamingEnabled {
            try await streamRegeneratedVariant(
                request: request,
                provider: provider,
                baseMessageId: targetMessageID,
                onStreamEvent: onStreamEvent
            )
            return targetMessageID
        }

        let response = try await providers.generate(request: request, provider: provider)
        _ = try conversations.insertMessageVariant(
            baseMessageId: targetMessageID,
            text: response.text,
            attachmentsJSON: "[]",
            thinkingStream: response.reasoningSummary
        )
        return targetMessageID
    }

    private func streamMessage(
        conversationId: Int64,
        userMessageId: Int64,
        request: ProviderRequest,
        provider: LLMProvider,
        onStreamEvent: (@Sendable (ProviderStreamEvent) -> Void)?
    ) async throws -> SendMessageResult {
        let assistantMessageId = try conversations.insertMessage(
            ChatMessage(
                conversationId: conversationId,
                role: "model",
                text: ""
            )
        )

        var fullText = ""
        var reasoningText = ""
        do {
            let stream = try await providers.stream(request: request, provider: provider)

            for try await event in stream {
                onStreamEvent?(event)
                switch event {
                case let .textDelta(delta):
                    fullText += delta
                    try conversations.updateMessageText(messageId: assistantMessageId, text: fullText)
                case let .reasoningDelta(delta):
                    reasoningText += delta
                    try conversations.saveThinking(messageId: assistantMessageId, stream: reasoningText)
                case .toolCallDelta:
                    continue
                case let .completed(response):
                    if fullText.isEmpty {
                        fullText = response.text
                        try conversations.updateMessageText(messageId: assistantMessageId, text: fullText)
                    }
                    if let reasoning = response.reasoningSummary, !reasoning.isEmpty {
                        reasoningText = reasoning
                        try conversations.saveThinking(messageId: assistantMessageId, stream: reasoningText)
                    }
                }
            }
        } catch {
            guard shouldRetryGeminiWithGenerate(provider: provider, error: error) else {
                throw error
            }

            DiagnosticsLogger.log(
                "Gemini stream empty; retrying non-streaming generate",
                category: .network,
                metadata: [
                    "provider": provider.rawValue,
                    "model": request.model,
                    "assistantMessageId": String(assistantMessageId)
                ],
                error: error
            )

            do {
                let fallback = try await providers.generate(request: request, provider: provider)
                fullText = fallback.text
                try conversations.updateMessageText(messageId: assistantMessageId, text: fullText)

                if let reasoning = fallback.reasoningSummary, !reasoning.isEmpty {
                    reasoningText = reasoning
                    try conversations.saveThinking(messageId: assistantMessageId, stream: reasoningText)
                }
                onStreamEvent?(.completed(fallback))
                DiagnosticsLogger.log(
                    "Gemini non-streaming fallback succeeded",
                    category: .network,
                    metadata: [
                        "provider": provider.rawValue,
                        "model": request.model,
                        "assistantMessageId": String(assistantMessageId)
                    ]
                )
            } catch {
                DiagnosticsLogger.log(
                    "Gemini non-streaming fallback failed",
                    category: .network,
                    metadata: [
                        "provider": provider.rawValue,
                        "model": request.model,
                        "assistantMessageId": String(assistantMessageId)
                    ],
                    error: error
                )
                throw error
            }
        }

        let response = ProviderResponse(
            text: fullText,
            reasoningSummary: reasoningText.isEmpty ? nil : reasoningText,
            raw: nil,
            usage: nil
        )

        return SendMessageResult(
            userMessageId: userMessageId,
            assistantMessageId: assistantMessageId,
            response: response
        )
    }

    private func streamRegeneratedVariant(
        request: ProviderRequest,
        provider: LLMProvider,
        baseMessageId: Int64,
        onStreamEvent: (@Sendable (ProviderStreamEvent) -> Void)?
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

        var fullText = ""
        var reasoningText = ""
        do {
            let stream = try await providers.stream(request: request, provider: provider)

            for try await event in stream {
                onStreamEvent?(event)
                switch event {
                case let .textDelta(delta):
                    fullText += delta
                    try conversations.updateMessageVariantText(variantId: variantId, text: fullText)
                case let .reasoningDelta(delta):
                    reasoningText += delta
                    try conversations.saveMessageVariantThinking(variantId: variantId, stream: reasoningText)
                case .toolCallDelta:
                    continue
                case let .completed(response):
                    if fullText.isEmpty {
                        fullText = response.text
                        try conversations.updateMessageVariantText(variantId: variantId, text: fullText)
                    }
                    if let reasoning = response.reasoningSummary, !reasoning.isEmpty {
                        reasoningText = reasoning
                        try conversations.saveMessageVariantThinking(variantId: variantId, stream: reasoningText)
                    }
                }
            }
        } catch {
            guard shouldRetryGeminiWithGenerate(provider: provider, error: error) else {
                throw error
            }

            DiagnosticsLogger.log(
                "Gemini stream empty during regeneration; retrying non-streaming generate",
                category: .network,
                metadata: [
                    "provider": provider.rawValue,
                    "model": request.model,
                    "variantId": String(variantId)
                ],
                error: error
            )

            do {
                let fallback = try await providers.generate(request: request, provider: provider)
                fullText = fallback.text
                try conversations.updateMessageVariantText(variantId: variantId, text: fullText)

                if let reasoning = fallback.reasoningSummary, !reasoning.isEmpty {
                    reasoningText = reasoning
                    try conversations.saveMessageVariantThinking(variantId: variantId, stream: reasoningText)
                }
                onStreamEvent?(.completed(fallback))
                DiagnosticsLogger.log(
                    "Gemini non-streaming fallback succeeded for regeneration",
                    category: .network,
                    metadata: [
                        "provider": provider.rawValue,
                        "model": request.model,
                        "variantId": String(variantId)
                    ]
                )
            } catch {
                DiagnosticsLogger.log(
                    "Gemini non-streaming fallback failed for regeneration",
                    category: .network,
                    metadata: [
                        "provider": provider.rawValue,
                        "model": request.model,
                        "variantId": String(variantId)
                    ],
                    error: error
                )
                throw error
            }
        }
    }

    private func buildProviderRequest(
        conversation: Conversation,
        settings: AppSettings,
        conversationId: Int64,
        providerMessages: [ProviderRequestMessage]? = nil
    ) throws -> ProviderRequest {
        let resolvedMessages: [ProviderRequestMessage]
        if let providerMessages {
            resolvedMessages = providerMessages
        } else {
            let history = try conversations.fetchProviderHistory(conversationId: conversationId)
            resolvedMessages = history.map {
                ProviderRequestMessage(role: $0.role, content: $0.text, attachments: $0.attachments)
            }
        }

        let tools = toolsForProvider(settings: settings, provider: conversation.apiProvider)
        var metadata = metadataForProvider(
            settings: settings,
            provider: conversation.apiProvider,
            model: conversation.model
        )
        if conversation.apiProvider.uppercased() == "CODEX_AUTH" {
            let sessionId = try conversations.getOrCreateCodexSessionId(conversationId: conversationId)
            metadata["codexSessionId"] = sessionId
        }
        metadata["provider"] = conversation.apiProvider

        return ProviderRequest(
            model: conversation.model,
            messages: resolvedMessages,
            systemPrompt: conversation.systemPrompt,
            stream: settings.isStreamingEnabled,
            tools: tools,
            thinking: thinkingConfigForProvider(
                settings: settings,
                provider: conversation.apiProvider,
                model: conversation.model
            ),
            provider: providerPreferencesForProvider(settings: settings, provider: conversation.apiProvider),
            metadata: metadata
        )
    }

    func sendDualMessage(conversationId: Int64, text: String, attachments: [String] = []) async throws -> DualChatMessage {
        let settings = try self.settings.load()
        guard var conversation = try conversations.fetchConversation(id: conversationId) else {
            throw ProviderClientError.parseFailure("Conversation not found")
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
        _ = try conversations.insertDualMessage(userMessage)

        let previousDualMessages = try conversations.fetchDualMessages(conversationId: conversationId)
        let historyA = try buildDualHistory(
            conversationId: conversationId,
            dualMessages: previousDualMessages,
            modelSide: .a
        )
        let historyB = try buildDualHistory(
            conversationId: conversationId,
            dualMessages: previousDualMessages,
            modelSide: .b
        )

        let requestA = buildSingleTurnRequest(
            model: settings.dualModelA,
            text: text,
            systemPrompt: settings.dualSystemPromptA,
            provider: settings.dualProviderA,
            settings: settings,
            stream: false,
            messages: historyA,
            context: .dualA
        )

        let requestB = buildSingleTurnRequest(
            model: settings.dualModelB,
            text: text,
            systemPrompt: settings.dualSystemPromptB,
            provider: settings.dualProviderB,
            settings: settings,
            stream: false,
            messages: historyB,
            context: .dualB
        )

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
            createdAtMs: modelCreatedAt
        )
        let modelRowId = try conversations.insertDualMessage(modelRow)
        modelRow.id = modelRowId

        async let outcomeA = generateDualSideResponse(
            request: requestA,
            provider: settings.dualProviderA,
            model: settings.dualModelA
        )
        async let outcomeB = generateDualSideResponse(
            request: requestB,
            provider: settings.dualProviderB,
            model: settings.dualModelB
        )
        let (resultA, resultB) = await (outcomeA, outcomeB)

        modelRow.modelAText = resultA.text
        modelRow.modelBText = resultB.text
        modelRow.modelAThinking = resultA.reasoning
        modelRow.modelBThinking = resultB.reasoning
        try conversations.updateDualMessage(modelRow)

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

    func prepareAutoConversationSeedMessage(conversationId: Int64, text: String) throws {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return }
        guard var conversation = try conversations.fetchConversation(id: conversationId) else {
            throw ProviderClientError.parseFailure("Conversation not found")
        }
        let isFirstMessage = try conversations.isConversationEmpty(conversationId: conversationId)
        _ = try conversations.insertMessage(
            ChatMessage(
                conversationId: conversationId,
                role: "user",
                text: normalized,
                attachmentsJSON: "[]"
            )
        )
        try updateConversationTitleIfNeeded(
            conversation: &conversation,
            firstPrompt: normalized,
            isFirstMessage: isFirstMessage
        )
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
        let normalizedInitialMessage = initialMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let currentSettings = try settings.load()
        let config = AutoConversationConfig(
            title: "自動会話: \(String(normalizedInitialMessage.prefix(20)))",
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

    func searchConversations(query: String) throws -> [ConversationListEntry] {
        try conversations.searchConversations(query: query)
    }

    // MARK: - Auth APIs

    func codexAuthStatePublisher() -> AnyPublisher<CodexAuthState, Never> {
        codexAuthRepository.state
    }

    func geminiAuthStatePublisher() -> AnyPublisher<GeminiAuthState, Never> {
        geminiAuthRepository.state
    }

    func loginCodexAuth(
        apiKey: String?,
        accessToken: String?,
        email: String?,
        planType: String?,
        accountId: String?
    ) async -> Result<CodexAuthState, Error> {
        await codexAuthRepository.login(
            apiKey: apiKey,
            accessToken: accessToken,
            email: email,
            planType: planType,
            accountId: accountId
        )
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

    func loginGeminiAuth(
        accessToken: String,
        projectId: String?,
        email: String?,
        userTier: String?,
        userTierName: String?
    ) async -> Result<GeminiAuthState, Error> {
        await geminiAuthRepository.login(
            accessToken: accessToken,
            projectId: projectId,
            email: email,
            userTier: userTier,
            userTierName: userTierName
        )
    }

    func loginGeminiAuthWithBrowser() async -> Result<GeminiAuthState, Error> {
        await geminiAuthRepository.loginWithBrowser()
    }

    func isGeminiOAuthClientConfigured() -> Bool {
        geminiAuthRepository.isOAuthClientConfigured()
    }

    func hasImportedGeminiOAuthClientConfig() -> Bool {
        geminiAuthRepository.hasImportedOAuthClientConfig()
    }

    func importedGeminiOAuthClientConfig() -> GeminiOAuthClientConfig? {
        geminiAuthRepository.importedOAuthClientConfig()
    }

    func importGeminiOAuthClientConfig(fileURL: URL) -> Result<GeminiOAuthClientConfig, Error> {
        do {
            return .success(try geminiAuthRepository.importOAuthClientConfig(fileURL: fileURL))
        } catch {
            return .failure(error)
        }
    }

    func saveGeminiOAuthClientConfig(clientID: String, clientSecret: String) -> Result<GeminiOAuthClientConfig, Error> {
        do {
            return .success(
                try geminiAuthRepository.saveOAuthClientConfig(
                    clientID: clientID,
                    clientSecret: clientSecret
                )
            )
        } catch {
            return .failure(error)
        }
    }

    func clearImportedGeminiOAuthClientConfig() -> Bool {
        do {
            try geminiAuthRepository.clearImportedOAuthClientConfig()
            return true
        } catch {
            return false
        }
    }

    func logoutGeminiAuth() async -> Result<GeminiAuthState, Error> {
        await geminiAuthRepository.logout()
    }

    func refreshGeminiAuth(force: Bool = false) async -> Result<GeminiAuthState, Error> {
        await geminiAuthRepository.refreshIfNeeded(force: force)
    }

    func retrieveGeminiAuthQuota() async -> Result<GeminiUserQuota, Error> {
        await geminiAuthRepository.retrieveUserQuota()
    }

    func saveGeminiAuthProjectId(_ projectId: String?) -> Bool {
        geminiAuthRepository.saveProjectId(projectId)
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

    func getProvidersDirectory() async -> ProviderDirectory {
        await modelService.getProvidersDirectory()
    }

    // MARK: - Helpers

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

            if autoConversation.maxTurns > 0, nextTurn > autoConversation.maxTurns {
                try appendAutoConversationSystemMessage(
                    autoConversation: autoConversation,
                    text: "**[SYSTEM]**\n\n🎯 自動会話が完了しました！\n\n• 実行ターン数: \(max(0, nextTurn - 1))/\(autoConversation.maxTurns)ターン\n• 参加モデル: \(autoConversation.modelA) vs \(autoConversation.modelB)\n• 終了理由: 最大ターン数に達したため"
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
            let request = buildSingleTurnRequest(
                model: turnModel,
                text: "",
                systemPrompt: turnPrompt,
                provider: turnProvider,
                settings: currentSettings,
                stream: false,
                messages: history,
                context: speaker.context
            )

            let response: ProviderResponse
            do {
                response = try await providers.generate(
                    request: request,
                    provider: LLMProvider(rawOrDefault: turnProvider)
                )
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
                throw ProviderClientError.parseFailure("自動会話で空の応答を受信しました。")
            }

            let hasEndSignal = containsAutoConversationEndSignal(
                text: responseText,
                configuredEndSignal: autoConversation.endSignal
            )
            _ = try conversations.insertAutoConversationMessage(
                AutoConversationMessage(
                    autoConversationId: autoConversationId,
                    speakerModel: speaker.modelCode,
                    content: responseText,
                    reasoning: reasoning?.isEmpty == true ? nil : reasoning,
                    turnNumber: nextTurn,
                    isEndSignal: hasEndSignal
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
                    text: "**[SYSTEM]**\n\n🏁 自動会話が終了しました\n\n• 実行ターン数: \(nextTurn)/\(autoConversation.maxTurns > 0 ? String(autoConversation.maxTurns) : "無制限")ターン\n• 参加モデル: \(autoConversation.modelA) vs \(autoConversation.modelB)\n• 終了理由: AIモデルが会話終了を宣言"
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

    private func shouldRetryGeminiWithGenerate(provider: LLMProvider, error: Error) -> Bool {
        guard provider == .geminiAuth else { return false }
        guard case let ProviderClientError.parseFailure(reason) = error else { return false }
        let normalized = reason.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if normalized == GeminiProviderClient.noUsableStreamDataReason.lowercased() {
            return true
        }
        return normalized.contains("no usable data")
    }

    private func buildSingleTurnRequest(
        model: String,
        text: String,
        systemPrompt: String?,
        provider: String,
        settings: AppSettings,
        stream: Bool? = nil,
        messages: [ProviderRequestMessage]? = nil,
        context: AppSettings.ReasoningContext = .default
    ) -> ProviderRequest {
        var metadata = metadataForProvider(
            settings: settings,
            provider: provider,
            model: model,
            context: context
        )
        metadata["provider"] = provider
        return ProviderRequest(
            model: model,
            messages: messages ?? [ProviderRequestMessage(role: "user", content: text)],
            systemPrompt: systemPrompt,
            stream: stream ?? settings.isStreamingEnabled,
            tools: toolsForProvider(settings: settings, provider: provider, context: context),
            thinking: thinkingConfigForProvider(settings: settings, provider: provider, model: model, context: context),
            provider: providerPreferencesForProvider(settings: settings, provider: provider),
            metadata: metadata
        )
    }

    private func toolsForProvider(
        settings: AppSettings,
        provider: String,
        context: AppSettings.ReasoningContext = .default
    ) -> [ProviderTool] {
        let overrides = settings.toolOverride(for: context)
        switch provider.uppercased() {
        case "GEMINI", "GEMINI_AUTH":
            var tools: [ProviderTool] = []
            if overrides.googleSearch ?? settings.geminiGoogleSearchEnabled {
                tools.append(ProviderTool(type: "google_search", payload: [:]))
            }
            if overrides.codeExecution ?? settings.geminiCodeExecutionEnabled {
                tools.append(ProviderTool(type: "code_execution", payload: [:]))
            }
            if overrides.urlContext ?? settings.geminiURLContextEnabled {
                tools.append(ProviderTool(type: "url_context", payload: [:]))
            }
            if overrides.googleMaps ?? settings.geminiGoogleMapsEnabled {
                tools.append(ProviderTool(type: "google_maps", payload: [:]))
            }
            if overrides.computerUse ?? settings.geminiComputerUseEnabled {
                tools.append(ProviderTool(type: "computer_use", payload: [:]))
            }
            let declarations = settings.geminiFunctionDeclarations.trimmingCharacters(in: .whitespacesAndNewlines)
            if !declarations.isEmpty {
                tools.append(ProviderTool(type: "function_declarations", payload: ["json": declarations]))
            }
            return tools
        case "OPENROUTER":
            var tools: [ProviderTool] = []
            if overrides.googleSearch ?? settings.openRouterGoogleSearchEnabled {
                tools.append(ProviderTool(type: "google_search", payload: [:]))
            }
            if overrides.codeExecution ?? settings.openRouterCodeExecutionEnabled {
                tools.append(ProviderTool(type: "code_execution", payload: [:]))
            }
            return tools
        default:
            return []
        }
    }

    private func metadataForProvider(
        settings: AppSettings,
        provider: String,
        model: String,
        context: AppSettings.ReasoningContext = .default
    ) -> [String: String] {
        switch provider.uppercased() {
        case "CODEX_AUTH":
            let summary = settings.codexReasoningSummary.ifBlank("auto").lowercased()
            let summaryToSend: String?
            if settings.codexReasoningEnabled &&
                summary != "none" &&
                (settings.codexSupportsReasoningSummaries || CodexModelCatalog.supportsReasoningSummary(model)) {
                summaryToSend = summary
            } else {
                summaryToSend = nil
            }

            let verbosity = settings.codexVerbosity.ifBlank("medium").lowercased()
            let verbosityToSend = CodexModelCatalog.supportsTextVerbosity(model) ? verbosity : nil

            var metadata: [String: String] = [
                "codexUserAgentPreset": settings.codexUserAgentPreset.ifBlank(CodexUserAgentPresetCatalog.presetAndroid),
                "codexWebSearchEnabled": settings.codexWebSearchEnabled ? "true" : "false",
                "codexWebSearchContextSize": settings.codexWebSearchContextSize.ifBlank("medium"),
                "codexPromptCacheEnabled": settings.codexPromptCacheEnabled ? "true" : "false",
                "codexPromptCacheMinLength": String(max(0, settings.codexPromptCacheMinLength)),
                "codexPromptCacheType": settings.codexPromptCacheType.ifBlank("ephemeral")
            ]
            if let summaryToSend {
                metadata["codexReasoningSummary"] = summaryToSend
            }
            if let verbosityToSend {
                metadata["codexVerbosity"] = verbosityToSend
            }
            return metadata
        case "GEMINI", "GEMINI_AUTH":
            let overrides = settings.thinkingOverride(for: context)
            let level = effectiveGeminiThinkingLevel(
                settings: settings,
                model: model,
                enabledOverride: overrides.enabled,
                levelOverride: overrides.level
            ) ?? ""
            return [
                "geminiResponseMimeType": settings.geminiResponseMimeType,
                "geminiResponseJSONSchema": settings.geminiResponseJSONSchema,
                "geminiFunctionDeclarations": settings.geminiFunctionDeclarations,
                "geminiThinkingLevel": level
            ]
        default:
            return [:]
        }
    }

    private func thinkingConfigForProvider(
        settings: AppSettings,
        provider: String,
        model: String,
        context: AppSettings.ReasoningContext = .default
    ) -> ProviderThinkingConfig? {
        let overrides = settings.thinkingOverride(for: context)
        switch provider.uppercased() {
        case "OPENROUTER":
            return buildOpenRouterThinkingConfig(settings: settings, context: context)
        case "CODEX_AUTH":
            let enabled = overrides.enabled ?? settings.codexReasoningEnabled
            let baseEffort = settings.codexReasoningEffort.ifBlank("medium")
            let overrideEffort = overrides.codexEffort?.ifBlank(baseEffort)
            let effort = enabled ? (overrideEffort ?? baseEffort) : "none"
            return ProviderThinkingConfig(
                enabled: nil,
                budget: nil,
                effort: effort,
                includeThoughts: true,
                exclude: nil
            )
        case "GEMINI", "GEMINI_AUTH":
            let enabled = overrides.enabled ?? settings.geminiThinkingEnabled
            let budget = overrides.budget ?? settings.geminiThinkingBudget
            if GeminiModelUtils.isThinkingLevelSupported(model: model) {
                return ProviderThinkingConfig(
                    enabled: nil,
                    budget: nil,
                    effort: nil,
                    includeThoughts: true,
                    exclude: nil
                )
            }
            guard let budget = GeminiModelUtils.calculateEffectiveThinkingBudget(
                model: model,
                userThinkingEnabled: enabled,
                userThinkingBudget: budget
            ) else {
                return nil
            }
            return ProviderThinkingConfig(
                enabled: nil,
                budget: budget,
                effort: nil,
                includeThoughts: true,
                exclude: nil
            )
        default:
            return nil
        }
    }

    private func buildOpenRouterThinkingConfig(
        settings: AppSettings,
        context: AppSettings.ReasoningContext = .default
    ) -> ProviderThinkingConfig? {
        let overrides = settings.openRouterOverride(for: context)
        let reasoningExclude = overrides.exclude ?? settings.openRouterReasoningExclude
        let thinkingEnabled = overrides.enabled ?? settings.openRouterThinkingEnabled
        let reasoningMode = (overrides.mode ?? settings.openRouterReasoningMode)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let reasoningEffort = (overrides.effort ?? settings.openRouterReasoningEffort)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let thinkingBudget = max(0, overrides.budget ?? settings.openRouterThinkingBudget)

        let includeThoughts = !reasoningExclude
        if !thinkingEnabled {
            return ProviderThinkingConfig(
                enabled: false,
                budget: nil,
                effort: nil,
                includeThoughts: includeThoughts,
                exclude: true
            )
        }

        let mode = ["auto", "effort", "budget"].contains(reasoningMode) ? reasoningMode : "auto"
        let budget = (mode == "budget" && thinkingBudget > 0) ? thinkingBudget : nil
        let effort: String?
        if mode == "effort" {
            let normalized = reasoningEffort
            effort = normalized.isEmpty ? nil : normalized
        } else {
            effort = nil
        }
        let enabled: Bool? = (mode == "auto" || (budget == nil && effort == nil)) ? true : nil
        let exclude: Bool? = reasoningExclude ? true : nil

        if budget == nil, effort == nil, enabled == nil, exclude == nil {
            return nil
        }

        return ProviderThinkingConfig(
            enabled: enabled,
            budget: budget,
            effort: effort,
            includeThoughts: includeThoughts,
            exclude: exclude
        )
    }

    private func providerPreferencesForProvider(settings: AppSettings, provider: String) -> ProviderRoutingConfig? {
        guard provider.uppercased() == "OPENROUTER" else { return nil }

        let providers = settings.preferredProvidersList()
        let quantizations = settings.selectedQuantizationsList()

        if providers.isEmpty, quantizations.isEmpty, settings.maxPricePerMillionTokens <= 0 {
            return nil
        }

        let onlyProviders: [String]?
        if !settings.allowFallbacks, providers.count == 1 {
            onlyProviders = providers
        } else {
            onlyProviders = nil
        }
        let orderProviders = onlyProviders == nil ? (providers.isEmpty ? nil : providers) : nil

        let maxPrice: ProviderMaxPriceConfig?
        if settings.maxPricePerMillionTokens > 0 {
            maxPrice = ProviderMaxPriceConfig(
                prompt: settings.maxPricePerMillionTokens,
                completion: settings.maxPricePerMillionTokens,
                request: nil,
                image: nil,
                audio: nil
            )
        } else {
            maxPrice = nil
        }

        let trimmedSort = settings.providerSort.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return ProviderRoutingConfig(
            order: orderProviders,
            allowFallbacks: providers.isEmpty ? nil : settings.allowFallbacks,
            requireParameters: settings.requireParameters ? true : nil,
            dataCollection: nil,
            quantizations: quantizations.isEmpty ? nil : quantizations,
            maxPrice: maxPrice,
            only: onlyProviders,
            ignore: nil,
            sort: trimmedSort.isEmpty ? nil : trimmedSort
        )
    }

    private func effectiveGeminiThinkingLevel(settings: AppSettings, model: String) -> String? {
        effectiveGeminiThinkingLevel(
            settings: settings,
            model: model,
            enabledOverride: nil,
            levelOverride: nil
        )
    }

    private func effectiveGeminiThinkingLevel(
        settings: AppSettings,
        model: String,
        enabledOverride: Bool?,
        levelOverride: String?
    ) -> String? {
        guard GeminiModelUtils.isThinkingLevelSupported(model: model) else { return nil }

        let defaultLevel = GeminiModelUtils.getDefaultThinkingLevel(model: model)
        let levelSource = levelOverride ?? settings.geminiThinkingLevel
        var normalized = GeminiModelUtils.normalizeThinkingLevel(
            model: model,
            level: levelSource
        ) ?? defaultLevel

        let enabled = enabledOverride ?? settings.geminiThinkingEnabled
        if !GeminiModelUtils.isThinkingAlwaysOn(model: model), !enabled {
            if let minimal = GeminiModelUtils.getMinimalThinkingLevel(model: model) {
                normalized = minimal
            }
        }
        return normalized
    }

    private enum DualHistorySide {
        case a
        case b
    }

    private struct DualSideResult {
        var text: String
        var reasoning: String?
        var error: Error?
    }

    private func generateDualSideResponse(
        request: ProviderRequest,
        provider: String,
        model: String
    ) async -> DualSideResult {
        do {
            let response = try await providers.generate(
                request: request,
                provider: LLMProvider(rawOrDefault: provider)
            )
            return DualSideResult(
                text: response.text,
                reasoning: response.reasoningSummary,
                error: nil
            )
        } catch {
            return DualSideResult(
                text: "エラー: \(error.localizedDescription)",
                reasoning: nil,
                error: error
            )
        }
    }

    private func buildDualHistory(
        conversationId: Int64,
        dualMessages: [DualChatMessage],
        modelSide: DualHistorySide
    ) throws -> [ProviderRequestMessage] {
        var messages: [ProviderRequestMessage] = try conversations.fetchProviderHistory(conversationId: conversationId).map {
            ProviderRequestMessage(role: $0.role, content: $0.text, attachments: $0.attachments)
        }

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
            return snippet.isEmpty ? "ブランチ" : "ブランチ: \(snippet)"
        }
        return "ブランチ: \(baseTitle)"
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
