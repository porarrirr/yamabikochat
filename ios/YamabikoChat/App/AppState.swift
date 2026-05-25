import Foundation
import Combine

struct ShareImportDraft: Equatable {
    let conversationID: Int64
    let text: String
}

@MainActor
final class AppState: ObservableObject {
    @Published var selectedConversationID: Int64?
    @Published private(set) var shareImportDraft: ShareImportDraft?
    @Published var isConversationHistoryPresented = false
    @Published private(set) var conversationSidebarRevealGeneration = 0

    func requestConversationSidebarReveal() {
        conversationSidebarRevealGeneration += 1
    }

    @discardableResult
    func importSharePayload(from store: SharePayloadStore, repository: ChatRepository) -> Bool {
        guard let payload = store.consumeLatest() else { return false }
        do {
            let conversationID = try repository.createConversation(projectId: nil)
            shareImportDraft = ShareImportDraft(conversationID: conversationID, text: payload.text)
            selectedConversationID = conversationID
            DiagnosticsLogger.log(
                "Imported share into new conversation",
                category: .app,
                metadata: ["conversationId": "\(conversationID)"]
            )
            return true
        } catch {
            DiagnosticsLogger.log(
                "Share import failed",
                category: .app,
                error: error
            )
            return false
        }
    }

    func shareImportText(for conversationID: Int64) -> String? {
        guard let draft = shareImportDraft, draft.conversationID == conversationID else { return nil }
        return draft.text
    }

    func clearShareImportDraft(for conversationID: Int64) {
        guard shareImportDraft?.conversationID == conversationID else { return }
        shareImportDraft = nil
    }
}
