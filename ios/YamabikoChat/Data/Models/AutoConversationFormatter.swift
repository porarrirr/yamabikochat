import Foundation

func formatAutoConversationDisplay(content: String, reasoning: String?) -> String {
    let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
    let trimmedReasoning = (reasoning ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

    switch (trimmedContent.isEmpty, trimmedReasoning.isEmpty) {
    case (true, true):
        return ""
    case (false, true):
        return trimmedContent
    case (true, false):
        return buildThinkingBlock(trimmedReasoning)
    case (false, false):
        return "\(trimmedContent)\n\n\(buildThinkingBlock(trimmedReasoning))"
    }
}

private func buildThinkingBlock(_ reasoning: String) -> String {
    "```thinking\n\(reasoning)\n```"
}
