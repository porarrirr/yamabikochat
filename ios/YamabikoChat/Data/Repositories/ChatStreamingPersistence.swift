import Foundation

/// Live UI snapshot published on every stream delta (not throttled).
struct ChatStreamingSnapshot: Sendable, Equatable {
    var targetId: Int64
    var text: String
    var thinking: String
    var toolActivity: ToolActivityPayload?
    var isFinal: Bool
}

/// Throttles GRDB writes during streaming while keeping in-memory state immediate.
struct ChatStreamingPersistenceCoordinator {
    private let flushIntervalNs: UInt64 = 100_000_000
    private var lastFlushNs: UInt64 = 0
    private var latestText: String = ""
    private var latestThinking: String = ""

    mutating func apply(
        text: String?,
        thinking: String?,
        force: Bool,
        persist: (_ text: String, _ thinking: String) throws -> Void
    ) rethrows {
        if let text {
            latestText = text
        }
        if let thinking {
            latestThinking = thinking
        }
        let now = DispatchTime.now().uptimeNanoseconds
        if force || now &- lastFlushNs >= flushIntervalNs {
            try persist(latestText, latestThinking)
            lastFlushNs = now
        }
    }

    var text: String { latestText }
    var thinking: String { latestThinking }
}

enum ChatStreamPersistenceKind {
    case message(messageId: Int64)
    case variant(variantId: Int64, snapshotMessageId: Int64)
}

/// Persistence + snapshot identity for one provider streaming session.
struct ChatStreamSessionTarget {
    let snapshotMessageId: Int64
    private let conversations: ConversationRepository
    private let kind: ChatStreamPersistenceKind

    init(conversations: ConversationRepository, kind: ChatStreamPersistenceKind) {
        self.conversations = conversations
        self.kind = kind
        switch kind {
        case let .message(messageId):
            snapshotMessageId = messageId
        case let .variant(_, snapshotId):
            snapshotMessageId = snapshotId
        }
    }

    func persist(text: String, thinking: String) throws {
        switch kind {
        case let .message(messageId):
            try conversations.updateMessageText(messageId: messageId, text: text)
            if !thinking.isEmpty {
                try conversations.saveThinking(messageId: messageId, stream: thinking)
            }
        case let .variant(variantId, _):
            try conversations.updateMessageVariantText(variantId: variantId, text: text)
            if !thinking.isEmpty {
                try conversations.saveMessageVariantThinking(variantId: variantId, stream: thinking)
            }
        }
    }

    func writeErrorPlaceholder(_ error: Error) throws {
        let placeholder = UserFacingErrorFormatter.placeholder(for: error)
        switch kind {
        case let .message(messageId):
            try conversations.updateMessageText(messageId: messageId, text: placeholder)
        case let .variant(variantId, _):
            try conversations.updateMessageVariantText(variantId: variantId, text: placeholder)
        }
    }

    func persistToolActivity(_ payload: ToolActivityPayload) throws {
        switch kind {
        case let .message(messageId):
            try conversations.saveToolActivity(messageId: messageId, variantId: nil, payload: payload)
        case let .variant(variantId, _):
            try conversations.saveToolActivity(messageId: nil, variantId: variantId, payload: payload)
        }
    }

    func persistAttachments(_ paths: [String]) throws {
        guard !paths.isEmpty else { return }
        switch kind {
        case let .message(messageId):
            try conversations.appendAttachments(messageId: messageId, paths: paths)
        case let .variant(variantId, _):
            try conversations.appendAttachments(variantId: variantId, paths: paths)
        }
    }
}

struct ChatStreamSessionResult {
    var text: String
    var reasoningText: String
    var usage: ProviderUsage?
    var usageSamples: [ProviderUsage]?
    var toolCalls: [ToolCall]
    var toolActivity: ToolActivityPayload?
}

enum ChatStreamSession {
    static func run(
        stream: AsyncThrowingStream<ProviderStreamEvent, Error>,
        conversations: ConversationRepository,
        kind: ChatStreamPersistenceKind,
        onStreamEvent: (@Sendable (ProviderStreamEvent) -> Void)?,
        onStreamingSnapshot: (@Sendable (ChatStreamingSnapshot) -> Void)?
    ) async throws -> ChatStreamSessionResult {
        let target = ChatStreamSessionTarget(conversations: conversations, kind: kind)
        var fullText = ""
        var reasoningText = ""
        var finalUsage: ProviderUsage?
        var finalUsageSamples: [ProviderUsage]?
        var finalToolCalls: [ToolCall] = []
        var toolActivity = ToolActivityPayload()
        var coordinator = ChatStreamingPersistenceCoordinator()
        do {
            for try await event in stream {
                try consumeStreamEvent(
                    event,
                    target: target,
                    fullText: &fullText,
                    reasoningText: &reasoningText,
                    finalUsage: &finalUsage,
                    finalUsageSamples: &finalUsageSamples,
                    finalToolCalls: &finalToolCalls,
                    toolActivity: &toolActivity,
                    coordinator: &coordinator,
                    onStreamEvent: onStreamEvent,
                    onStreamingSnapshot: onStreamingSnapshot
                )
            }
        } catch {
            toolActivity.failRunning(message: L10n.text("ツールの実行が中断されました"))
            if toolActivity.hasPersistableContent {
                try? target.persistToolActivity(toolActivity)
            }
            if fullText.isEmpty, reasoningText.isEmpty {
                try? target.writeErrorPlaceholder(error)
            }
            publishStreamingSnapshot(
                targetId: target.snapshotMessageId,
                coordinator: coordinator,
                toolActivity: toolActivity,
                isFinal: true,
                onStreamingSnapshot: onStreamingSnapshot
            )
            throw error
        }

        try coordinator.apply(text: fullText, thinking: reasoningText, force: true, persist: target.persist)
        if toolActivity.hasPersistableContent {
            try target.persistToolActivity(toolActivity)
        }
        publishStreamingSnapshot(
            targetId: target.snapshotMessageId,
            coordinator: coordinator,
            toolActivity: toolActivity,
            isFinal: true,
            onStreamingSnapshot: onStreamingSnapshot
        )

        return ChatStreamSessionResult(
            text: fullText,
            reasoningText: reasoningText,
            usage: finalUsage,
            usageSamples: finalUsageSamples,
            toolCalls: finalToolCalls,
            toolActivity: toolActivity.hasPersistableContent ? toolActivity : nil
        )
    }

