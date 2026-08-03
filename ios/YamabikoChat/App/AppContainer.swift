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
    let openRouterModelService: OpenRouterModelService
    let modelsDevCatalogRepository: ModelsDevCatalogRepository
    let codexAuthRepository: CodexAuthRepository
    let providerGateway: ProviderGateway
    let fusionService: FusionService
    let chatRepository: ChatRepository
    let sharePayloadStore: SharePayloadStore

    init(services: AppServices = .shared) {
        dbQueue = services.dbQueue
        credentialStore = services.credentialStore
        settingsRepository = services.settingsRepository
        conversationRepository = services.conversationRepository
        attachmentRepository = services.attachmentRepository
        openRouterModelService = services.openRouterModelService
        modelsDevCatalogRepository = services.modelsDevCatalogRepository
        codexAuthRepository = services.codexAuthRepository
        providerGateway = services.providerGateway
        fusionService = services.fusionService
        chatRepository = services.chatRepository
        sharePayloadStore = services.sharePayloadStore

        AppStoreScreenshotDemoSeeder.seedIfNeeded(
            chatRepository: chatRepository,
            conversations: conversationRepository
        )
    }
}
