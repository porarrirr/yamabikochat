import Foundation
import Combine
import GRDB

@MainActor
final class AppContainer: ObservableObject {
    let dbQueue: DatabaseQueue
    let credentialStore: SecureCredentialStore

    let settingsRepository: SettingsRepository
    let conversationRepository: ConversationRepository
    let attachmentRepository: AttachmentRepository
    let skillRepository: AgentSkillRepository
    let openRouterModelService: OpenRouterModelService
    let modelsDevCatalogRepository: ModelsDevCatalogRepository
    let codexAuthRepository: CodexAuthRepository
    let providerGateway: ProviderGateway
    let chatRepository: ChatRepository
    let sharePayloadStore: SharePayloadStore
    private let conversationSpotlightIndexer: ConversationSpotlightIndexer
    let userQuestionCoordinator: UserQuestionCoordinator

    init(services: AppServices) {
        conversationSpotlightIndexer = ConversationSpotlightIndexer(repository: services.conversationRepository)
        dbQueue = services.dbQueue
        credentialStore = services.credentialStore
        settingsRepository = services.settingsRepository
        conversationRepository = services.conversationRepository
        attachmentRepository = services.attachmentRepository
        skillRepository = services.skillRepository
        openRouterModelService = services.openRouterModelService
        modelsDevCatalogRepository = services.modelsDevCatalogRepository
        codexAuthRepository = services.codexAuthRepository
        providerGateway = services.providerGateway
        chatRepository = services.chatRepository
        sharePayloadStore = services.sharePayloadStore
        userQuestionCoordinator = services.userQuestionCoordinator

        #if DEBUG
        AppStoreScreenshotDemoSeeder.seedIfNeeded(
            chatRepository: chatRepository,
            conversations: conversationRepository
        )
        #endif
    }
}
