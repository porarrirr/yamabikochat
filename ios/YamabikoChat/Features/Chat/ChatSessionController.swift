import Foundation

/// Owns frame-coalesced presentation state for one Pi streaming session.
/// Provider/model resolution and the Pi execution contract remain in ChatRepository.
@MainActor
final class ChatSessionController {
    private var snapshots: [Int64: ChatStreamingSnapshot] = [:]
    private var pendingSnapshots: [Int64: ChatStreamingSnapshot] = [:]
    private var lastPublishAt: [Int64: Date] = [:]
    private var flushTasks: [Int64: Task<Void, Never>] = [:]
    private let frameInterval: TimeInterval
    private let now: () -> Date

    init(
        frameInterval: TimeInterval = 1.0 / 30.0,
        now: @escaping () -> Date = Date.init
    ) {
        self.frameInterval = frameInterval
        self.now = now
    }

    var onSnapshot: (ChatStreamingSnapshot) -> Void = { _ in }
    var onClear: () -> Void = {}

    var isEmpty: Bool { snapshots.isEmpty }

    func snapshot(for messageID: Int64) -> ChatStreamingSnapshot? {
        snapshots[messageID]
    }

    func handle(_ snapshot: ChatStreamingSnapshot) {
        let targetID = snapshot.targetId
        if snapshot.isFinal {
            flushTasks[targetID]?.cancel()
            flushTasks.removeValue(forKey: targetID)
            pendingSnapshots.removeValue(forKey: targetID)
            lastPublishAt.removeValue(forKey: targetID)
            snapshots.removeValue(forKey: targetID)
            onSnapshot(snapshot)
            return
        }

        pendingSnapshots[targetID] = snapshot
        let elapsed = now().timeIntervalSince(lastPublishAt[targetID] ?? .distantPast)
        if elapsed >= frameInterval {
            flushTasks[targetID]?.cancel()
            flushTasks.removeValue(forKey: targetID)
            publishPending(targetID: targetID)
            return
        }

        guard flushTasks[targetID] == nil else { return }
        let delay = frameInterval - elapsed
        flushTasks[targetID] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(delay, 0) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            self.publishPending(targetID: targetID)
            self.flushTasks.removeValue(forKey: targetID)
        }
    }

    func clear() {
        flushTasks.values.forEach { $0.cancel() }
        flushTasks.removeAll()
        pendingSnapshots.removeAll()
        lastPublishAt.removeAll()
        snapshots.removeAll()
        onClear()
    }

    private func publishPending(targetID: Int64) {
        guard let snapshot = pendingSnapshots.removeValue(forKey: targetID) else { return }
        lastPublishAt[targetID] = now()
        snapshots[targetID] = snapshot
        onSnapshot(snapshot)
    }
}