    private static func consumeStreamEvent(
        _ event: ProviderStreamEvent,
        target: ChatStreamSessionTarget,
        fullText: inout String,
        reasoningText: inout String,
        finalUsage: inout ProviderUsage?,
        finalUsageSamples: inout [ProviderUsage]?,
        finalToolCalls: inout [ToolCall],
        toolActivity: inout ToolActivityPayload,
        coordinator: inout ChatStreamingPersistenceCoordinator,
        onStreamEvent: (@Sendable (ProviderStreamEvent) -> Void)?,
        onStreamingSnapshot: (@Sendable (ChatStreamingSnapshot) -> Void)?
    ) throws {
        onStreamEvent?(event)
        switch event {
        case .answerStart:
            fullText = ""
            try publishBufferedState(
                target: target,
                coordinator: &coordinator,
                fullText: fullText,
                reasoningText: reasoningText,
                toolActivity: toolActivity,
                force: true,
                onStreamingSnapshot: onStreamingSnapshot
            )
        case let .textDelta(delta):
            fullText += delta
            try publishBufferedState(
                target: target,
                coordinator: &coordinator,
                fullText: fullText,
                reasoningText: reasoningText,
                toolActivity: toolActivity,
                force: false,
                onStreamingSnapshot: onStreamingSnapshot
            )
        case let .reasoningDelta(delta):
            reasoningText += delta
            try publishBufferedState(
                target: target,
                coordinator: &coordinator,
                fullText: fullText,
                reasoningText: reasoningText,
                toolActivity: toolActivity,
                force: false,
                onStreamingSnapshot: onStreamingSnapshot
            )
        case let .toolActivity(event):
            toolActivity.apply(event)
            if event.phase == .finished, let result = event.result {
                try target.persistAttachments(result.artifacts.map(\.path))
            }
            publishStreamingSnapshot(
                targetId: target.snapshotMessageId,
                coordinator: coordinator,
                toolActivity: toolActivity,
                isFinal: false,
                onStreamingSnapshot: onStreamingSnapshot
            )
        case let .executionSnapshot(execution):
            toolActivity.piExecution = execution
            try target.persistToolActivity(toolActivity)
        case let .completed(response):
            finalUsage = response.usage ?? finalUsage
            finalUsageSamples = response.usageSamples ?? finalUsageSamples
            finalToolCalls = response.toolCalls
            toolActivity.piExecution = response.piExecution
            // Pi's completed response is built from the last assistant message.
            // Earlier assistant turns can contain user-facing progress text before
            // tool calls, so completion authoritatively replaces the live buffer.
            fullText = response.text
            if let reasoning = response.reasoningSummary, !reasoning.isEmpty {
                reasoningText = reasoning
            }
            try publishBufferedState(
                target: target,
                coordinator: &coordinator,
                fullText: fullText,
                reasoningText: reasoningText,
                toolActivity: toolActivity,
                force: true,
                onStreamingSnapshot: onStreamingSnapshot
            )
        }
    }

    private static func publishBufferedState(
        target: ChatStreamSessionTarget,
        coordinator: inout ChatStreamingPersistenceCoordinator,
        fullText: String,
        reasoningText: String,
        toolActivity: ToolActivityPayload,
        force: Bool,
        onStreamingSnapshot: (@Sendable (ChatStreamingSnapshot) -> Void)?
    ) throws {
        try coordinator.apply(text: fullText, thinking: reasoningText, force: force, persist: target.persist)
        publishStreamingSnapshot(
            targetId: target.snapshotMessageId,
            coordinator: coordinator,
            toolActivity: toolActivity,
            isFinal: false,
            onStreamingSnapshot: onStreamingSnapshot
        )
    }

    private static func publishStreamingSnapshot(
        targetId: Int64,
        coordinator: ChatStreamingPersistenceCoordinator,
        toolActivity: ToolActivityPayload?,
        isFinal: Bool,
        onStreamingSnapshot: (@Sendable (ChatStreamingSnapshot) -> Void)?
    ) {
        onStreamingSnapshot?(
            ChatStreamingSnapshot(
                targetId: targetId,
                text: coordinator.text,
                thinking: coordinator.thinking,
                toolActivity: toolActivity,
                isFinal: isFinal
            )
        )
    }
}
