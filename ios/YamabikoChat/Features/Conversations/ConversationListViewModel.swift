import Foundation
import Combine

@MainActor
final class ConversationListViewModel: ObservableObject {
    @Published private(set) var conversations: [ConversationListEntry] = []
    @Published var searchQuery: String = ""
    @Published var errorMessage: String?

    private var repository: ChatRepository?
    private var cancellables: Set<AnyCancellable> = []

    func bind(repository: ChatRepository) {
        guard self.repository == nil else { return }
        self.repository = repository

        repository.observeConversationList()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                self?.conversations = $0
            }
            .store(in: &cancellables)

        do {
            _ = try repository.ensureInitialConversation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createConversation(secret: Bool = false) -> Int64? {
        guard let repository else { return nil }
        do {
            if secret {
                return try repository.createSecretConversation()
            }
            return try repository.createConversation()
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func deleteConversation(id: Int64) {
        guard let repository else { return }
        do {
            try repository.deleteConversation(id: id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var filteredConversations: [ConversationListEntry] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return conversations }
        return conversations.filter { entry in
            entry.title.localizedCaseInsensitiveContains(query) ||
                (entry.lastMessagePreview?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }
}
