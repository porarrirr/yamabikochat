import Foundation

/// Pure turn planning, independent of persistence and provider execution.
enum AutoConversationTurnPolicy {
    enum Speaker {
        case a
        case b

        var modelLabel: String {
            switch self {
            case .a:
                return "AI-A"
            case .b:
                return "AI-B"
            }
        }

        var modelCode: AutoConversationSpeakerModel {
            switch self {
            case .a:
                return .a
            case .b:
                return .b
            }
        }

        var context: AppSettings.ReasoningContext {
            switch self {
            case .a:
                return .autoA
            case .b:
                return .autoB
            }
        }
    }

    private static let autoConversationUnlimitedTurnSafetyLimit = 100
    private static let autoConversationSessionDurationLimitMs: Int64 = 30 * 60 * 1_000
    private static let autoConversationEndRegexes: [NSRegularExpression] = [
        try! NSRegularExpression(pattern: "(?:会話|議論|討論|対話)(?:を)?(?:(?:ここ|これ|以上)で)?(?:終了|終わり)(?:に)?(?:いたします|します|しましょう|ます|ましょう|とします)", options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: "これ(?:にて|で)(?:終(?:了|わ)り|終了)とさせていただきます", options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: "(?:ここ|これ|以上|本件)(?:で|にて)(?:終(?:了|わ)り|終了)(?:とします|です)", options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: "\\bend of (?:this )?(?:conversation|discussion)\\b", options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: "\\bthis concludes (?:our )?(?:conversation|discussion)\\b", options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: "\\blet'?s end (?:the )?(?:conversation|discussion)\\b", options: [.caseInsensitive]),
        try! NSRegularExpression(pattern: "\\bconversation (?:has )?(?:ended|is over)\\b", options: [.caseInsensitive])
    ]

    static func determineAutoConversationNextStep(messages: [AutoConversationMessage]) -> (turn: Int, speaker: Speaker) {
        let ordered = orderedMessages(messages)
        let lastModelMessage = ordered.last(where: {
            $0.speakerModel == .a || $0.speakerModel == .b
        })

        guard let lastModelMessage else {
            return (1, .a)
        }
        let nextSpeaker: Speaker = (lastModelMessage.speakerModel == .a) ? .b : .a
        return (lastModelMessage.turnNumber + 1, nextSpeaker)
    }

    static func buildAutoConversationHistory(
        messages: [AutoConversationMessage],
        speaker: Speaker
    ) -> [ProviderRequestMessage] {
        let ordered = orderedMessages(messages)
        return ordered.compactMap { message in
            let content = message.content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else { return nil }
            switch message.speakerModel {
            case .user:
                return ProviderRequestMessage(role: "user", content: content)
            case .a, .b:
                let role: String
                switch (speaker, message.speakerModel) {
                case (.a, .a), (.b, .b):
                    role = "assistant"
                default:
                    role = "user"
                }
                return ProviderRequestMessage(role: role, content: content)
            }
        }
    }

    static func containsAutoConversationEndSignal(text: String, configuredEndSignal: String) -> Bool {
        let normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return false }

        let endSignal = configuredEndSignal.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetSignal = endSignal.isEmpty ? "[END]" : endSignal
        if normalized.range(of: targetSignal, options: [.caseInsensitive, .widthInsensitive]) != nil {
            return true
        }

        let range = NSRange(location: 0, length: (normalized as NSString).length)
        return Self.autoConversationEndRegexes.contains { regex in
            regex.firstMatch(in: normalized, options: [], range: range) != nil
        }
    }

    private static func orderedMessages(_ messages: [AutoConversationMessage]) -> [AutoConversationMessage] {
        messages.sorted {
            if $0.turnNumber == $1.turnNumber { return ($0.id ?? 0) < ($1.id ?? 0) }
            return $0.turnNumber < $1.turnNumber
        }
    }

    static func reachedSafetyLimit(maxTurns: Int, nextTurn: Int, createdAtMs: Int64, nowMs: Int64) -> Bool {
        maxTurns == 0 && (nextTurn > autoConversationUnlimitedTurnSafetyLimit
            || nowMs - createdAtMs >= autoConversationSessionDurationLimitMs)
    }
}
