import Foundation
import GRDB

final class AppServices {
    static let shared = AppServices()

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

    private init() {
        DiagnosticsLogger.initialize()
        do {
            dbQueue = try AppDatabase.makeDatabaseQueue()
        } catch {
            fatalError("Database initialization failed: \(error)")
        }

        credentialStore = KeychainStore()
        settingsRepository = SettingsRepository(dbQueue: dbQueue)
        conversationRepository = ConversationRepository(dbQueue: dbQueue)
        attachmentRepository = AttachmentRepository()
        skillRepository = AgentSkillRepository()
        openRouterModelService = OpenRouterModelService(credentialStore: credentialStore)
        let localTools = LocalToolRegistry(
            executors: [WebSearchTool(), FetchUrlTool()] + AgentSkillTools.executors(repository: skillRepository)
        )
        requestSettingsResolver = ProviderRequestSettingsResolver(
            modelService: openRouterModelService,
            skillRepository: skillRepository,
            localToolRegistry: localTools
        )
        modelsDevCatalogRepository = ModelsDevCatalogRepository()
        codexAuthRepository = CodexAuthRepository(credentialStore: credentialStore)
        superGrokAuthRepository = SuperGrokAuthRepository(credentialStore: credentialStore)
        providerGateway = ProviderGateway(
            settingsRepository: settingsRepository,
            credentialStore: credentialStore,
            codexAuthRepository: codexAuthRepository,
            superGrokAuthRepository: superGrokAuthRepository,
            modelsDevCatalogRepository: modelsDevCatalogRepository,
            localTools: localTools
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

        do {
            try chatRepository.purgeSecretConversations()
        } catch {
            DiagnosticsLogger.log("Purge secret conversations failed", category: .app, error: error)
        }
    }
}
