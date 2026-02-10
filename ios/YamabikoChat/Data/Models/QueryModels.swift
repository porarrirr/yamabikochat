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

struct ProviderHistoryMessage: Equatable {
    var messageId: Int64
    var role: String
    var text: String
    var attachments: [String]
}

struct FullChatMessage: Identifiable, Equatable {
    var id: Int64
    var message: ChatMessage
    var thinkingStream: String?
    var variants: [ChatMessageVariant]

    var variantCount: Int {
        1 + variants.count
    }

    var normalizedSelectedVariantIndex: Int {
        let upperBound = max(0, variantCount - 1)
        return min(max(0, message.selectedVariantIndex), upperBound)
    }

    var selectedVariantOrdinal: Int {
        normalizedSelectedVariantIndex + 1
    }

    var canSelectPreviousVariant: Bool {
        normalizedSelectedVariantIndex > 0
    }

    var canSelectNextVariant: Bool {
        normalizedSelectedVariantIndex < variantCount - 1
    }

    var selectedVariant: ChatMessageVariant? {
        let selected = normalizedSelectedVariantIndex
        guard selected > 0 else { return nil }
        return variants.first(where: { $0.variantIndex == selected })
    }

    var displayText: String {
        selectedVariant?.text ?? message.text
    }

    var displayAttachmentsJSON: String {
        selectedVariant?.attachmentsJSON ?? message.attachmentsJSON
    }

    var displayThinkingStream: String? {
        selectedVariant?.thinkingStream ?? thinkingStream
    }
}
