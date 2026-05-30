package com.porarri.yamabikochat.ui.chat

object AutoConversationTrigger {
    private val testPatterns = setOf(
        "a", "test", "テスト", "t", "1", "2", "3", "4", "5", "6", "7", "8", "9", "0",
        "aa", "aaa", "bb", "cc", "dd", "ee", "ff", "gg", "hh", "ii", "jj", "kk"
    )

    private val strongTriggers = listOf(
        "こんにちは", "会話", "話", "議論", "ディスカッション", "チャット",
        "について", "どう思う", "考える", "語る", "相談", "質問"
    )

    fun matches(text: String): Boolean {
        val trimmedText = text.trim()
        if (trimmedText.length < 2) return false

        val lowerText = trimmedText.lowercase()
        if (testPatterns.contains(lowerText)) return false

        if (strongTriggers.any { trigger -> lowerText.contains(trigger) }) {
            return true
        }

        if (
            trimmedText.length >= 3 &&
            (lowerText.contains("？") || lowerText.contains("?") ||
                lowerText.contains("！") || lowerText.contains("!"))
        ) {
            return true
        }

        if (trimmedText.length >= 5) {
            val hasJapanese = lowerText.any {
                it in 'あ'..'ん' || it in 'ア'..'ン' || it.code > 0x3000
            }
            val hasAlphabet = lowerText.any { it in 'a'..'z' }

            if (hasJapanese || hasAlphabet) {
                return true
            }
        }

        return false
    }
}
