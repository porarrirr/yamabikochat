import Foundation

/// Assembles Server-Sent Event payloads from raw line stream chunks (Android eventBuffer parity).
struct SSEPayloadAssembler {
    private var dataLines: [String] = []

    mutating func consume(line: String) -> [String] {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix(":") {
            return []
        }
        if trimmed.isEmpty {
            // A single complete stream chunk may arrive without a following blank line (OpenCode Go).
            if dataLines.count == 1,
               Self.looksLikeCompleteJSONEvent(dataLines[0]) {
                return []
            }
            return flush()
        }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") {
            var payloads = flush()
            payloads.append(trimmed)
            return payloads
        }
        guard trimmed.hasPrefix("data:") else {
            return []
        }
        let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        guard !payload.isEmpty else {
            return []
        }
        // Some gateways (incl. OpenCode Go / DeepSeek) omit the blank line between events.
        var payloads: [String] = []
        if !dataLines.isEmpty {
            let pending = dataLines.joined(separator: "\n")
            if Self.looksLikeCompleteJSONEvent(pending) {
                // Emit the previous event before buffering the next `data:` line.
                payloads.append(contentsOf: flush())
            }
        }
        dataLines.append(payload)
        return payloads
    }

    private static func looksLikeCompleteJSONEvent(_ raw: String) -> Bool {
        guard raw.first == "{",
              let data = raw.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }
        // Multiline `data:` fragments can be valid JSON but belong to one event; only split
        // back-to-back provider stream chunks (OpenAI choices, Anthropic type, Gemini candidates).
        return object["choices"] != nil || object["type"] != nil || object["candidates"] != nil
    }

    mutating func flushRemaining() -> [String] {
        flush()
    }

    private mutating func flush() -> [String] {
        guard !dataLines.isEmpty else {
            return []
        }
        let payload = dataLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        dataLines.removeAll(keepingCapacity: true)
        guard !payload.isEmpty else {
            return []
        }
        return [payload]
    }
}

enum SSEPayloadAssembly {
    /// Yields fully assembled SSE JSON payloads (blank-line delimited, multiline data: joined).
    static func payloads(
        from lineStream: AsyncThrowingStream<String, Error>
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var assembler = SSEPayloadAssembler()
                do {
                    for try await line in lineStream {
                        for payload in assembler.consume(line: line) {
                            continuation.yield(payload)
                        }
                    }
                    for payload in assembler.flushRemaining() {
                        continuation.yield(payload)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
