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
    private let codexAuthRepository: CodexAuthRepository
    private let superGrokAuthRepository: SuperGrokAuthRepository
    private let pricingRepository: any LiteLlmPricingEstimating
    private let localToolRegistry: LocalToolRegistry
    private let fusionService: FusionService
    private let fusionTraceStore: FusionTraceStore
    private let fusionOrchestrator: FusionOrchestrator

    init(
        conversations: ConversationRepository,
        settings: SettingsRepository,
        providers: ProviderGateway,
        credentialStore: SecureCredentialStore,
        modelService: OpenRouterModelService,
        codexAuthRepository: CodexAuthRepository,
        superGrokAuthRepository: SuperGrokAuthRepository,
        pricingRepository: any LiteLlmPricingEstimating = LiteLlmPricingRepository(),
        localToolRegistry: LocalToolRegistry = LocalToolRegistry(
            executors: [
                WebSearchTool(),
                FetchUrlTool()
            ]
        ),
        fusionService: FusionService,
        fusionTraceStore: FusionTraceStore,
        fusionOrchestrator: FusionOrchestrator = FusionOrchestrator()
    ) {
        self.conversations = conversations
        self.settings = settings
        self.providers = providers
        self.credentialStore = credentialStore
        self.modelService = modelService
        self.codexAuthRepository = codexAuthRepository
        self.superGrokAuthRepository = superGrokAuthRepository
        self.pricingRepository = pricingRepository
        self.localToolRegistry = localToolRegistry
        self.fusionService = fusionService
        self.fusionTraceStore = fusionTraceStore
        self.fusionOrchestrator = fusionOrchestrator
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
        if title == "New Chat",
           let existing = try conversations.fetchLatestEmptyConversation(title: title, projectId: projectId),
           let id = existing.id {
            return id
        }

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
            throw ProviderClientError.parseFailure(L10n.text("プロジェクト名を入力してください。"))
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

    func deleteConversations(ids: Set<Int64>) throws {
        try conversations.deleteConversations(ids: ids)
    }

    @discardableResult
    func deleteSecretConversationIfNeeded(id: Int64) throws -> Bool {
        try conversations.deleteSecretConversationIfNeeded(id: id)
    }

    func purgeSecretConversations() throws {
        try conversations.purgeSecretConversations()
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
        onStreamEvent: (@Sendable (ProviderStreamEvent) -> Void)? = nil,
        onStreamingSnapshot: (@Sendable (ChatStreamingSnapshot) -> Void)? = nil
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

        let request = try await buildProviderRequest(
            conversation: conversation,
            settings: settings,
            conversationId: conversationId
        )
        let provider = conversation.apiProvider

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
        onStreamEvent: (@Sendable (ProviderStreamEvent) -> Void)? = nil,
        onStreamingSnapshot: (@Sendable (ChatStreamingSnapshot) -> Void)? = nil
    ) async throws -> Int64 {
        let settings = try self.settings.load()
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
        let requestMessages = Array(history.prefix(targetIndex)).map {
            ProviderRequestMessage(role: $0.role, content: $0.text, attachments: $0.attachments)
        }
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
            resolvedMessages = history.map {
                ProviderRequestMessage(
                    role: $0.role,
                    content: $0.text,
                    attachments: $0.attachments,
                    reasoningContent: $0.thinkingStream
                )
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
        metadata["promptCacheKey"] = "conversation-\(conversationId)"
        metadata["supportsVision"] = await visionMetadataFlag(
            provider: conversation.apiProvider,
            model: conversation.model
        )

        return ProviderRequest(
            model: conversation.model,
            messages: resolvedMessages,
            systemPrompt: SystemPromptComposer.composeForAPI(conversation.systemPrompt),
            stream: settings.isStreamingEnabled,
            tools: tools,
            thinking: thinkingConfigForProvider(
                settings: settings,
                provider: conversation.apiProvider,
                model: conversation.model
            ),
            provider: await providerPreferencesForProvider(
                settings: settings,
                provider: conversation.apiProvider,
                model: conversation.model
            ),
            metadata: metadata
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
        let orchestrator = ToolCallingOrchestrator(registry: localToolRegistry)
        do {
            let outcome = try await orchestrator.run(
                request: request,
                invoke: { [self] roundRequest, round in
                    do {
                        return try await executeProviderRound(
                            request: roundRequest,
                            provider: provider,
                            persistenceKind: persistenceKind,
                            streamEnabled: streamEnabled,
                            persistResults: persistResults,
                            onStreamEvent: onStreamEvent,
                            onStreamingSnapshot: onStreamingSnapshot
                        )
                    } catch {
                        guard ClientToolFallbackPolicy.shouldRetryWithoutClientTools(
                            error: error,
                            request: roundRequest,
                            round: round
                        ) else {
                            throw error
                        }
                        DiagnosticsLogger.log(
                            "Model rejected client tools; retrying without local functions",
                            level: .warning,
                            category: .network,
                            metadata: [
                                "provider": provider,
                                "model": roundRequest.model
                            ],
                            error: error
                        )
                        return try await executeProviderRound(
                            request: ClientToolFallbackPolicy.removingClientTools(from: roundRequest),
                            provider: provider,
                            persistenceKind: persistenceKind,
                            streamEnabled: streamEnabled,
                            persistResults: persistResults,
                            onStreamEvent: onStreamEvent,
                            onStreamingSnapshot: onStreamingSnapshot
                        )
                    }
                },
                onActivitiesChanged: { [self] activities in
                    guard persistResults else { return }
                    do {
                        try saveToolActivities(kind: persistenceKind, steps: activities)
                    } catch {
                        DiagnosticsLogger.log(
                            "Tool activity persistence failed",
                            category: .chat,
                            metadata: [
                                "conversation": String(conversationId),
                                "target": toolActivityTargetDescription(kind: persistenceKind)
                            ],
                            error: error
                        )
                    }
                }
            )
            if persistResults {
                try persistProviderResponse(outcome.response, kind: persistenceKind)
            }
            return outcome.response
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
            return ProviderResponse(
                text: session.text,
                reasoningSummary: session.reasoningText.trimmedNonEmpty,
                raw: nil,
                usage: session.usage,
                toolCalls: session.toolCalls
            )
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
    }

    private func saveToolActivities(
        kind: ChatStreamPersistenceKind,
        steps: [ToolActivityStep]
    ) throws {
        switch kind {
        case let .message(messageId):
            try conversations.saveToolActivities(messageId: messageId, steps: steps)
        case let .variant(variantId, _):
            try conversations.saveToolActivities(variantId: variantId, steps: steps)
        }
    }

    private func toolActivityTargetDescription(kind: ChatStreamPersistenceKind) -> String {
        switch kind {
        case let .message(messageId):
            return "message:\(messageId)"
        case let .variant(variantId, _):
            return "variant:\(variantId)"
        }
    }

    func sendDualMessage(conversationId: Int64, text: String, attachments: [String] = []) async throws -> DualChatMessage {
        let bgGuard = BackgroundTaskGuard()
        bgGuard.begin(name: "YamabikoChatDualStreaming")
        defer { bgGuard.end() }

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

        let requestA = await buildSingleTurnRequest(
            model: settings.dualModelA,
            text: text,
            systemPrompt: settings.dualSystemPromptA,
            provider: settings.dualProviderA,
            settings: settings,
            stream: false,
            messages: historyA,
            context: .dualA,
            promptCacheKey: "conversation-\(conversationId)-dual-a"
        )

        let requestB = await buildSingleTurnRequest(
            model: settings.dualModelB,
            text: text,
            systemPrompt: settings.dualSystemPromptB,
            provider: settings.dualProviderB,
            settings: settings,
            stream: false,
            messages: historyB,
            context: .dualB,
            promptCacheKey: "conversation-\(conversationId)-dual-b"
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

        await recordTokenUsageIfAvailable(
            provider: settings.dualProviderA,
            model: settings.dualModelA,
            usage: resultA.usage,
            conversationId: conversationId,
            requestType: "dual_a"
        )
        await recordTokenUsageIfAvailable(
            provider: settings.dualProviderB,
            model: settings.dualModelB,
            usage: resultB.usage,
            conversationId: conversationId,
            requestType: "dual_b"
        )

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

    func sendFusionMessage(
        conversationId: Int64,
        text: String,
        attachments: [String] = [],
        onFusionProgress: (@Sendable (FusionProgressSnapshot) -> Void)? = nil,
        onStreamEvent: (@Sendable (ProviderStreamEvent) -> Void)? = nil,
        onStreamingSnapshot: (@Sendable (ChatStreamingSnapshot) -> Void)? = nil
    ) async throws -> SendMessageResult {
        let bgGuard = BackgroundTaskGuard()
        bgGuard.begin(name: "YamabikoChatFusion")
        defer { bgGuard.end() }

        let settings = try self.settings.load()
        guard settings.isFusionModeEnabled else {
            throw ProviderClientError.parseFailure(L10n.text("Fusion モードが有効ではありません。"))
        }
        guard var conversation = try conversations.fetchConversation(id: conversationId) else {
            throw ProviderClientError.parseFailure("Conversation not found")
        }
        let isFirstMessage = try conversations.isConversationEmpty(conversationId: conversationId)
        let normalizedAttachments = attachments.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

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

        let taskType = FusionTaskType(rawValue: settings.fusionTaskType.lowercased()) ?? .auto
        let allowWebSearchOverride: Bool? = settings.clientWebSearchToolEnabled ? nil : false
        let fusionRequest: FusionRequest
        do {
            fusionRequest = try FusionPresetLoader.buildRequest(
                userPrompt: text,
                systemPrompt: conversation.systemPrompt,
                taskTypeOverride: taskType,
                allowWebSearchOverride: allowWebSearchOverride,
                customPresetJSON: settings.fusionCustomPresetJSON
            )
        } catch {
            DiagnosticsLogger.log("Fusion preset load failed", category: .fusion, error: error)
            throw error
        }

        let history = try conversations.fetchProviderHistory(conversationId: conversationId).map {
            ProviderRequestMessage(
                role: $0.role,
                content: $0.text,
                attachments: $0.attachments
            )
        }

        let context = FusionContext(
            fusionDepth: 0,
            debugMode: settings.fusionDebugModeEnabled,
            logPrompts: settings.fusionLogPromptsEnabled,
            conversationId: conversationId
        )

        let judgeOutcome: FusionJudgeOutcome
        do {
            judgeOutcome = try await fusionService.runThroughJudge(
                request: fusionRequest,
                context: context,
                conversationHistory: history,
                userAttachments: normalizedAttachments,
                onProgress: onFusionProgress
            )
        } catch FusionError.allPanelsFailed(let panelResults) {
            DiagnosticsLogger.log(
                "Fusion all panels failed; falling back to single model",
                category: .fusion,
                metadata: [
                    "conversationId": String(conversationId),
                    "preset": fusionRequest.preset
                ]
            )
            let failedTraceId = UUID().uuidString
            let failedTrace = FusionTrace(
                requestId: failedTraceId,
                preset: fusionRequest.preset,
                startedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
                completedAtMs: Int64(Date().timeIntervalSince1970 * 1000),
                panelResults: panelResults,
                judgeResult: nil,
                synthesisResult: nil,
                totalLatencyMs: panelResults.map(\.latencyMs).max(),
                totalCost: nil,
                failedModels: panelResults.map(\.modelId),
                status: "all_panels_failed",
                userPrompt: settings.fusionLogPromptsEnabled ? text : nil,
                finalAnswer: nil
            )
            try fusionTraceStore.save(trace: failedTrace, conversationId: conversationId)

            let failedPanelChips = panelResults.map { result in
                FusionPanelChipStatus(
                    modelId: result.modelId,
                    provider: result.provider,
                    state: result.success ? .succeeded : .failed
                )
            }
            onFusionProgress?(
                FusionProgressSnapshot.phaseOnly(.fallback, panels: failedPanelChips)
            )

            let fallbackModel = fusionRequest.fallbackModel ?? fusionRequest.synthesizerModel
            let fallbackSupportsVision = await pricingRepository.modelSupportsVision(
                provider: fallbackModel.provider,
                model: fallbackModel.modelId
            )
            let request = fusionService.buildProviderRequest(
                model: fallbackModel,
                systemPrompt: conversation.systemPrompt ?? "",
                phase: .fallback,
                allowTools: false,
                maxTokens: fusionRequest.maxSynthesizerTokens,
                settings: settings,
                fusionDepth: 0,
                userPrompt: text,
                conversationHistory: history,
                userAttachments: normalizedAttachments,
                supportsVision: fallbackSupportsVision
            )
            let provider = fallbackModel.provider
            let assistantMessageId = try conversations.insertMessage(
                ChatMessage(
                    conversationId: conversationId,
                    role: "model",
                    text: "",
                    fusionTraceId: failedTraceId
                )
            )
            let response = try await runToolCallingTurn(
                request: request,
                provider: provider,
                conversationId: conversationId,
                persistenceKind: .message(messageId: assistantMessageId),
                streamEnabled: settings.isStreamingEnabled,
                onStreamEvent: onStreamEvent,
                onStreamingSnapshot: onStreamingSnapshot
            )
            await recordTokenUsageIfAvailable(
                provider: fallbackModel.provider,
                model: fallbackModel.modelId,
                usage: response.usage,
                conversationId: conversationId,
                requestType: "fusion_fallback"
            )
            return SendMessageResult(
                userMessageId: userMessageId,
                assistantMessageId: assistantMessageId,
                response: response
            )
        }

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
        var finalText: String
        var synthUsage: ProviderUsage?
        var synthesisResult: SynthesisPhaseResult

        do {
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
            finalText = session.text
            synthUsage = session.usage
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
            synthesisResult = SynthesisPhaseResult(
                modelId: judgeOutcome.synthesizerModel.modelId,
                provider: judgeOutcome.synthesizerModel.provider.uppercased(),
                success: true,
                content: finalText,
                latencyMs: latencyMs,
                inputTokens: synthUsage?.inputTokens,
                outputTokens: synthUsage?.outputTokens,
                cost: cost,
                error: nil,
                usedFallback: false
            )
        } catch {
            finalText = judgeOutcome.staticFallbackAnswer
            if finalText.isEmpty {
                finalText = L10n.format("エラー: %@", error.localizedDescription)
            }
            try conversations.updateMessageText(messageId: assistantMessageId, text: finalText)
            synthesisResult = SynthesisPhaseResult(
                modelId: judgeOutcome.synthesizerModel.modelId,
                provider: judgeOutcome.synthesizerModel.provider.uppercased(),
                success: false,
                content: finalText,
                latencyMs: Int64(Date().timeIntervalSince(synthStarted) * 1000),
                inputTokens: nil,
                outputTokens: nil,
                cost: nil,
                error: error.localizedDescription,
                usedFallback: true
            )
            DiagnosticsLogger.log(
                "Fusion synthesizer stream failed; using fallback",
                category: .fusion,
                requestID: judgeOutcome.trace.requestId,
                error: error
            )
        }

        await recordTokenUsageIfAvailable(
            provider: judgeOutcome.synthesizerModel.provider,
            model: judgeOutcome.synthesizerModel.modelId,
            usage: synthUsage,
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
            resolvedSystemPrompt = settings.systemPrompt
        }

        let request = await buildSingleTurnRequest(
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
                let response = try await runToolCallingTurn(
                    request: request,
                    provider: resolvedProvider,
                    conversationId: conversationId,
                    persistenceKind: .message(messageId: assistantMessageId),
                    streamEnabled: false,
                    persistResults: true,
                    onStreamEvent: nil,
                    onStreamingSnapshot: nil
                )
                await recordTokenUsageIfAvailable(
                    provider: normalizedProvider,
                    model: normalizedModel,
                    usage: response.usage,
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

    func resolveContextLimit(provider: String, model: String) async -> Int? {
        let normalizedModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedModel.isEmpty else { return nil }

        if let direct = modelService.getModelById(normalizedModel)?.contextLength, direct > 0 {
            return direct
        }

        let lowerModel = normalizedModel.lowercased()
        let withoutVariant = lowerModel.components(separatedBy: ":").first ?? lowerModel
        let suffix = withoutVariant.split(separator: "/").dropFirst().joined(separator: "/")

        let refresh = modelService.currentModels().isEmpty
        let available = await modelService.getAvailableModels(forceRefresh: refresh)
        if let exact = available.first(where: { $0.id.lowercased() == lowerModel }), exact.contextLength > 0 {
            return exact.contextLength
        }
        if !suffix.isEmpty,
           let loose = available.first(where: { model in
               let candidate = model.id.lowercased().components(separatedBy: ":").first ?? model.id.lowercased()
               return candidate == withoutVariant || candidate.hasSuffix("/\(suffix)")
           }),
           loose.contextLength > 0 {
            return loose.contextLength
        }

        let providerKey = provider.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if providerKey == "OPENROUTER",
           let fallback = modelService.getModelById(normalizedModel)?.contextLength,
           fallback > 0 {
            return fallback
        }
        return nil
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
            let request = await buildSingleTurnRequest(
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
                response = try await providers.generate(request: request, providerID: turnProvider)
                await recordTokenUsageIfAvailable(
                    provider: turnProvider,
                    model: turnModel,
                    usage: response.usage,
                    conversationId: autoConversation.boundChatConversationId,
                    requestType: "auto_turn"
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
                throw ProviderClientError.parseFailure(L10n.text("自動会話で空の応答を受信しました。"))
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
        conversationId: Int64?,
        requestType: String
    ) async {
        guard let normalized = usage?.normalizedNonEmpty() else { return }
        let resolvedInput = max(0, normalized.inputTokens ?? 0)
        let resolvedOutput = max(0, normalized.outputTokens ?? 0)
        let resolvedTotal = max(
            max(0, normalized.totalTokens ?? (resolvedInput + resolvedOutput)),
            resolvedInput + resolvedOutput
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

    private func buildSingleTurnRequest(
        model: String,
        text: String,
        systemPrompt: String?,
        provider: String,
        settings: AppSettings,
        stream: Bool? = nil,
        messages: [ProviderRequestMessage]? = nil,
        context: AppSettings.ReasoningContext = .default,
        promptCacheKey: String? = nil
    ) async -> ProviderRequest {
        var metadata = metadataForProvider(
            settings: settings,
            provider: provider,
            model: model,
            context: context
        )
        metadata["provider"] = provider
        if let promptCacheKey = promptCacheKey?.trimmingCharacters(in: .whitespacesAndNewlines), !promptCacheKey.isEmpty {
            metadata["promptCacheKey"] = promptCacheKey
        }
        metadata["supportsVision"] = await visionMetadataFlag(provider: provider, model: model)
        return ProviderRequest(
            model: model,
            messages: messages ?? [ProviderRequestMessage(role: "user", content: text)],
            systemPrompt: SystemPromptComposer.composeForAPI(systemPrompt),
            stream: stream ?? settings.isStreamingEnabled,
            tools: toolsForProvider(settings: settings, provider: provider, context: context),
            thinking: thinkingConfigForProvider(settings: settings, provider: provider, model: model, context: context),
            provider: await providerPreferencesForProvider(
                settings: settings,
                provider: provider,
                model: model
            ),
            metadata: metadata
        )
    }

    private func toolsForProvider(
        settings: AppSettings,
        provider: String,
        context: AppSettings.ReasoningContext = .default
    ) -> [ProviderTool] {
        let overrides = settings.toolOverride(for: context)
        let supportsClientWebSearch = ProviderReference(persistedID: provider).isModelsDev
            || LLMProvider(rawOrDefault: provider).supportsClientWebSearchTool
        var tools: [ProviderTool]
        switch provider.uppercased() {
        case "GEMINI":
            tools = []
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
        case "OPENROUTER":
            tools = []
            if overrides.googleSearch ?? settings.openRouterGoogleSearchEnabled {
                tools.append(ProviderTool(type: "google_search", payload: [:]))
            }
            if overrides.codeExecution ?? settings.openRouterCodeExecutionEnabled {
                tools.append(ProviderTool(type: "code_execution", payload: [:]))
            }
        case "ALIBABA_CODING_PLAN":
            tools = []
            if settings.alibabaMCPEnabled {
                if let serverURL = settings.resolvedAlibabaMCPServerURL() {
                    var payload: [String: String] = [
                        "server_url": serverURL,
                        "server_name": settings.resolvedAlibabaMCPServerName()
                    ]
                    let allowedTools = settings.alibabaMCPAllowedToolsList()
                    if !allowedTools.isEmpty {
                        payload["allowed_tools"] = allowedTools.joined(separator: ",")
                    }
                    tools.append(ProviderTool(type: "mcp_toolset", payload: payload))
                } else {
                    DiagnosticsLogger.log(
                        "Alibaba MCP enabled but server URL is invalid; skipping MCP toolset",
                        level: .warning,
                        category: .settings
                    )
                }
            }
        default:
            tools = []
        }

        if case .default = context,
           settings.clientWebSearchToolEnabled,
           supportsClientWebSearch {
            tools.append(contentsOf: localToolRegistry.definitions.map(\.providerTool))
        }
        return tools
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
        case "GEMINI":
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
        case "SUPERGROK":
            let enabled = overrides.enabled ?? settings.superGrokReasoningEnabled
            let baseEffort = settings.superGrokReasoningEffort.ifBlank("medium")
            let overrideEffort = overrides.codexEffort?.ifBlank(baseEffort)
            let rawEffort = enabled ? (overrideEffort ?? baseEffort) : "none"
            let effort: String
            if rawEffort == "none" {
                effort = "none"
            } else {
                let normalized = rawEffort.lowercased()
                effort = ["low", "medium", "high"].contains(normalized) ? normalized : "medium"
            }
            // Catalog miss = custom model; only omit reasoning for known non-reasoning models.
            if let catalog = SuperGrokModelCatalog.model(for: model), !catalog.supportsReasoning {
                return nil
            }
            return ProviderThinkingConfig(
                enabled: nil,
                budget: nil,
                effort: effort,
                includeThoughts: true,
                exclude: nil
            )
        case "GEMINI":
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

    private func providerPreferencesForProvider(
        settings: AppSettings,
        provider: String,
        model: String
    ) async -> ProviderRoutingConfig? {
        guard provider.uppercased() == "OPENROUTER" else { return nil }

        let catalogModel = modelService.getModelById(model)
        let availableProviders = await openRouterAvailableProviderSlugs(for: model, catalogModel: catalogModel)
        let availableQuantizations = openRouterAvailableQuantizations(catalogModel: catalogModel)

        let preferredProviders = settings.preferredProvidersList()
        let providers = resolveCompatibleOpenRouterProviderSlugs(
            preferredProviders,
            available: availableProviders
        )
        let quantizations = filterCompatibleOpenRouterSlugs(
            settings.selectedQuantizationsList(),
            available: availableQuantizations
        )

        let hasRoutingProviders = !providers.isEmpty
        if !hasRoutingProviders, quantizations.isEmpty, settings.maxPricePerMillionTokens <= 0 {
            if !preferredProviders.isEmpty {
                DiagnosticsLogger.log(
                    "OpenRouter provider routing omitted with incompatible preferred provider",
                    category: .network,
                    metadata: [
                        "model": model,
                        "preferred": preferredProviders.joined(separator: ",")
                    ]
                )
            }
            return nil
        }

        let onlyProviders: [String]?
        if !settings.allowFallbacks, hasRoutingProviders {
            onlyProviders = providers
        } else {
            onlyProviders = nil
        }
        let orderProviders = onlyProviders == nil ? (hasRoutingProviders ? providers : nil) : nil

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

        DiagnosticsLogger.log(
            "OpenRouter provider routing applied",
            category: .network,
            metadata: [
                "model": model,
                "providers": providers.joined(separator: ","),
                "only": (onlyProviders ?? []).joined(separator: ","),
                "allow_fallbacks": String(settings.allowFallbacks)
            ]
        )

        return ProviderRoutingConfig(
            order: orderProviders,
            allowFallbacks: hasRoutingProviders ? settings.allowFallbacks : nil,
            requireParameters: settings.requireParameters ? true : nil,
            dataCollection: nil,
            quantizations: quantizations.isEmpty ? nil : quantizations,
            maxPrice: maxPrice,
            only: onlyProviders,
            ignore: nil,
            sort: trimmedSort.isEmpty ? nil : trimmedSort
        )
    }

    private func openRouterAvailableProviderSlugs(
        for model: String,
        catalogModel: SimpleModel?
    ) async -> [String] {
        let fromEndpoints = await modelService.getAvailableProviders(for: model)
        let endpointSlugs = normalizedOpenRouterSlugs(fromEndpoints)
        if !endpointSlugs.isEmpty {
            return endpointSlugs
        }
        if let catalogModel, !catalogModel.availableProviders.isEmpty {
            return normalizedOpenRouterSlugs(catalogModel.availableProviders)
        }
        return []
    }

    private func openRouterAvailableQuantizations(catalogModel: SimpleModel?) -> [String] {
        guard let catalogModel, !catalogModel.availableQuantizations.isEmpty else {
            return []
        }
        return normalizedOpenRouterSlugs(catalogModel.availableQuantizations)
    }

    private func normalizedOpenRouterSlugs(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    private func filterCompatibleOpenRouterSlugs(_ preferred: [String], available: [String]) -> [String] {
        guard !available.isEmpty else { return [] }
        let availableSet = Set(available.map { $0.lowercased() })
        return preferred.filter { availableSet.contains($0.lowercased()) }
    }

    private func resolveCompatibleOpenRouterProviderSlugs(
        _ preferred: [String],
        available: [String]
    ) -> [String] {
        filterCompatibleOpenRouterSlugs(preferred, available: available)
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
        var usage: ProviderUsage?
        var error: Error?
    }

    private func generateDualSideResponse(
        request: ProviderRequest,
        provider: String,
        model: String
    ) async -> DualSideResult {
        do {
            let response = try await providers.generate(request: request, providerID: provider)
            return DualSideResult(
                text: response.text,
                reasoning: response.reasoningSummary,
                usage: response.usage,
                error: nil
            )
        } catch {
            return DualSideResult(
                text: L10n.format("エラー: %@", error.localizedDescription),
                reasoning: nil,
                usage: nil,
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
            ProviderRequestMessage(
                role: $0.role,
                content: $0.text,
                attachments: $0.attachments,
                reasoningContent: $0.thinkingStream
            )
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
