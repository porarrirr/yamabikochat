package com.porarri.yamabikochat.data

import com.porarri.yamabikochat.data.local.AutoConversationMessage

/**
 * Formats auto conversation content for display while keeping the raw text that should be fed back
 * into language models free from hidden reasoning traces.
 */
fun formatAutoConversationDisplay(content: String, reasoning: String?): String {
    val trimmedContent = content.trim()
    val trimmedReasoning = reasoning?.trim().orEmpty()

    return when {
        trimmedContent.isEmpty() && trimmedReasoning.isEmpty() -> ""
        trimmedReasoning.isEmpty() -> trimmedContent
        trimmedContent.isEmpty() -> buildThinkingBlock(trimmedReasoning)
        else -> buildString {
            append(trimmedContent)
            append("\n\n")
            append(buildThinkingBlock(trimmedReasoning))
        }
    }
}

fun AutoConversationMessage.displayContent(): String =
    formatAutoConversationDisplay(content, reasoning)

private fun buildThinkingBlock(reasoning: String): String {
    return buildString {
        append("```thinking\n")
        append(reasoning)
        append("\n```")
    }
}
