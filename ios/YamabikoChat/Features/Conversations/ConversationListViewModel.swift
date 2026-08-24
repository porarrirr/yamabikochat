import Foundation
import Combine

@MainActor
final class ConversationListViewModel: ObservableObject {
    @Published private(set) var conversations: [ConversationListEntry] = []
    @Published private(set) var filteredConversations: [ConversationListEntry] = []
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
                self?.rebuildFilteredConversations()
                self?.pruneSelectionToVisibleConversations()
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

        Publishers.CombineLatest($searchQuery.removeDuplicates(), $selectedProjectId.removeDuplicates())
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _, _ in
                self?.rebuildFilteredConversations()
                self?.pruneSelectionToVisibleConversations()
            }
            .store(in: &cancellables)
    }

    func createConversation(secret: Bool = false, projectId: Int64? = nil) -> Int64? {
        guard let repository else { return nil }
        do {
            let targetProjectId = projectId ?? selectedProjectId
            let conversationID: Int64
            if secret {
                conversationID = try repository.createSecretConversation(projectId: targetProjectId)
            } else {
                conversationID = try repository.createConversation(projectId: targetProjectId)
            }
            errorMessage = nil
            return conversationID
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func createConversation(initialMessage: String, projectId: Int64) -> Int64? {
        guard let repository else { return nil }
        do {
            let conversationID = try repository.createConversationWithPendingInitialMessage(
                initialMessage,
                projectId: projectId
            )
            errorMessage = nil
            return conversationID
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func createProject(title: String, instructions: String?) -> Int64? {
        guard let repository else { return nil }
        do {
            let id = try repository.createProject(title: title, instructions: instructions)
            errorMessage = nil
            return id
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    @discardableResult
    func updateProject(
        id: Int64,
        title: String,
        instructions: String?,
        iconName: String? = nil,
        colorHex: String? = nil
    ) -> Bool {
        guard let repository else { return false }
        do {
            try repository.updateProject(
                id: id,
                title: title,
                instructions: instructions,
                iconName: iconName,
                colorHex: colorHex
            )
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    @discardableResult
    func updateProjectInstructions(id: Int64, instructions: String?) -> Bool {
        guard let repository else { return false }
        do {
            try repository.updateProjectInstructions(id: id, instructions: instructions)
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
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

    @discardableResult
    func deleteProject(id: Int64, mode: ProjectDeletionMode) -> Bool {
        guard let repository else { return false }
        do {
            try repository.deleteProject(id: id, mode: mode)
            if selectedProjectId == id {
                selectedProjectId = nil
            }
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func rebuildFilteredConversations() {
        let base: [ConversationListEntry]
        if let selectedProjectId {
            base = conversations.filter { $0.projectId == selectedProjectId }
        } else {
            base = conversations
        }

        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered: [ConversationListEntry]
        if query.isEmpty {
            filtered = base
        } else {
            filtered = base.filter { entry in
            entry.title.localizedCaseInsensitiveContains(query) ||
                (entry.lastMessagePreview?.localizedCaseInsensitiveContains(query) ?? false) ||
                (entry.projectTitle?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        guard filteredConversations != filtered else { return }
        filteredConversations = filtered
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
            exitSelectionMode()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func pruneSelectionToVisibleConversations() {
        guard isSelectionMode else { return }
        selectedConversationIds.formIntersection(filteredConversations.map(\.id))
    }
}
