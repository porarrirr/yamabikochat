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
        let worker = Task {
            try await operation()
        }
        let timeoutTask = Task {
            try await Task.sleep(nanoseconds: UInt64(timeoutMs) * 1_000_000)
            worker.cancel()
            throw TimeoutError.timedOut(milliseconds: timeoutMs)
        }

        do {
            let result = try await worker.value
            timeoutTask.cancel()
            return result
        } catch is CancellationError {
            timeoutTask.cancel()
            throw TimeoutError.timedOut(milliseconds: timeoutMs)
        } catch {
            timeoutTask.cancel()
            throw error
        }
    }
}