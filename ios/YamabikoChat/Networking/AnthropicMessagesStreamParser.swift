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
        case "content_block_start":
            guard let block = root["content_block"] as? [String: Any] else { return nil }
            let blockType = (block["type"] as? String)?.lowercased()
            guard blockType == "tool_use" else { return nil }
            let index = (root["index"] as? NSNumber)?.intValue ?? 0
            let inputJSON: String
            if let input = block["input"],
               !((input as? [String: Any])?.isEmpty ?? false),
               JSONSerialization.isValidJSONObject(input),
               let data = try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]) {
                inputJSON = String(decoding: data, as: UTF8.self)
            } else {
                inputJSON = ""
            }
            return .toolCallDelta(
                ToolCallDelta(
                    index: index,
                    id: block["id"] as? String,
                    name: block["name"] as? String,
                    argumentsFragment: inputJSON
                )
            )
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
                let reasoningDelta = StreamDeltaAccumulator.incrementalDelta(buffer: fullReasoning, incoming: incoming)
                guard !reasoningDelta.isEmpty else { return nil }
                fullReasoning += reasoningDelta
                return .reasoningDelta(reasoningDelta)
            case "input_json_delta":
                guard let partialJSON = delta["partial_json"] as? String, !partialJSON.isEmpty else {
                    return nil
                }
                return .toolCallDelta(
                    ToolCallDelta(
                        index: (root["index"] as? NSNumber)?.intValue ?? 0,
                        argumentsFragment: partialJSON
                    )
                )
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
