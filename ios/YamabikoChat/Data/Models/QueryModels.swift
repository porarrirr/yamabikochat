import Foundation

struct ConversationListEntry: Identifiable, Equatable {
    var id: Int64
    var title: String
    var updatedAtMs: Int64
    var lastMessagePreview: String?
    var isSecret: Bool
    var projectId: Int64?
    var projectTitle: String?
}

struct ProjectListEntry: Identifiable, Equatable {
    var id: Int64
    var title: String
    var iconName: String
    var colorHex: String
    var instructions: String?
    var updatedAtMs: Int64
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
    var thinkingStream: String?
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
        displayContent.text
    }

    var displayAttachmentsJSON: String {
        selectedVariant?.attachmentsJSON ?? message.attachmentsJSON
    }

    var displayThinkingStream: String? {
        displayContent.thinking
    }

    private var displayContent: (text: String, thinking: String?) {
        let sourceText = selectedVariant?.text ?? message.text
        let persistedThinking = selectedVariant?.thinkingStream ?? thinkingStream

        guard message.role == "model" else {
            let thinking = persistedThinking?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (text: sourceText, thinking: thinking?.isEmpty == true ? nil : thinking)
        }

        let split = splitReasoningBlocks(from: sourceText)

        var thinkingParts: [String] = []
        for value in [persistedThinking, split.reasoning] {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let trimmed, !trimmed.isEmpty else { continue }
            if !thinkingParts.contains(trimmed) {
                thinkingParts.append(trimmed)
            }
        }
        let combinedThinking = thinkingParts.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let thinking = combinedThinking.isEmpty ? nil : combinedThinking
        return (text: split.content, thinking: thinking)
    }
}

private func splitReasoningBlocks(from input: String) -> (content: String, reasoning: String) {
    guard !input.isEmpty else {
        return (content: "", reasoning: "")
    }

    var working = input
    var extracted: [String] = []

    let patterns: [(pattern: String, captureGroup: Int)] = [
        ("(?is)<think>(.*?)</think>", 1),
        ("(?is)<thinking>(.*?)</thinking>", 1),
        ("(?is)<reasoning>(.*?)</reasoning>", 1),
        ("(?is)```\\s*(thinking|reasoning|analysis|thoughts)\\s*\\R(.*?)```", 2),
    ]

    for pattern in patterns {
        guard let regex = try? NSRegularExpression(pattern: pattern.pattern) else { continue }
        let range = NSRange(working.startIndex..., in: working)

        for match in regex.matches(in: working, range: range) {
            guard let capturedRange = Range(match.range(at: pattern.captureGroup), in: working) else { continue }
            extracted.append(String(working[capturedRange]))
        }

        working = regex.stringByReplacingMatches(in: working, range: range, withTemplate: "")
    }

    return (
        content: working.trimmingCharacters(in: .whitespacesAndNewlines),
        reasoning: extracted
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    )
}
