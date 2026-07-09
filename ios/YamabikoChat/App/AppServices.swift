import Foundation
import GRDB

final class AppServices {
    static let shared = AppServices()

    let dbQueue: DatabaseQueue
    let credentialStore: SecureCredentialStore

    let settingsRepository: SettingsRepository
    let conversationRepository: ConversationRepository
    let attachmentRepository: AttachmentRepository
    let openRouterModelService: OpenRouterModelService
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
        openRouterModelService = OpenRouterModelService(credentialStore: credentialStore)
        codexAuthRepository = CodexAuthRepository(credentialStore: credentialStore)
        superGrokAuthRepository = SuperGrokAuthRepository(credentialStore: credentialStore)
        providerGateway = ProviderGateway(
            settingsRepository: settingsRepository,
            credentialStore: credentialStore,
            superGrokAuthRepository: superGrokAuthRepository
        )
        fusionTraceStore = FusionTraceStore(dbQueue: dbQueue)
        fusionService = FusionService(
            settingsRepository: settingsRepository,
            providerGateway: providerGateway,
            pricingRepository: LiteLlmPricingRepository(),
            traceStore: fusionTraceStore
        )
        chatRepository = ChatRepository(
            conversations: conversationRepository,
            settings: settingsRepository,
            providers: providerGateway,
            credentialStore: credentialStore,
            modelService: openRouterModelService,
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
