import Combine
import Foundation

enum ChatTimelineRowChangeKind: Equatable, Sendable {
    case streamUpdate
    case completion
    case normalUpdate
}

@MainActor
final class ChatTimelineRowStore: ObservableObject, Identifiable {
    struct StreamingPresentation: Equatable {
        let snapshot: ChatStreamingSnapshot
        let markdownBlocks: [NativeMarkdownBlock]
    }

    let id: String
    @Published private(set) var item: ChatTimelineItem
    @Published private(set) var streamingPresentation: StreamingPresentation?
    private let markdownParser = NativeMarkdownIncrementalParser()

    var streamingSnapshot: ChatStreamingSnapshot? {
        streamingPresentation?.snapshot
    }

    var streamingMarkdownBlocks: [NativeMarkdownBlock]? {
        streamingPresentation?.markdownBlocks
    }

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
        guard let snapshot else {
            markdownParser.reset()
            streamingPresentation = nil
            return
        }
        let responseText: String
        if !snapshot.text.isEmpty {
            responseText = snapshot.text
        } else if case let .message(message) = item {
            responseText = message.displayText
        } else {
            responseText = ""
        }
        let artifacts = ChatArtifactPresentation.items(
            from: responseText,
            isStreaming: !snapshot.isFinal
        )
        let markdownSource = ExtractedFenceRemover.remove(
            from: responseText,
            ranges: artifacts.map { ($0.startIndex, $0.endIndex) }
        )
        let blocks = markdownParser.streamingBlocks(for: markdownSource)
        streamingPresentation = StreamingPresentation(snapshot: snapshot, markdownBlocks: blocks)
        if snapshot.isFinal {
            markdownParser.reset()
        }
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
    var onRowContentWillChange: ((String, ChatTimelineRowChangeKind) -> Void)?
    var onRowContentDidChange: ((String, ChatTimelineRowChangeKind) -> Void)?

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
        let changeKind: ChatTimelineRowChangeKind = snapshot.isFinal ? .completion : .streamUpdate
        onRowContentWillChange?(rowID, changeKind)
        row.apply(snapshot: presentedSnapshot)
        onRowContentDidChange?(rowID, changeKind)
    }

    func clearTransientStreamingSnapshots() {
        pendingStreamingSnapshotsByMessageID = pendingStreamingSnapshotsByMessageID.filter { $0.value.isFinal }
        let changedRows = rowsByID.values.filter { $0.streamingSnapshot?.isFinal == false }
        guard !changedRows.isEmpty else { return }
        for row in changedRows {
            onRowContentWillChange?(row.id, .completion)
            row.apply(snapshot: nil)
            onRowContentDidChange?(row.id, .completion)
        }
    }

    func clearAll() {
        latestMessages = []
        latestDualMessages = []
        pendingStreamingSnapshotsByMessageID.removeAll(keepingCapacity: false)
        rebuild()
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
        var changedRows: [(id: String, kind: ChatTimelineRowChangeKind)] = []
        for item in snapshot.items {
            if let existing = rowsByID[item.id] {
                let clearsFinalSnapshot = existing.streamingSnapshot.map {
                    $0.isFinal && self.item(item, containsPersistedContentsOf: $0)
                } ?? false
                if existing.item != item || clearsFinalSnapshot {
                    let kind: ChatTimelineRowChangeKind = clearsFinalSnapshot ? .completion : .normalUpdate
                    onRowContentWillChange?(item.id, kind)
                    changedRows.append((item.id, kind))
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
            let kind: ChatTimelineRowChangeKind = streamingSnapshot.isFinal ? .completion : .streamUpdate
            onRowContentWillChange?(rowID, kind)
            row.apply(snapshot: presentedSnapshot)
            changedRows.append((rowID, kind))
        }

        if orderedIDs != nextIDs {
            orderedIDs = nextIDs
        } else if !changedRows.isEmpty {
            mutationGeneration &+= 1
        }
        for change in changedRows {
            onRowContentDidChange?(change.id, change.kind)
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
