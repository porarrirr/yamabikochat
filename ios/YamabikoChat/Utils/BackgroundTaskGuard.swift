import UIKit

@MainActor
private final class BackgroundTaskCoordinator {
    static let shared = BackgroundTaskCoordinator()

    private struct Entry {
        let name: String
        var taskID: UIBackgroundTaskIdentifier
    }

    private var entries: [UUID: Entry] = [:]
    private var observersInstalled = false

    private init() {}

    func register(id: UUID, name: String) {
        installObserversIfNeeded()
        entries[id] = Entry(name: name, taskID: .invalid)
        beginTaskIfNeeded(id: id)
    }

    func unregister(id: UUID) {
        endTask(id: id)
        entries.removeValue(forKey: id)
    }

    private func beginTaskIfNeeded(id: UUID) {
        guard var entry = entries[id] else { return }
        guard entry.taskID == .invalid else { return }
        guard UIApplication.shared.applicationState != .active else { return }

        let taskID = UIApplication.shared.beginBackgroundTask(withName: entry.name) { [weak self] in
            Task { @MainActor in
                self?.handleExpiration(id: id)
            }
        }
        guard taskID != .invalid else { return }
        entry.taskID = taskID
        entries[id] = entry
    }

    private func endTask(id: UUID) {
        guard var entry = entries[id] else { return }
        guard entry.taskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(entry.taskID)
        entry.taskID = .invalid
        entries[id] = entry
    }

    private func handleExpiration(id: UUID) {
        endTask(id: id)
    }

    private func handleDidEnterBackground() {
        for id in entries.keys {
            beginTaskIfNeeded(id: id)
        }
    }

    private func handleWillEnterForeground() {
        for id in entries.keys {
            endTask(id: id)
        }
    }

    private func installObserversIfNeeded() {
        guard !observersInstalled else { return }
        observersInstalled = true

        NotificationCenter.default.addObserver(
            forName: UIApplication.didEnterBackgroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleDidEnterBackground()
            }
        }

        NotificationCenter.default.addObserver(
            forName: UIApplication.willEnterForegroundNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleWillEnterForeground()
            }
        }
    }
}

final class BackgroundTaskGuard: @unchecked Sendable {
    private let id = UUID()
    private var isActive = false
    private let lock = NSLock()

    func begin(name: String = "StreamingResponse") {
        lock.lock()
        defer { lock.unlock() }
        guard !isActive else { return }
        isActive = true
        runOnMain {
            BackgroundTaskCoordinator.shared.register(id: self.id, name: name)
        }
    }

    func end() {
        lock.lock()
        let shouldEnd = isActive
        isActive = false
        lock.unlock()
        guard shouldEnd else { return }
        runOnMain {
            BackgroundTaskCoordinator.shared.unregister(id: self.id)
        }
    }

    private func runOnMain(_ block: @MainActor @escaping () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                block()
            }
        } else {
            DispatchQueue.main.sync {
                block()
            }
        }
    }
}