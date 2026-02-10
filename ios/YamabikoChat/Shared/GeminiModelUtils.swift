import Foundation

enum GeminiModelUtils {
    private static let gemini25Pattern = #"(?i)gemini[-_/]2\.5(?:[-_/]|$)"#
    private static let gemini3Pattern = #"(?i)gemini[-_/]3(?:[-_/]|$)"#

    static func isThinkingLevelSupported(model: String) -> Bool {
        isGemini3(model: model)
    }

    static func getThinkingLevelOptions(model: String) -> [String] {
        guard isGemini3(model: model) else { return [] }
        if model.localizedCaseInsensitiveContains("flash") {
            return ["minimal", "low", "medium", "high"]
        }
        return ["low", "high"]
    }

    static func getDefaultThinkingLevel(model: String) -> String {
        isGemini3(model: model) ? "high" : ""
    }

    static func getMinimalThinkingLevel(model: String) -> String? {
        if isGemini3(model: model), model.localizedCaseInsensitiveContains("flash") {
            return "minimal"
        }
        return nil
    }

    static func normalizeThinkingLevel(model: String, level: String?) -> String? {
        let normalized = (level ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return nil }
        let options = getThinkingLevelOptions(model: model)
        return options.first(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame })
    }

    static func isThinkingSupported(model: String) -> Bool {
        isGemini25(model: model) || isGemini3(model: model)
    }

    static func isThinkingAlwaysOn(model: String) -> Bool {
        let isPro = model.localizedCaseInsensitiveContains("pro")
        return isPro && (isGemini25(model: model) || isGemini3(model: model))
    }

    static func canDisableThinking(model: String) -> Bool {
        isGemini25(model: model) &&
            (model.localizedCaseInsensitiveContains("flash") || model.localizedCaseInsensitiveContains("lite"))
    }

    static func getThinkingDescription(model: String) -> String {
        if !isThinkingSupported(model: model) {
            return "このモデルはthinking機能をサポートしていません"
        }
        if isThinkingAlwaysOn(model: model) {
            return "このモデルはthinking機能が常時ONです（Google仕様）"
        }
        if isGemini3(model: model), model.localizedCaseInsensitiveContains("flash") {
            return "Gemini 3 Flashはthinkingレベル（minimal〜high）を調整できます"
        }
        if canDisableThinking(model: model) {
            return "thinking機能のON/OFFとbudget調整が可能です"
        }
        return "thinking機能をサポートしています"
    }

    static func calculateEffectiveThinkingBudget(
        model: String,
        userThinkingEnabled: Bool,
        userThinkingBudget: Int
    ) -> Int? {
        if !isThinkingSupported(model: model) {
            return nil
        }
        if isThinkingAlwaysOn(model: model) {
            return userThinkingBudget
        }
        if userThinkingEnabled {
            return userThinkingBudget
        }
        return 0
    }

    private static func isGemini25(model: String) -> Bool {
        matches(pattern: gemini25Pattern, text: model)
    }

    private static func isGemini3(model: String) -> Bool {
        matches(pattern: gemini3Pattern, text: model)
    }

    private static func matches(pattern: String, text: String) -> Bool {
        text.range(of: pattern, options: .regularExpression) != nil
    }
}
