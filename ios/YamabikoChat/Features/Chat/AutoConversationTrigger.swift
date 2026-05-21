import Foundation

enum AutoConversationTrigger {
    private static let testPatterns: Set<String> = [
        "a", "test", "テスト", "t", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
        "aa", "aaa", "bb", "cc", "dd", "ee", "ff", "gg", "hh", "ii", "jj", "kk"
    ]

    private static let strongTriggers = [
        "こんにちは", "会話", "話", "議論", "ディスカッション", "チャット",
        "について", "どう思う", "考える", "語る", "相談", "質問"
    ]

    static func matches(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedText.count >= 2 else { return false }

        let lowerText = trimmedText.lowercased()
        if testPatterns.contains(lowerText) {
            return false
        }

        if strongTriggers.contains(where: { lowerText.contains($0) }) {
            return true
        }

        if trimmedText.count >= 3,
           lowerText.contains("？") || lowerText.contains("?") ||
           lowerText.contains("！") || lowerText.contains("!") {
            return true
        }

        if trimmedText.count >= 5 {
            let hasJapanese = lowerText.unicodeScalars.contains { scalar in
                (0x3040...0x30FF).contains(scalar.value) || scalar.value > 0x3000
            }
            let hasAlphabet = lowerText.contains { $0.isASCII && $0.isLetter }
            if hasJapanese || hasAlphabet {
                return true
            }
        }

        return false
    }
}
