import Foundation
import FoundationModels
import UIKit

/// In-memory SDK sessions only. Exact prior input/history matching prevents a
/// regenerated answer, edited conversation, or different chat from sharing KV state.
@available(iOS 27.0, *)
@MainActor
final class PCCSessionStore {
    static let shared = PCCSessionStore(observeMemoryWarnings: true)

    struct Signature: Equatable {
        let modelType: String
        let modelConfiguration: AnyHashable
        let instructions: String
        let tools: [PCCNativeRequest.ToolDefinition]
        let reasoning: String
        let temperature: Double?
        let maximumResponseTokens: Int?
    }

    final class Entry {
        let session: LanguageModelSession
        let router: PCCToolRouter
        let signature: Signature
        var expectedHistory: [PCCNativeRequest.Message] = []
        var lastUse = Date()

        init(session: LanguageModelSession, router: PCCToolRouter, signature: Signature) {
            self.session = session
            self.router = router
            self.signature = signature
        }
    }

    struct Lease {
        let key: String?
        let entry: Entry
        let reused: Bool
        let generation: UUID
    }

    private var entries: [String: Entry] = [:]
    private var active: Set<String> = []
    private var generation = UUID()
    private var memoryObserver: NSObjectProtocol?
    private let capacity: Int
    private let idleLifetime: TimeInterval

    init(capacity: Int = 4, idleLifetime: TimeInterval = 15 * 60, observeMemoryWarnings: Bool = false) {
        self.capacity = max(1, capacity)
        self.idleLifetime = idleLifetime
        if observeMemoryWarnings {
            memoryObserver = NotificationCenter.default.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification,
                object: nil, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.removeAll() }
                }
        }
    }

    deinit {
        if let memoryObserver { NotificationCenter.default.removeObserver(memoryObserver) }
    }

    func acquire(key: String?, signature: Signature, history: [PCCNativeRequest.Message],
                 create: () throws -> Entry) throws -> Lease {
        let key = key?.trimmedNonEmpty
        let now = Date()
        entries = entries.filter { now.timeIntervalSince($0.value.lastUse) < idleLifetime }
        if let key, active.contains(key) { throw PCCFailure(code: "pcc_session_busy") }
        let previous = key.flatMap { entries.removeValue(forKey: $0) }
        let reusable = previous.map { $0.signature == signature && $0.expectedHistory == history.map(\.canonical) } ?? false
        let entry = try reusable ? previous! : create()
        if let key { active.insert(key) }
        return Lease(key: key, entry: entry, reused: reusable, generation: generation)
    }

    func release(_ lease: Lease, completedHistory: [PCCNativeRequest.Message]?) {
        lease.entry.router.clear()
        guard let key = lease.key else { return }
        active.remove(key)
        guard generation == lease.generation, let completedHistory else { return }
        lease.entry.expectedHistory = completedHistory.map(\.canonical)
        lease.entry.lastUse = Date()
        entries[key] = lease.entry
        while entries.count > capacity, let oldest = entries.min(by: { $0.value.lastUse < $1.value.lastUse })?.key {
            entries.removeValue(forKey: oldest)
        }
    }

    func removeConversations(_ ids: Set<Int64>) {
        entries = entries.filter { key, _ in
            !ids.contains { id in
                key == "conversation-\(id)" || key.hasPrefix("conversation-\(id)-") || key == "fusion-\(id)"
            }
        }
        generation = UUID()
    }

    func removeAll() {
        entries.removeAll()
        // In-flight sessions may finish, but must not repopulate a cleared store.
        generation = UUID()
    }
}

/// Tools retained by an SDK session route to the current request's executors and
/// event stream. Clearing the router releases old run/continuation captures.
@available(iOS 27.0, *)
@MainActor
final class PCCToolRouter {
    private var handler: (@Sendable (ToolCall) async throws -> ToolResult)?

    func configure(_ handler: @escaping @Sendable (ToolCall) async throws -> ToolResult) {
        self.handler = handler
    }

    func clear() { handler = nil }

    func call(_ call: ToolCall) async throws -> ToolResult {
        try Task.checkCancellation()
        guard let handler else { throw PCCFailure(code: "pcc_tool_executor_unavailable") }
        return try await handler(call)
    }
}
