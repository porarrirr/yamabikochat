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
    let codexAuthRepository: CodexAuthRepository
    let geminiAuthRepository: GeminiAuthRepository
    let providerGateway: ProviderGateway
    let chatRepository: ChatRepository
    let sharePayloadStore: SharePayloadStore

    init() {
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
        geminiAuthRepository = GeminiAuthRepository(credentialStore: credentialStore)
        providerGateway = ProviderGateway(
            settingsRepository: settingsRepository,
            credentialStore: credentialStore,
            geminiAuthRepository: geminiAuthRepository
        )
        chatRepository = ChatRepository(
            conversations: conversationRepository,
            settings: settingsRepository,
            providers: providerGateway,
            credentialStore: credentialStore,
            modelService: openRouterModelService,
            codexAuthRepository: codexAuthRepository,
            geminiAuthRepository: geminiAuthRepository
        )
        sharePayloadStore = SharePayloadStore()
    }
}
