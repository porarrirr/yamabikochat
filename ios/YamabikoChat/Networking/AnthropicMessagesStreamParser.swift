import Foundation

/// Parses Anthropic-style messages API stream events (`content_block_delta`, `message_stop`, …).
enum AnthropicMessagesStreamParser {
    static func event(
        from root: [String: Any],
        fullText: inout String,
        fullReasoning: inout String
    ) -> ProviderStreamEvent? {
        let type = (root["type"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch type {
        case "content_block_delta":
            guard let delta = root["delta"] as? [String: Any] else { return nil }
            switch (delta["type"] as? String)?.lowercased() {
            case "text_delta":
                guard let incoming = delta["text"] as? String, !incoming.isEmpty else { return nil }
                let textDelta = StreamDeltaAccumulator.incrementalDelta(buffer: fullText, incoming: incoming)
                guard !textDelta.isEmpty else { return nil }
                fullText += textDelta
                return .textDelta(textDelta)
            case "thinking_delta":
                guard let incoming = delta["thinking"] as? String, !incoming.isEmpty else { return nil }
                fullReasoning += incoming
                return .reasoningDelta(incoming)
            default:
                return nil
            }
        case "message_stop":
            return .completed(
                ProviderResponse(
                    text: fullText,
                    reasoningSummary: fullReasoning.isEmpty ? nil : fullReasoning,
                    raw: nil,
                    usage: nil
                )
            )
        default:
            return nil
        }
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
