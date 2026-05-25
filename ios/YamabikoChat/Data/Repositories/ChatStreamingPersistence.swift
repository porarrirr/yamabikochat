import Foundation

/// Live UI snapshot published on every stream delta (not throttled).
struct ChatStreamingSnapshot: Sendable, Equatable {
    var targetId: Int64
    var text: String
    var thinking: String
    var isFinal: Bool
}

/// Throttles GRDB writes during streaming while keeping in-memory state immediate.
struct ChatStreamingPersistenceCoordinator {
    private let flushIntervalNs: UInt64 = 100_000_000
    private var lastFlushNs: UInt64 = 0
    private var latestText: String = ""
    private var latestThinking: String = ""

    mutating func apply(
        text: String?,
        thinking: String?,
        force: Bool,
        persist: (_ text: String, _ thinking: String) throws -> Void
    ) rethrows {
        if let text {
            latestText = text
        }
        if let thinking {
            latestThinking = thinking
        }
        let now = DispatchTime.now().uptimeNanoseconds
        if force || now &- lastFlushNs >= flushIntervalNs {
            try persist(latestText, latestThinking)
            lastFlushNs = now
        }
    }

    var text: String { latestText }
    var thinking: String { latestThinking }
}
