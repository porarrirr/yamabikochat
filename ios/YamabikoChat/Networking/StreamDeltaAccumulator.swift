import Foundation

enum StreamDeltaAccumulator {
    /// Returns only the suffix of `incoming` that extends `buffer`, matching Android ChatResponseStreamer.incrementalDelta.
    static func incrementalDelta(buffer: String, incoming: String) -> String {
        if incoming.isEmpty {
            return ""
        }
        if incoming == buffer {
            return ""
        }
        if incoming.count > buffer.count, incoming.hasPrefix(buffer) {
            return String(incoming.dropFirst(buffer.count))
        }
        return incoming
    }
}
