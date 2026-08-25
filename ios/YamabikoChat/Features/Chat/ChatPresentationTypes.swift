import Foundation
import SwiftUI

enum ChatMode: String, CaseIterable, Identifiable, Sendable {
    case standard
    case dual
    case fusion
    case autoConversation

    var id: String { rawValue }

    init(settings: AppSettings) {
        if settings.isDualModeEnabled {
            self = .dual
        } else if settings.isFusionModeEnabled {
            self = .fusion
        } else if settings.isAutoConversationEnabled {
            self = .autoConversation
        } else {
            self = .standard
        }
    }

    var title: String {
        switch self {
        case .standard: L10n.text("通常")
        case .dual: L10n.text("デュアル")
        case .fusion: L10n.text("Fusion")
        case .autoConversation: L10n.text("自動会話")
        }
    }

    var systemImage: String {
        switch self {
        case .standard: "bubble.left.and.bubble.right"
        case .dual: "rectangle.split.2x1"
        case .fusion: "sparkles.rectangle.stack"
        case .autoConversation: "arrow.triangle.2.circlepath"
        }
    }

    func applying(to settings: AppSettings) -> AppSettings {
        var updated = settings
        updated.isDualModeEnabled = self == .dual
        updated.isFusionModeEnabled = self == .fusion
        updated.isAutoConversationEnabled = self == .autoConversation
        return updated.normalizedForPersistence()
    }
}

extension ChatRepository {
    func setChatMode(_ mode: ChatMode) throws {
        try saveSettings(mode.applying(to: loadSettings()))
    }
}

enum ChatWorkspaceRoute: Identifiable {
    case modelPicker
    case modePicker
    case runInspector(messageID: Int64, steps: [ToolActivityStep])
    case thinkingInspector(messageID: Int64, text: String)
    case fusionInspector(messageID: Int64, trace: FusionTrace, debugModeEnabled: Bool)
    case artifactViewer(id: String, block: ChatArtifactBlock)

    var id: String {
        switch self {
        case .modelPicker: "model-picker"
        case .modePicker: "mode-picker"
        case let .runInspector(messageID, _): "run-\(messageID)"
        case let .thinkingInspector(messageID, _): "thinking-\(messageID)"
        case let .fusionInspector(messageID, _, _): "fusion-\(messageID)"
        case let .artifactViewer(id, _): "artifact-\(id)"
        }
    }
}

enum TailFollowState: Equatable {
    case followingTail
    case detached(anchorMessageID: Int64, offset: CGFloat)
}

enum TailFollowPolicy {
    static let defaultThreshold: CGFloat = 96
    static let offsetTolerance: CGFloat = 0.5

    static func isNearTail(distance: CGFloat, threshold: CGFloat = defaultThreshold) -> Bool {
        distance <= threshold
    }

    static func restoredOffset(
        anchorMinY: CGFloat,
        offsetWithinViewport: CGFloat,
        lowerBound: CGFloat,
        upperBound: CGFloat
    ) -> CGFloat {
        min(max(anchorMinY - offsetWithinViewport, lowerBound), max(lowerBound, upperBound))
    }

    static func shouldAdjustOffset(
        current: CGFloat,
        target: CGFloat,
        tolerance: CGFloat = offsetTolerance
    ) -> Bool {
        abs(current - target) > tolerance
    }
}

enum ChatTimelineItem: Identifiable, Equatable {
    case message(FullChatMessage)
    case dual(DualChatMessage)

    var id: String {
        switch self {
        case let .message(item): "m-\(item.id)"
        case let .dual(item): "d-\(item.id ?? item.createdAtMs)"
        }
    }

    var createdAtMs: Int64 {
        switch self {
        case let .message(item): item.message.createdAtMs
        case let .dual(item): item.createdAtMs
        }
    }
}

struct ChatTimelineSnapshot: Equatable {
    let items: [ChatTimelineItem]

    init(messages: [FullChatMessage], dualMessages: [DualChatMessage]) {
        items = (messages.map(ChatTimelineItem.message) + dualMessages.map(ChatTimelineItem.dual))
            .sorted { lhs, rhs in
                if lhs.createdAtMs == rhs.createdAtMs { return lhs.id < rhs.id }
                return lhs.createdAtMs < rhs.createdAtMs
            }
    }
}

enum DualResponseSide {
    case a
    case b
}

struct DualResponsePresentation: Equatable {
    let text: String
    let status: DualChatMessage.SideStatus
    let error: String?
    let thinking: String?
    let toolActivity: ToolActivityPayload?

    init(message: DualChatMessage, side: DualResponseSide) {
        switch side {
        case .a:
            text = message.modelAText
            status = message.parsedModelAStatus
            error = message.modelAError
            thinking = message.modelAThinking
            toolActivity = message.modelAToolActivity
        case .b:
            text = message.modelBText
            status = message.parsedModelBStatus
            error = message.modelBError
            thinking = message.modelBThinking
            toolActivity = message.modelBToolActivity
        }
    }

    var toolSteps: [ToolActivityStep] {
        toolActivity?.steps ?? []
    }

    var attachmentPaths: [String] {
        toolActivity?.attachmentPaths ?? []
    }
}

enum ChatArtifactBlock: Equatable, Sendable {
    case html(String)
    case svg(String)

    var title: String {
        switch self {
        case .html: L10n.text("HTML 成果物")
        case .svg: L10n.text("SVG 成果物")
        }
    }

    var systemImage: String {
        switch self {
        case .html: "safari"
        case .svg: "square.on.square"
        }
    }
}

struct ChatArtifactPresentationItem: Identifiable, Equatable, Sendable {
    let id: String
    let block: ChatArtifactBlock
    let startIndex: Int
    let endIndex: Int
}

enum ChatArtifactPresentation {
    static func items(from text: String, isStreaming: Bool) -> [ChatArtifactPresentationItem] {
        let isChatError = UserFacingErrorFormatter.looksLikeChatError(text)
        guard !isStreaming, !isChatError else { return [] }

        let svg = SvgCodeExtractor.extract(from: text).map {
            ChatArtifactPresentationItem(
                id: $0.id,
                block: .svg($0.content),
                startIndex: $0.startIndex,
                endIndex: $0.endIndex
            )
        }
        let html = HtmlPreviewPolicy.blocks(
            from: text,
            isChatError: false,
            isActivelyStreaming: false
        ).map {
            ChatArtifactPresentationItem(
                id: $0.id,
                block: .html($0.content),
                startIndex: $0.startIndex,
                endIndex: $0.endIndex
            )
        }
        return (svg + html).sorted { $0.startIndex < $1.startIndex }
    }
}
