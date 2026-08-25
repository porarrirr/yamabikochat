import Combine
import Foundation

@MainActor
final class ChatTimelineRowStore: ObservableObject, Identifiable {
    let id: String
    @Published private(set) var item: ChatTimelineItem
    @Published private(set) var streamingSnapshot: ChatStreamingSnapshot?

    init(item: ChatTimelineItem) {
        id = item.id
        self.item = item
    }

    func replace(item: ChatTimelineItem) {
        guard self.item != item else { return }
        self.item = item
    }

    func apply(snapshot: ChatStreamingSnapshot?) {
        guard streamingSnapshot != snapshot else { return }
        streamingSnapshot = snapshot
    }
}

@MainActor
final class ChatTimelineStore: ObservableObject {
    @Published private(set) var orderedIDs: [String] = []
    @Published private(set) var mutationGeneration = 0

    private var rowsByID: [String: ChatTimelineRowStore] = [:]
    private var messageRowIDByDatabaseID: [Int64: String] = [:]
    private var pendingStreamingSnapshotsByMessageID: [Int64: ChatStreamingSnapshot] = [:]
    private var latestMessages: [FullChatMessage] = []
    private var latestDualMessages: [DualChatMessage] = []

    // UIKit uses these hooks to preserve the visible anchor around a self-sizing
    // row update. Streaming changes deliberately do not publish a collection-wide
    // generation because that would invalidate every visible cell each frame.
    var onRowContentWillChange: (() -> Void)?
    var onRowContentDidChange: (() -> Void)?

    func update(messages: [FullChatMessage]) {
        latestMessages = messages
        rebuild()
    }

    func update(dualMessages: [DualChatMessage]) {
        latestDualMessages = dualMessages
        rebuild()
    }

    func row(id: String) -> ChatTimelineRowStore? {
        rowsByID[id]
    }

    func applyStreamingSnapshot(_ snapshot: ChatStreamingSnapshot) {
        guard let rowID = messageRowIDByDatabaseID[snapshot.targetId],
              let row = rowsByID[rowID]
        else {
            pendingStreamingSnapshotsByMessageID[snapshot.targetId] = snapshot
            return
        }
        pendingStreamingSnapshotsByMessageID.removeValue(forKey: snapshot.targetId)
        let presentedSnapshot = snapshot.isFinal && item(row.item, containsPersistedContentsOf: snapshot)
            ? nil
            : snapshot
        guard row.streamingSnapshot != presentedSnapshot else { return }
        onRowContentWillChange?()
        row.apply(snapshot: presentedSnapshot)
        onRowContentDidChange?()
    }

    func clearTransientStreamingSnapshots() {
        pendingStreamingSnapshotsByMessageID = pendingStreamingSnapshotsByMessageID.filter { $0.value.isFinal }
        let changedRows = rowsByID.values.filter { $0.streamingSnapshot?.isFinal == false }
        guard !changedRows.isEmpty else { return }
        onRowContentWillChange?()
        for row in changedRows {
            row.apply(snapshot: nil)
        }
        onRowContentDidChange?()
    }

    private func rebuild() {
        let snapshot = ChatTimelineSnapshot(
            messages: latestMessages,
            dualMessages: latestDualMessages
        )
        let nextIDs = snapshot.items.map(\.id)
        let nextIDSet = Set(nextIDs)

        for id in rowsByID.keys where !nextIDSet.contains(id) {
            rowsByID.removeValue(forKey: id)
        }

        messageRowIDByDatabaseID.removeAll(keepingCapacity: true)
        var hasRowContentChanges = false
        for item in snapshot.items {
            if let existing = rowsByID[item.id] {
                let clearsFinalSnapshot = existing.streamingSnapshot.map {
                    $0.isFinal && self.item(item, containsPersistedContentsOf: $0)
                } ?? false
                if existing.item != item || clearsFinalSnapshot {
                    if !hasRowContentChanges {
                        onRowContentWillChange?()
                    }
                    hasRowContentChanges = true
                }
                existing.replace(item: item)
                if clearsFinalSnapshot {
                    existing.apply(snapshot: nil)
                }
            } else {
                rowsByID[item.id] = ChatTimelineRowStore(item: item)
            }
            if case let .message(message) = item {
                messageRowIDByDatabaseID[message.id] = item.id
            }
        }

        let pendingSnapshots = pendingStreamingSnapshotsByMessageID
        for (messageID, streamingSnapshot) in pendingSnapshots {
            guard let rowID = messageRowIDByDatabaseID[messageID],
                  let row = rowsByID[rowID]
            else { continue }
            pendingStreamingSnapshotsByMessageID.removeValue(forKey: messageID)
            let presentedSnapshot = streamingSnapshot.isFinal
                && item(row.item, containsPersistedContentsOf: streamingSnapshot)
                ? nil
                : streamingSnapshot
            guard row.streamingSnapshot != presentedSnapshot else { continue }
            row.apply(snapshot: presentedSnapshot)
        }

        if orderedIDs != nextIDs {
            orderedIDs = nextIDs
        } else if hasRowContentChanges {
            mutationGeneration &+= 1
        }
        if hasRowContentChanges {
            onRowContentDidChange?()
        }
    }

    private func item(_ item: ChatTimelineItem, containsPersistedContentsOf snapshot: ChatStreamingSnapshot) -> Bool {
        guard case let .message(message) = item else { return false }
        let persistedText = message.selectedVariant?.text ?? message.message.text
        guard snapshot.text.isEmpty || persistedText == snapshot.text else { return false }

        let persistedThinking = message.selectedVariant?.thinkingStream ?? message.thinkingStream ?? ""
        guard snapshot.thinking.isEmpty || persistedThinking == snapshot.thinking else { return false }

        guard let activity = snapshot.toolActivity, activity.hasPersistableContent else { return true }
        return message.displayToolActivity?.payload == activity
    }
}
