import Foundation
import SwiftUI

struct ChatReasoningEffortConfiguration: Equatable, Sendable {
    let providerID: String
    let modelID: String
    let modelLabel: String
    let options: [String]
    var selectedValue: String
}

enum ChatReasoningEffortPresentationPolicy {
    private static let canonicalRanks: [String: Int] = [
        "none": 0,
        "minimal": 1,
        "low": 2,
        "medium": 3,
        "high": 4,
        "xhigh": 5,
        "max": 6,
        "ultra": 7
    ]

    static func orderedOptions(_ values: [String]) -> [String] {
        var seen = Set<String>()
        let unique = values.compactMap { rawValue -> String? in
            let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
            let comparisonKey = value.lowercased()
            guard !value.isEmpty, seen.insert(comparisonKey).inserted else { return nil }
            return value
        }

        let ranked = unique.enumerated().map { index, value in
            (index: index, value: value, rank: canonicalRanks[canonicalKey(value)])
        }
        guard ranked.allSatisfy({ $0.rank != nil }) else {
            // Provider-specific or localized effort names remain in authoritative order.
            return unique
        }
        return ranked.sorted { lhs, rhs in
            guard lhs.rank == rhs.rank else { return lhs.rank! < rhs.rank! }
            return lhs.index < rhs.index
        }.map(\.value)
    }

    static func matchingOption(_ value: String?, in options: [String]) -> String? {
        guard let value else { return nil }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        return options.first { $0.caseInsensitiveCompare(normalized) == .orderedSame }
    }

    static func showsMeter(
        isComposerFocused: Bool,
        isSoftwareKeyboardVisible: Bool,
        configuration: ChatReasoningEffortConfiguration?
    ) -> Bool {
        isComposerFocused && isSoftwareKeyboardVisible && configuration != nil
    }

    static func optionIndex(
        for locationX: CGFloat,
        width: CGFloat,
        optionCount: Int,
        horizontalInset: CGFloat
    ) -> Int? {
        guard optionCount > 0,
              let fraction = sliderFraction(
                  for: locationX,
                  width: width,
                  horizontalInset: horizontalInset
              )
        else { return nil }
        guard optionCount > 1 else { return 0 }
        return Int((fraction * CGFloat(optionCount - 1)).rounded())
    }

    static func sliderFraction(
        for locationX: CGFloat,
        width: CGFloat,
        horizontalInset: CGFloat
    ) -> CGFloat? {
        guard locationX.isFinite,
              width.isFinite,
              width > 0,
              horizontalInset.isFinite
        else { return nil }
        let usableWidth = max(width - horizontalInset * 2, 1)
        return min(max((locationX - horizontalInset) / usableWidth, 0), 1)
    }

    static func gaugeSymbolName(selectedValue: String, options: [String]) -> String {
        guard let index = options.firstIndex(of: selectedValue), options.count > 1 else {
            return "gauge.with.dots.needle.50percent"
        }
        let fraction = Double(index) / Double(options.count - 1)
        switch fraction {
        case ..<0.17: return "gauge.with.dots.needle.0percent"
        case ..<0.42: return "gauge.with.dots.needle.33percent"
        case ..<0.59: return "gauge.with.dots.needle.50percent"
        case ..<0.84: return "gauge.with.dots.needle.67percent"
        default: return "gauge.with.dots.needle.100percent"
        }
    }

    private static func canonicalKey(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }
}

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
    case mermaidViewer(id: String, source: String)

    var id: String {
        switch self {
        case .modelPicker: "model-picker"
        case .modePicker: "mode-picker"
        case let .runInspector(messageID, _): "run-\(messageID)"
        case let .thinkingInspector(messageID, _): "thinking-\(messageID)"
        case let .fusionInspector(messageID, _, _): "fusion-\(messageID)"
        case let .artifactViewer(id, _): "artifact-\(id)"
        case let .mermaidViewer(id, _): "mermaid-\(id)"
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
