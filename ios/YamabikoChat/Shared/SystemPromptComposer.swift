import Foundation

enum SystemPromptComposer {
    private static let dateLabel = "Today's date: "
    private static let dateSuffixSeparator = "\n\n"

    static let agenticWebSearchInstructions = """
    You have access to web_search and fetch_url.

    Use web search when the answer depends on current, changing, niche, uncertain, or externally verifiable information. Do not search unnecessarily when the question can be answered reliably from stable knowledge.

    Search agentically when the task requires investigation:
    1. Identify the key facts, entities, time range, and uncertainties that must be resolved.
    2. Start with focused searches for the most important unknowns.
    3. Evaluate the returned results before deciding the next action.
    4. Refine, broaden, or split the query when results are missing, ambiguous, outdated, contradictory, or overly dependent on one source.
    5. Use fetch_url to inspect relevant original pages. Do not rely only on search snippets.
    6. Follow useful leads found in sources when they are necessary to answer the question.
    7. Prefer primary, official, and authoritative sources. Compare multiple independent sources when accuracy, recency, or controversy matters.
    8. Stop searching once the important claims are sufficiently supported. Avoid repeating equivalent searches or fetching irrelevant pages.
    9. Clearly distinguish sourced facts from inference. If reliable evidence cannot be found or sources conflict, state the limitation.
    10. In the final answer, cite the URLs of the sources actually used.

    For simple lookups, one search or one source may be sufficient. Match the depth of the search to the complexity and risk of the question.
    """

    static func composeForAPI(
        _ systemPrompt: String?,
        enablesAgenticWebSearch: Bool = false,
        now: Date = Date()
    ) -> String? {
        let dateSuffix = dateLabel + formattedDate(now)
        let components = [
            systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
            enablesAgenticWebSearch ? agenticWebSearchInstructions : nil,
            dateSuffix
        ]
        .compactMap { $0 }
        .filter { !$0.isEmpty }
        return components.joined(separator: dateSuffixSeparator)
    }

    static func mergeForAPI(_ systemPrompts: String?..., now: Date = Date()) -> String? {
        let merged = systemPrompts
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: dateSuffixSeparator)
        return composeForAPI(merged.isEmpty ? nil : merged, now: now)
    }

    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy/MM/dd"
        return formatter.string(from: date)
    }
}
