import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var selectedConversationID: Int64?
    @Published var pendingSharedText: String?
    @Published var isConversationHistoryPresented = false
    @Published private(set) var conversationSidebarRevealGeneration = 0

    func requestConversationSidebarReveal() {
        conversationSidebarRevealGeneration += 1
    }

    func consumeSharePayload(from store: SharePayloadStore) {
        guard let payload = store.consumeLatest() else { return }
        pendingSharedText = payload.text
    }

    func consumePendingText() -> String? {
        defer { pendingSharedText = nil }
        return pendingSharedText
    }
}
