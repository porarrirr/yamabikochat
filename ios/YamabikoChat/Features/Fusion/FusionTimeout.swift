import Foundation

enum FusionTimeout {
    enum TimeoutError: LocalizedError, Sendable {
        case timedOut(milliseconds: Int)

        var errorDescription: String? {
            switch self {
            case let .timedOut(ms):
                return L10n.format("タイムアウト (%d ms)", ms)
            }
        }
    }

    static func run<T: Sendable>(
        milliseconds: Int,
        operation: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        let timeoutMs = max(1, milliseconds)
        return try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)
                throw TimeoutError.timedOut(milliseconds: timeoutMs)
            }
            defer { group.cancelAll() }

            guard let first = try await group.next() else {
                throw CancellationError()
            }
            return first
        }
    }
}
