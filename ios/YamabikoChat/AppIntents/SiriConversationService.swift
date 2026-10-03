import Foundation
import Combine

/// Shared navigation boundary for foreground App Intents, including cold launches.
@MainActor
final class SiriNavigation: ObservableObject {
    enum Request: Equatable {
        case conversation(Int64)
        case search(String)
    }

    static let shared = SiriNavigation()
    @Published private(set) var pendingRequest: Request?

    func request(_ request: Request) {
        pendingRequest = request
    }

    func consume() -> Request? {
        let request = pendingRequest
        pendingRequest = nil
        return request
    }
}

enum SiriConversationError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        L10n.text("Siri: 会話が見つからないか、利用できません。")
    }
}

enum SiriConversationService {
    static func conversationID(from url: URL) -> Int64? {
        guard url.scheme == "yamabikochat", url.host == "conversation",
              url.query == nil, url.fragment == nil,
              url.pathComponents.count == 2,
              let id = Int64(url.lastPathComponent), id > 0 else { return nil }
        return id
    }

    static func resolve(id: Int64, repository: ConversationRepository) throws -> ConversationEntity {
        guard let conversation = try repository.siriConversations(ids: [id]).first,
              let entity = ConversationEntity(conversation) else {
            throw SiriConversationError.unavailable
        }
        return entity
    }

    static func ask(prompt: String, save: Bool) async throws -> ShortcutRunResult {
        let services = try AppServices.resolve()
        let settings = try services.settingsRepository.load()
        return try await ask(prompt: prompt, save: save, settings: settings, repository: services.chatRepository)
    }

    static func ask(prompt: String, save: Bool, settings: AppSettings, repository: ChatRepository) async throws -> ShortcutRunResult {
        do {
            return try await repository.runShortcut(
                prompt: prompt, provider: settings.apiProvider, model: settings.currentModel(),
                saveToNewConversation: save
            )
        } catch {
            DiagnosticsLogger.log("Siri question failed", category: .chat,
                                  metadata: ["provider": settings.apiProvider, "model": settings.currentModel()],
                                  error: error)
            throw error
        }
    }
}
