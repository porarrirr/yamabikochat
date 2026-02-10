import Foundation

final class AuthFlowReadySignal: @unchecked Sendable {
    private let lock = NSLock()
    private var signaled = false
    private var continuations: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        lock.lock()
        if signaled {
            lock.unlock()
            return
        }
        lock.unlock()

        await withCheckedContinuation { continuation in
            lock.lock()
            if signaled {
                lock.unlock()
                continuation.resume(returning: ())
                return
            }
            continuations.append(continuation)
            lock.unlock()
        }
    }

    func signal() {
        lock.lock()
        guard !signaled else {
            lock.unlock()
            return
        }
        signaled = true
        let pending = continuations
        continuations.removeAll()
        lock.unlock()

        pending.forEach { $0.resume(returning: ()) }
    }
}
