import Foundation

/// Parses OpenAI-style chat completion stream chunks (`choices[].delta` / `message`).
enum OpenAICompatibleStreamParser {
    static func events(
        fromPayload dataChunk: String,
        fullText: inout String,
        fullReasoning: inout String
    ) -> [ProviderStreamEvent] {
        guard let root = try? JSONSerialization.jsonObject(with: Data(dataChunk.utf8)) as? [String: Any],
              let choices = root["choices"] as? [[String: Any]]
        else {
            return []
        }
        return events(fromChoices: choices, fullText: &fullText, fullReasoning: &fullReasoning)
    }

    static func events(
        fromChoices choices: [[String: Any]],
        fullText: inout String,
        fullReasoning: inout String
    ) -> [ProviderStreamEvent] {
        var events: [ProviderStreamEvent] = []
        for choice in choices {
            if let delta = choice["delta"] as? [String: Any] {
                events.append(contentsOf: deltaEvents(from: delta, fullText: &fullText, fullReasoning: &fullReasoning))
            }
            if let message = choice["message"] as? [String: Any] {
                events.append(contentsOf: deltaEvents(from: message, fullText: &fullText, fullReasoning: &fullReasoning))
            }
            if let incoming = choice["text"] as? String, !incoming.isEmpty {
                events.append(contentsOf: appendTextDelta(incoming, buffer: &fullText))
            }
        }
        return events
    }

    private static func deltaEvents(
        from object: [String: Any],
        fullText: inout String,
        fullReasoning: inout String
    ) -> [ProviderStreamEvent] {
        var events: [ProviderStreamEvent] = []
        if let incoming = reasoningText(from: object) {
            events.append(contentsOf: appendReasoningDelta(incoming, buffer: &fullReasoning))
        }
        let incomingContent = openAICompatibleText(from: object["content"])
        if !incomingContent.isEmpty {
            events.append(contentsOf: appendTextDelta(incomingContent, buffer: &fullText))
        }
        if let toolCalls = object["tool_calls"] as? [[String: Any]],
           let data = try? JSONSerialization.data(withJSONObject: toolCalls),
           let raw = String(data: data, encoding: .utf8),
           !raw.isEmpty {
            events.append(.toolCallDelta(raw))
        }
        return events
    }

    private static func appendTextDelta(_ incoming: String, buffer: inout String) -> [ProviderStreamEvent] {
        let textDelta = StreamDeltaAccumulator.incrementalDelta(buffer: buffer, incoming: incoming)
        guard !textDelta.isEmpty else { return [] }
        buffer += textDelta
        return [.textDelta(textDelta)]
    }

    private static func appendReasoningDelta(_ incoming: String, buffer: inout String) -> [ProviderStreamEvent] {
        let reasoningDelta = StreamDeltaAccumulator.incrementalDelta(buffer: buffer, incoming: incoming)
        guard !reasoningDelta.isEmpty else { return [] }
        buffer += reasoningDelta
        return [.reasoningDelta(reasoningDelta)]
    }

    static func reasoningText(from object: [String: Any]) -> String? {
        if let details = object["reasoning_details"] as? [[String: Any]] {
            let joined = details.compactMap { detail -> String? in
                (detail["text"] as? String)?.trimmedNonEmpty
            }
            .joined()
            if let trimmed = joined.trimmedNonEmpty {
                return trimmed
            }
        }
        for key in ["reasoning_content", "reasoning", "thinking", "reasoningContent"] {
            let incoming = openAICompatibleText(from: object[key])
            if let trimmed = incoming.trimmedNonEmpty {
                return trimmed
            }
        }
        return nil
    }

    static func openAICompatibleText(from value: Any?) -> String {
        guard let value else { return "" }
        if let text = value as? String {
            return text
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        guard let parts = value as? [Any] else { return "" }
        return parts.compactMap { part -> String? in
            if let text = part as? String {
                return text
            }
            guard let block = part as? [String: Any] else { return nil }
            let type = (block["type"] as? String)?.lowercased()
            if let type, !["input_text", "output_text", "text"].contains(type) {
                return nil
            }
            return block["text"] as? String
        }
        .joined()
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
