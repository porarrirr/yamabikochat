import Foundation
import Combine

@MainActor
final class ConversationListViewModel: ObservableObject {
    @Published private(set) var conversations: [ConversationListEntry] = []
    @Published private(set) var projects: [ProjectListEntry] = []
    @Published var searchQuery: String = ""
    @Published var selectedProjectId: Int64?
    @Published var errorMessage: String?
    @Published var isSelectionMode: Bool = false
    @Published var selectedConversationIds: Set<Int64> = []

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

        repository.observeProjects()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] projects in
                self?.projects = projects
                guard let selected = self?.selectedProjectId else { return }
                if !projects.contains(where: { $0.id == selected }) {
                    self?.selectedProjectId = nil
                }
            }
            .store(in: &cancellables)

        do {
            _ = try repository.ensureInitialConversation()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createConversation(secret: Bool = false, projectId: Int64? = nil) -> Int64? {
        guard let repository else { return nil }
        do {
            let targetProjectId = projectId ?? selectedProjectId
            if secret {
                return try repository.createSecretConversation(projectId: targetProjectId)
            }
            return try repository.createConversation(projectId: targetProjectId)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func createProject(title: String, instructions: String?) -> Int64? {
        guard let repository else { return nil }
        do {
            let id = try repository.createProject(title: title, instructions: instructions)
            selectedProjectId = id
            return id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func assignConversation(id: Int64, to projectId: Int64?) {
        guard let repository else { return }
        do {
            try repository.assignConversationToProject(conversationId: id, projectId: projectId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectProject(_ id: Int64?) {
        selectedProjectId = id
    }

    func resetProjectFilterForNonProjectConversation(conversationId: Int64) {
        guard selectedProjectId != nil else { return }

        if let entry = conversations.first(where: { $0.id == conversationId }) {
            if entry.projectId == nil {
                selectedProjectId = nil
            }
            return
        }

        guard let repository else { return }
        if let conversation = try? repository.conversation(id: conversationId),
           conversation.projectId == nil {
            selectedProjectId = nil
        }
    }

    func projectConversationCount(projectId: Int64) -> Int {
        if let repository,
           let count = try? repository.projectConversationCount(projectId: projectId) {
            return count
        }
        return conversations.reduce(into: 0) { count, entry in
            if entry.projectId == projectId {
                count += 1
            }
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

    func deleteProject(id: Int64, mode: ProjectDeletionMode) {
        guard let repository else { return }
        do {
            try repository.deleteProject(id: id, mode: mode)
            if selectedProjectId == id {
                selectedProjectId = nil
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var filteredConversations: [ConversationListEntry] {
        let base: [ConversationListEntry]
        if let selectedProjectId {
            base = conversations.filter { $0.projectId == selectedProjectId }
        } else {
            base = conversations
        }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return base }
        return base.filter { entry in
            entry.title.localizedCaseInsensitiveContains(query) ||
                (entry.lastMessagePreview?.localizedCaseInsensitiveContains(query) ?? false) ||
                (entry.projectTitle?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    // MARK: - Selection Mode

    var isAllSelected: Bool {
        let filtered = filteredConversations
        return !filtered.isEmpty && filtered.allSatisfy { selectedConversationIds.contains($0.id) }
    }

    func toggleSelectionMode() {
        isSelectionMode.toggle()
        if !isSelectionMode {
            selectedConversationIds.removeAll()
        }
    }

    func exitSelectionMode() {
        isSelectionMode = false
        selectedConversationIds.removeAll()
    }

    func toggleSelection(id: Int64) {
        if selectedConversationIds.contains(id) {
            selectedConversationIds.remove(id)
        } else {
            selectedConversationIds.insert(id)
        }
    }

    func selectAll() {
        selectedConversationIds = Set(filteredConversations.map(\.id))
    }

    func deselectAll() {
        selectedConversationIds.removeAll()
    }

    func deleteSelectedConversations() {
        guard let repository, !selectedConversationIds.isEmpty else { return }
        do {
            try repository.deleteConversations(ids: selectedConversationIds)
        } catch {
            errorMessage = error.localizedDescription
        }
        exitSelectionMode()
    }
}
