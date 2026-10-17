import Combine

/// Reconnects a conversation's screen to its existing run after navigation.
@MainActor
final class ChatViewModelStore: ObservableObject {
    private struct Entry {
        weak var viewModel: ChatViewModel?
    }

    private var entries: [Int64: Entry] = [:]

    func viewModel(conversationID: Int64) -> ChatViewModel {
        entries = entries.filter { $0.value.viewModel != nil }
        if let viewModel = entries[conversationID]?.viewModel {
            return viewModel
        }

        let viewModel = ChatViewModel(conversationID: conversationID)
        // The screen owns an idle model; an active task retains its model until
        // completion. Weak entries avoid keeping every visited timeline in memory.
        entries[conversationID] = Entry(viewModel: viewModel)
        return viewModel
    }

    func removeConversations(ids: Set<Int64>) {
        for id in ids {
            let viewModel = entries.removeValue(forKey: id)?.viewModel
            viewModel?.cancelActiveRun()
            if viewModel?.isAutoConversationRunning == true || viewModel?.isAutoConversationPaused == true {
                viewModel?.stopAutoConversation()
            }
        }
    }
}
