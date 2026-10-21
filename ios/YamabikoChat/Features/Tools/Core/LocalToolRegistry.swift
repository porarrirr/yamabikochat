import Foundation

protocol LocalToolExecutor: Sendable {
    var definition: ToolDefinition { get }
    func execute(call: ToolCall) async throws -> ToolResult
}

struct LocalToolRegistry: Sendable {
    private let executors: [String: any LocalToolExecutor]
    private let webResearch: WebResearchSession

    /// The app and offline PCC contract tests share this inventory so adding a
    /// built-in tool also adds its schema to the simulator validation.
    static func builtInExecutors(
        reader: FetchUrlTool = FetchUrlTool(),
        python: PythonExecuteTool = PythonExecuteTool(),
        editor: StrReplaceEditorTool = StrReplaceEditorTool(),
        questions: AskUserQuestionTool = AskUserQuestionTool(coordinator: UserQuestionCoordinator())
    ) -> [any LocalToolExecutor] {
        [WebSearchTool(reader: reader), reader, python, editor, questions, GenUITool(), GenUIReferenceTool()]
    }

    init(executors: [any LocalToolExecutor]) {
        webResearch = WebResearchSession()
        self.executors = Dictionary(
            executors.map { ($0.definition.name, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    /// Pi owns the execution. Each stream gets isolated retrieval bookkeeping,
    /// even when the app reuses this registry across conversations.
    func scopedForExecution() -> LocalToolRegistry {
        LocalToolRegistry(executors: Array(executors.values))
    }

    var definitions: [ToolDefinition] {
        executors.values.map(\.definition).sorted { $0.name < $1.name }
    }

    func execute(call: ToolCall) async -> ToolResult {
        guard let executor = executors[call.name] else {
            return ToolResult(
                callId: call.id,
                name: call.name,
                content: Self.errorContent("Unknown local tool: \(call.name)"),
                isError: true
            )
        }

        if let blocked = await webResearch.begin(call) { return blocked }
        do {
            let result = try await executor.execute(call: call)
            return await webResearch.finish(call, result: result)
        } catch {
            if call.name != WebSearchTool.name {
                DiagnosticsLogger.log(
                    "Local tool execution failed",
                    category: .network,
                    metadata: ["tool": call.name],
                    error: error
                )
            }
            let result = ToolResult(callId: call.id, name: call.name,
                                    content: Self.errorContent(error.localizedDescription), isError: true)
            return await webResearch.finish(call, result: result)
        }
    }

    static func errorContent(_ message: String) -> String {
        let object = ["error": message]
        guard let data = try? JSONSerialization.data(withJSONObject: object),
              let json = String(data: data, encoding: .utf8)
        else {
            return #"{"error":"Local tool execution failed"}"#
        }
        return json
    }
}

/// Tracks observable retrieval progress, never factual truth or model context.
/// No domain keywords, URL templates, inferred protocols or alternative AI calls.
private actor WebResearchSession {
    private var calls: [String: String] = [:]
    private var completed: [String: ToolResult] = [:]
    private var completionOrder: [String] = []
    private var discovered: Set<String> = []
    private var passages: Set<String> = []
    private var failedDocuments: [String: String] = [:]
    private var stalledSearches = 0

    func begin(_ call: ToolCall) -> ToolResult? {
        guard let key = fingerprint(call) else { return nil }
        if let previous = calls[key] {
            if completed[key]?.isError == false || (try? ToolArguments.object(from: call.argumentsJSON))?["recover_cached"] as? Bool == true {
                if var recovered = completed[key] {
                    recovered.callId = call.id
                    if var object = try? JSONSerialization.jsonObject(with: Data(recovered.content.utf8)) as? [String: Any] {
                        object["research_status"] = "cached_evidence_recovered"
                        object["previous_call_id"] = previous
                        object["network_request_performed"] = false
                        object["research_progress"] = ["new_source_count": 0, "new_passage_count": 0]
                        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) {
                            recovered.content = String(decoding: data, as: UTF8.self)
                        }
                    }
                    return recovered
                }
                // A long execution may have evicted that cached result. Explicit
                // recovery may retrieve it again; Pi still owns context compaction.
                calls[key] = call.id
                return nil
            }
            return stopped(call, reason: "duplicate_request", previous: previous,
                           action: "Use the earlier result. For a missing fact, inspect a new document section or a materially different source; do not repeat this request.")
        }
        if call.name == FetchUrlTool.name,
           let arguments = try? ToolArguments.object(from: call.argumentsJSON),
           let url = arguments["url"] as? String, let previous = failedDocuments[urlKey(url)] {
            return stopped(call, reason: "source_unavailable_this_execution", previous: previous,
                           action: "This source already failed in this execution. Changing the goal cannot repair its HTTP/access/format failure. Use an accessible source or report the gap.")
        }
        if call.name == WebSearchTool.name, stalledSearches >= 3 {
            return stopped(call, reason: "search_no_new_sources", previous: nil,
                           action: "Three searches added no new sources. Read an unread source/section from existing results, or answer the supported facts and state the unresolved gap. Searching unlocks if reading adds new passages.")
        }
        calls[key] = call.id
        return nil
    }

    func finish(_ call: ToolCall, result: ToolResult) -> ToolResult {
        guard [WebSearchTool.name, FetchUrlTool.name].contains(call.name) else { return result }
        if call.name == FetchUrlTool.name, result.isError,
           let arguments = try? ToolArguments.object(from: call.argumentsJSON), let url = arguments["url"] as? String {
            failedDocuments[urlKey(url)] = call.id
        }
        if let key = fingerprint(call) {
            if completed[key] == nil { completionOrder.append(key) }
            completed[key] = result
            while completionOrder.count > 32 { completed.removeValue(forKey: completionOrder.removeFirst()) }
        }
        var newSources = 0
        for source in result.sources {
            if discovered.insert(urlKey(source.url)).inserted { newSources += 1 }
        }
        let payload = try? JSONSerialization.jsonObject(with: Data(result.content.utf8))
        var newPassages = 0
        if let object = payload as? [String: Any] {
            if call.name == FetchUrlTool.name, object["selection_status"] as? String == "dynamic_content_unavailable",
               let arguments = try? ToolArguments.object(from: call.argumentsJSON), let url = arguments["url"] as? String {
                failedDocuments[urlKey(url)] = call.id
            }
            if let content = object["content"] as? String, !content.isEmpty,
               passages.insert(content).inserted { newPassages += 1 }
            if let pages = object["pages"] as? [[String: Any]] {
                for page in pages {
                    if page["status"] as? String == ToolResultStatus.failure.rawValue {
                        if let url = page["source"] as? String { failedDocuments[urlKey(url)] = call.id }
                        continue
                    }
                    if let document = page["document"] as? [String: Any] {
                        if document["selection_status"] as? String == "dynamic_content_unavailable", let url = page["source"] as? String {
                            failedDocuments[urlKey(url)] = call.id
                            continue
                        }
                        let content = document["content"] as? String
                            ?? (try? JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) }
                        if let content, !content.isEmpty, passages.insert(content).inserted { newPassages += 1 }
                    }
                }
            } else if call.name == FetchUrlTool.name, !result.isError, object["content"] == nil {
                if passages.insert(result.content).inserted { newPassages += 1 }
            }
        }
        if newPassages > 0 { stalledSearches = 0 }
        else if call.name == WebSearchTool.name {
            stalledSearches = newSources == 0 ? stalledSearches + 1 : 0
        }
        // Keep the tool's evidence untouched. Only append mechanical progress data.
        guard var object = payload as? [String: Any],
              call.name == WebSearchTool.name || object["selection_status"] != nil else { return result }
        object["research_progress"] = ["new_source_count": newSources, "new_passage_count": newPassages,
                                       "searches_without_new_sources": stalledSearches]
        if newSources == 0, newPassages == 0 {
            object["next_action"] = "No new source or passage was added. Reuse previous evidence; inspect a new section/source for a named gap, otherwise conclude."
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return result }
        var updated = result
        updated.content = String(decoding: data, as: UTF8.self)
        return updated
    }

    private func fingerprint(_ call: ToolCall) -> String? {
        guard let arguments = try? ToolArguments.object(from: call.argumentsJSON) else { return nil }
        if call.name == WebSearchTool.name, let query = arguments["query"] as? String {
            var normalized = normalizedText(query)
            // Preserve quoted phrase semantics and boolean operator ordering.
            if !query.contains("\""), !query.contains("("), !query.contains("OR"), !query.contains("AND") {
                normalized = normalized.components(separatedBy: " ").sorted().joined(separator: " ")
            }
            return "search:" + normalized + ":" + normalizedText(arguments["goal"] as? String ?? "")
                + ":" + String(ToolArguments.int(arguments["max_results"]) ?? 8)
                + ":read_sources=" + String(arguments["read_sources"] as? Bool ?? false)
        }
        if call.name == FetchUrlTool.name, let url = arguments["url"] as? String {
            return "read:" + urlKey(url) + ":" + normalizedText(arguments["goal"] as? String ?? "")
                + ":" + (arguments["read_mode"] as? String ?? "relevant")
                + ":" + String(ToolArguments.int(arguments["start_paragraph"]) ?? 0)
                + ":" + String(ToolArguments.int(arguments["start_character"]) ?? 0)
                + ":" + String(ToolArguments.int(arguments["max_characters"]) ?? 4000)
        }
        return nil
    }

    private func normalizedText(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping.lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private func urlKey(_ value: String) -> String {
        var url = URLComponents(string: value)
        url?.fragment = nil
        return url?.string ?? value
    }

    private func stopped(_ call: ToolCall, reason: String, previous: String?, action: String) -> ToolResult {
        var object: [String: Any] = ["research_status": reason, "network_request_performed": false, "next_action": action]
        if let previous { object["previous_call_id"] = previous }
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data()
        DiagnosticsLogger.log("Web research redundant operation skipped", category: .network,
                              metadata: ["tool": call.name, "reason": reason])
        return ToolResult(callId: call.id, name: call.name, content: String(decoding: data, as: UTF8.self), status: .insufficient)
    }
}
