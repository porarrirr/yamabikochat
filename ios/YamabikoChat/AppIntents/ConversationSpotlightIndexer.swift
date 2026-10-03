import AppIntents
import Combine
import CoreSpotlight
import Foundation

struct ConversationIndexPlan {
    let current: [Int64: ConversationListEntry]
    let removedIDs: [Int64]
    let changed: [ConversationListEntry]

    init(previous: [Int64: ConversationListEntry], entries: [ConversationListEntry]) {
        let visible = entries.filter { !$0.isSecret }
        let currentEntries = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, $0) })
        current = currentEntries
        removedIDs = previous.keys.filter { currentEntries[$0] == nil }
        changed = visible.filter {
            previous[$0.id]?.title != $0.title || previous[$0.id]?.updatedAtMs != $0.updatedAtMs
        }
    }
}

@MainActor
final class ConversationSpotlightIndexer {
    private var observation: AnyCancellable?
    private var pending: [ConversationListEntry]?
    private var task: Task<Void, Never>?
    private var indexed: [Int64: ConversationListEntry] = [:]
    private var initialized = false

    init(repository: ConversationRepository) {
        guard #available(iOS 18.0, *) else { return }
        observation = repository.observeConversationList()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] entries in self?.enqueue(entries) }
    }

    private func enqueue(_ entries: [ConversationListEntry]) {
        pending = entries.filter { !$0.isSecret }
        guard task == nil else { return }
        task = Task { [weak self] in
            guard let self else { return }
            while let entries = pending {
                pending = nil
                if #available(iOS 18.0, *) { await reconcile(entries) }
            }
            task = nil
        }
    }

    @available(iOS 18.0, *)
    private func reconcile(_ entries: [ConversationListEntry]) async {
        let index = CSSearchableIndex.default()
        do {
            // Remove stale entries once per launch, scoped to our own entity type.
            if !initialized {
                try await index.deleteAppEntities(ofType: ConversationEntity.self)
                indexed = [:]
                initialized = true
            }
            let plan = ConversationIndexPlan(previous: indexed, entries: entries)
            if !plan.removedIDs.isEmpty {
                try await index.deleteAppEntities(identifiedBy: plan.removedIDs.map(Int.init), ofType: ConversationEntity.self)
            }
            let changed = plan.changed.map {
                ConversationEntity(id: $0.id, title: $0.title,
                                   updatedAt: Date(timeIntervalSince1970: Double($0.updatedAtMs) / 1000))
            }
            if !changed.isEmpty { try await index.indexAppEntities(changed) }
            indexed = plan.current
        } catch {
            DiagnosticsLogger.log("Siri conversation indexing failed", category: .app, error: error)
        }
    }
}
