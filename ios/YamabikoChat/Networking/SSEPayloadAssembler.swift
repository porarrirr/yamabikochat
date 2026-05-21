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
            return flush()
        }
        guard trimmed.hasPrefix("data:") else {
            return []
        }
        let payload = String(trimmed.dropFirst(5)).trimmingCharacters(in: .whitespaces)
        dataLines.append(payload)
        return []
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
