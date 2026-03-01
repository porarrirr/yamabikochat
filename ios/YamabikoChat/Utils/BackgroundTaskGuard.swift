import UIKit

final class BackgroundTaskGuard: @unchecked Sendable {
    private var taskID: UIBackgroundTaskIdentifier = .invalid
    private let lock = NSLock()

    func begin(name: String = "StreamingResponse") {
        lock.lock()
        defer { lock.unlock() }
        guard taskID == .invalid else { return }
        taskID = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            self?.end()
        }
    }

    func end() {
        lock.lock()
        defer { lock.unlock() }
        guard taskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskID)
        taskID = .invalid
    }
}
