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
    @Published var attachments: [AttachmentDraft] = []
    @Published var isSpeechRecording = false
    @Published var canAttachImages = false
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
