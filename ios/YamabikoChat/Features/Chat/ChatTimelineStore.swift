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
    let markdownPresentationCache = NativeMarkdownPresentationCache()
    @Published private(set) var item: ChatTimelineItem
    @Published private(set) var streamingPresentation: StreamingPresentation?
    private let markdownParser = NativeMarkdownIncrementalParser()
    private var renderedResponseText: String?
    private var renderedMarkdownBlocks: [NativeMarkdownBlock] = []
    // Keep interaction state with the message rather than a recycled hosting cell.
    private var genUIStates: [String: GenUIState] = [:]
    @Published private(set) var contentLayoutRevision = 0

    func contentLayoutDidChange() {
        contentLayoutRevision += 1
    }

    func genUIState(id: String, document: GenUIDocument) -> GenUIState {
        if let state = genUIStates[id], state.document.isRich && document.isRich { state.document = document; return state }
        if let state = genUIStates[id], state.document == document { return state }
        let state = GenUIState(document: document)
        state.onLayoutChange = { [weak self] in self?.contentLayoutDidChange() }
        genUIStates[id] = state
        return state
    }

    var hasGenUIContent: Bool {
        switch item {
        case .message(let message):
            return (streamingSnapshot?.toolActivity?.steps ?? message.displayToolActivity?.steps ?? [])
                .contains { $0.genUIDocument != nil }
        case .dual(let message):
            return [message.modelAToolActivity, message.modelBToolActivity]
                .compactMap { $0 }.flatMap(\.steps).contains { $0.genUIDocument != nil }
        }
    }

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
            renderedResponseText = nil
            renderedMarkdownBlocks = []
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
        // Thinking and tool events often leave a long answer unchanged. Reuse
        // its fence extraction as well as its parsed Markdown until text changes.
        // Completion still reparses because an unfinished fence can become visible.
        if renderedResponseText != responseText || streamingSnapshot?.isFinal != snapshot.isFinal {
            let artifacts = ChatArtifactPresentation.items(from: responseText, isStreaming: !snapshot.isFinal)
            let markdownSource = ExtractedFenceRemover.remove(
                from: responseText, ranges: artifacts.map { ($0.startIndex, $0.endIndex) }
            )
            if snapshot.isFinal {
                // Publish the completed representation with the final snapshot.
                // A recycled/cancelled SwiftUI task must not leave the row using
                // the streaming parser, which intentionally renders TeX literally.
                renderedMarkdownBlocks = NativeMarkdownParser.parse(markdownSource)
                markdownPresentationCache.insert(renderedMarkdownBlocks, for: markdownSource, rendersMath: true)
                // A later regeneration reuses this row. Do not let the streaming
                // parser resume from prefix state that predates the final parse.
                markdownParser.reset()
            } else {
                renderedMarkdownBlocks = markdownParser.streamingBlocks(for: markdownSource)
            }
            renderedResponseText = responseText
        }
        streamingPresentation = StreamingPresentation(snapshot: snapshot, markdownBlocks: renderedMarkdownBlocks)
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
        // The timeline displays a thinking button, not the thinking transcript.
        // Keep its action's latest text observable without rebuilding/measuring
        // the hosting cell when only that hidden transcript changes. Presence
        // transitions, tool changes, answer changes and completion still resize.
        let changesOnlyThinkingContents = presentedSnapshot.map { next in
            row.streamingSnapshot.map { previous in
                !previous.isFinal && !next.isFinal
                    && previous.text == next.text
                    && previous.toolActivity == next.toolActivity
                    && previous.thinking.unicodeScalars.contains(where: {
                        !CharacterSet.whitespacesAndNewlines.contains($0)
                    }) == next.thinking.unicodeScalars.contains(where: {
                        !CharacterSet.whitespacesAndNewlines.contains($0)
                    })
            } ?? false
        } ?? false
        if !changesOnlyThinkingContents { onRowContentWillChange?(rowID, changeKind) }
        row.apply(snapshot: presentedSnapshot)
        if !changesOnlyThinkingContents { onRowContentDidChange?(rowID, changeKind) }
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
