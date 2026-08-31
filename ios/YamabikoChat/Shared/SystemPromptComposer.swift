import Foundation

enum SystemPromptComposer {
    private static let dateLabel = "Today's date: "
    private static let dateSuffixSeparator = "\n\n"

    static let agenticWebSearchInstructions = """
    You have access to web_search and fetch_url.

    Use web search when the answer depends on current, changing, niche, uncertain, or externally verifiable information. Do not search unnecessarily when the question can be answered reliably from stable knowledge.

    Search agentically when the task requires investigation:
    1. Identify the key facts, entities, time range, and uncertainties that must be resolved.
    2. Start with a broad search that can reveal the relevant terminology, sources, and competing explanations.
    3. Read titles and snippets before deciding which pages are necessary. Do not fetch every result.
    4. Use fetch_url(url, goal) only for relevant original pages, and state a specific evidence goal for each page. Do not rely only on search snippets.
    5. Refine, narrow, or split the query when results are missing, ambiguous, outdated, contradictory, or overly dependent on one source.
    6. Follow useful leads found in sources when they are necessary to answer the question.
    7. Prefer primary, official, and authoritative sources. Compare multiple independent sources when accuracy, recency, or controversy matters.
    8. Stop searching once the important claims are sufficiently supported. Do not repeat equivalent searches with superficial wording changes or fetch irrelevant pages.
    9. Clearly distinguish sourced facts from inference. If reliable evidence cannot be found or sources conflict, state the limitation.
    10. In the final answer, cite only the sources actually used. Format every source as a descriptive Markdown link such as [source or article title](https://example.com/article). Never expose a bare URL when a descriptive link label is available.

    For simple lookups, one search or one source may be sufficient. Match the depth of the search to the complexity and risk of the question.
    """

    static let editorToolInstructions = """
    Use only the tools that are actually provided. Follow each tool's parameter schema exactly, and do not invent tool names or parameters. If a tool returns an error, do not claim that the operation succeeded.

    When using str_replace_editor:
    - The current execution gets a fresh /workspace. For a project, it initially contains copies of the files added by the user. When the request refers to project files or workspace contents, inspect /workspace and read the relevant files instead of asking the user to attach them again.
    - Inspect the relevant file before modifying it.
    - Use view_format=jsonl before whitespace-sensitive str_replace operations; copy only the JSON `text` value, without the line metadata.
    - Use create only for a path that does not already exist.
    - Use str_replace only when old_str uniquely identifies the intended text.
    - Preserve unrelated content.
    """

    static let userQuestionToolInstructions = """
    Use ask_user_question only when you need the user's confirmation, a user-owned choice, or information that cannot be discovered from the available context or tools. Keep each question concise and give it a stable id. You may ask multiple questions in one call. Put a recommended option first and append "(Recommended)" to its label. Set multi_select to true only when more than one option may be selected. If the user cancels, do not invent an answer or claim that the question was answered.
    """

    static func composeForAPI(
        _ systemPrompt: String?,
        enablesAgenticWebSearch: Bool = false,
        enablesEditorInstructions: Bool = false,
        enablesUserQuestionInstructions: Bool = false,
        now: Date = Date()
    ) -> String? {
        let dateSuffix = dateLabel + formattedDate(now)
        let components = [
            systemPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
            enablesAgenticWebSearch ? agenticWebSearchInstructions : nil,
            enablesEditorInstructions ? editorToolInstructions : nil,
            enablesUserQuestionInstructions ? userQuestionToolInstructions : nil,
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
