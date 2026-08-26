import Combine
import Foundation

@MainActor
final class ChatWorkspaceStore: ObservableObject {
    @Published var presentedRoute: ChatWorkspaceRoute?

    func present(_ route: ChatWorkspaceRoute) {
        presentedRoute = route
    }

    func dismiss() {
        presentedRoute = nil
    }
}

@MainActor
final class ChatComposerStore: ObservableObject {
    /// Deprecated: Input text is now owned by ChatViewModel (@Published inputText).
    /// Kept for backward compatibility; not used as Source of Truth.
    @Published var inputText = ""
    @Published var attachments: [AttachmentDraft] = []
    @Published var isSpeechRecording = false
    @Published var canAttachImages = false

    var hasContent: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !attachments.isEmpty
    }
}

struct AttachmentDraft: Identifiable, Equatable {
    let id: UUID
    var url: URL
    var displayName: String

    init(url: URL, displayName: String? = nil) {
        id = UUID()
        self.url = url
        self.displayName = displayName ?? url.lastPathComponent
    }
}
