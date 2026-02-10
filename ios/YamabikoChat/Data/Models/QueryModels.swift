import Foundation

struct ConversationListEntry: Identifiable, Equatable {
    var id: Int64
    var title: String
    var updatedAtMs: Int64
    var lastMessagePreview: String?
    var isSecret: Bool
}

struct ChatMessageSummary: Identifiable, Equatable {
    var id: Int64
    var role: String
    var textPreview: String
    var createdAtMs: Int64
    var hasAttachments: Bool
}

struct FullChatMessage: Identifiable, Equatable {
    var id: Int64
    var message: ChatMessage
    var thinkingStream: String?
}
