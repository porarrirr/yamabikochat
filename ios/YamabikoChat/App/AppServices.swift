import Foundation
import GRDB

final class AppServices {
    private static let resolutionLock = NSLock()
    private static var resolvedInstance: AppServices?

    static func resolve() throws -> AppServices {
        resolutionLock.lock()
        defer { resolutionLock.unlock() }
        if let resolvedInstance { return resolvedInstance }
        let instance = try AppServices()
        resolvedInstance = instance
        return instance
    }

    let dbQueue: DatabaseQueue
    let credentialStore: SecureCredentialStore

    let settingsRepository: SettingsRepository
    let conversationRepository: ConversationRepository
    let attachmentRepository: AttachmentRepository
    let skillRepository: AgentSkillRepository
    let openRouterModelService: OpenRouterModelService
    let requestSettingsResolver: ProviderRequestSettingsResolver
    let modelsDevCatalogRepository: ModelsDevCatalogRepository
    let codexAuthRepository: CodexAuthRepository
    let superGrokAuthRepository: SuperGrokAuthRepository
    let providerGateway: ProviderGateway
    let fusionTraceStore: FusionTraceStore
    let fusionService: FusionService
    let chatRepository: ChatRepository
    let sharePayloadStore: SharePayloadStore
    let userQuestionCoordinator: UserQuestionCoordinator

    private init() throws {
        DiagnosticsLogger.initialize()
        dbQueue = try AppDatabase.makeDatabaseQueue()

        credentialStore = KeychainStore()
        settingsRepository = SettingsRepository(dbQueue: dbQueue)
        conversationRepository = ConversationRepository(dbQueue: dbQueue)
        attachmentRepository = AttachmentRepository()
        do {
            try EditorWorkspaceStore.shared.deleteOrphans(
                validSessionIDs: try conversationRepository.allConversationIDs().map(String.init)
            )
        } catch {
            DiagnosticsLogger.log("Editor workspace orphan cleanup failed", category: .app, error: error)
        }
        let repository = AgentSkillRepository()
        skillRepository = repository
        openRouterModelService = OpenRouterModelService(credentialStore: credentialStore)
        Task { [openRouterModelService] in
            _ = await openRouterModelService.getAvailableModels()
        }
        userQuestionCoordinator = UserQuestionCoordinator()
        let askUserQuestionTool = AskUserQuestionTool(coordinator: userQuestionCoordinator)
        // The resolver receives only the client web tools. Agent Skill tools are
        // appended by the resolver itself; the Pi runtime registry below includes
        // their executors so `activate_skill` / `read_skill_resource` calls can be
        // dispatched without sending duplicate tool definitions to providers.
        let pythonTool = PythonExecuteTool(attachments: attachmentRepository)
        let editorTool = StrReplaceEditorTool(attachments: attachmentRepository)
        let clientWebTools = LocalToolRegistry(
            executors: [WebSearchTool(), FetchUrlTool(), pythonTool, editorTool, askUserQuestionTool]
        )
        // Recreate per request: WebSearch/FetchUrl are stateless, pythonTool is reused
        // (tied to attachmentRepository), and AgentSkill executors snapshot latest enabledSkills.
        let makeLocalTools: @Sendable () -> LocalToolRegistry = { [repository, pythonTool, editorTool, askUserQuestionTool] in
            LocalToolRegistry(
                executors: [WebSearchTool(), FetchUrlTool(), pythonTool, editorTool, askUserQuestionTool] + AgentSkillTools.executors(repository: repository)
            )
        }
        let localTools = makeLocalTools()
        modelsDevCatalogRepository = ModelsDevCatalogRepository()
        let modelsDevCredentials = credentialStore
        requestSettingsResolver = ProviderRequestSettingsResolver(
            modelService: openRouterModelService,
            skillRepository: skillRepository,
            modelsDevCatalogRepository: modelsDevCatalogRepository,
            localToolRegistry: clientWebTools,
            modelsDevReasoningEffort: { providerID, modelID in
                try? modelsDevCredentials.readSecret(
                    key: ModelsDevReasoningPreference.storageKey(providerID: providerID, modelID: modelID)
                )
            }
        )
        codexAuthRepository = CodexAuthRepository(credentialStore: credentialStore)
        superGrokAuthRepository = SuperGrokAuthRepository(credentialStore: credentialStore)
        providerGateway = ProviderGateway(
            settingsRepository: settingsRepository,
            credentialStore: credentialStore,
            codexAuthRepository: codexAuthRepository,
            superGrokAuthRepository: superGrokAuthRepository,
            modelsDevCatalogRepository: modelsDevCatalogRepository,
            openRouterModelService: openRouterModelService,
            localTools: localTools,
            localToolFactory: makeLocalTools
        )
        fusionTraceStore = FusionTraceStore(dbQueue: dbQueue)
        fusionService = FusionService(
            settingsRepository: settingsRepository,
            providerGateway: providerGateway,
            pricingRepository: LiteLlmPricingRepository(),
            traceStore: fusionTraceStore,
            requestSettingsResolver: requestSettingsResolver,
            skillRepository: skillRepository
        )
        chatRepository = ChatRepository(
            conversations: conversationRepository,
            settings: settingsRepository,
            providers: providerGateway,
            credentialStore: credentialStore,
            modelService: openRouterModelService,
            skillRepository: skillRepository,
            requestSettingsResolver: requestSettingsResolver,
            codexAuthRepository: codexAuthRepository,
            superGrokAuthRepository: superGrokAuthRepository,
            fusionService: fusionService,
            fusionTraceStore: fusionTraceStore
        )
        sharePayloadStore = SharePayloadStore()

    }
}
