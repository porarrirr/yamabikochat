import Foundation
import Combine

struct ShareImportDraft: Equatable {
    let conversationID: Int64
    let text: String
}

@MainActor
final class AppState: ObservableObject {
    @Published var selectedConversationID: Int64?
    @Published private var shareImportDrafts: [Int64: String] = [:]
    @Published var isConversationHistoryPresented = false
    @Published private(set) var conversationSidebarRevealGeneration = 0

    var shareImportDraft: ShareImportDraft? {
        guard let conversationID = selectedConversationID,
              let text = shareImportDrafts[conversationID] else { return nil }
        return ShareImportDraft(conversationID: conversationID, text: text)
    }

    func requestConversationSidebarReveal() {
        conversationSidebarRevealGeneration += 1
    }

    @discardableResult
    func importSharePayload(from store: SharePayloadStore, repository: ChatRepository) -> Bool {
        guard let pending = store.loadLatest() else { return false }
        do {
            guard let conversationID = try repository.importShare(payloadID: pending.id, text: pending.payload.text) else {
                return store.discard(pending)
            }
            shareImportDrafts[conversationID] = pending.payload.text
            selectedConversationID = conversationID
            if !store.discard(pending) {
                DiagnosticsLogger.log(
                    "Committed share import but could not remove the matching pending payload",
                    level: .warning,
                    category: .app,
                    metadata: ["conversationId": "\(conversationID)"]
                )
                return false
            }
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
        shareImportDrafts[conversationID]
    }

    func clearShareImportDraft(for conversationID: Int64) {
        shareImportDrafts.removeValue(forKey: conversationID)
    }
}
