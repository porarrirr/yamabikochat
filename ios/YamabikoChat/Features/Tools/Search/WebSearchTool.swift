import Foundation

struct WebSearchTool: LocalToolExecutor {
    static let name = "web_search"

    let definition = ToolDefinition(
        name: name,
        description: """
        Search the public web and return up to 8 result titles, snippets, and URLs. Supply goal for factual research: the top two results are also read concurrently and source passages are returned in the SAME call, avoiding a separate discovery/read round. Returned pages are evidence, not guaranteed answers; inspect dates, entities and contradictions. Omit goal only when discovering URLs or terminology. Use focused queries for current, uncertain, niche, or externally verifiable information. Read the best source before searching again. Preserve facts already found and search only for a specific unresolved gap. Do not repeat equivalent queries, including superficial word reordering. After two approaches without new evidence, report the gap and stop that branch. Search snippets are discovery aids; use fetch_url to inspect important original sources.
        """,
        parametersJSON: """
        {
          "type": "object",
          "properties": {
            "recover_cached": {
              "type": "boolean", "default": false,
              "description": "Use only if an earlier response is no longer available in the model context. Recover the same retrieved evidence without repeating network work when retained; not for routine retries."
            },
            "query": {
              "type": "string",
              "description": "The search query."
            },
            "goal": {
              "type": "string",
              "description": "The evidence needed for the answer. When supplied, read the top two search results concurrently and return their source passages in this same call."
            },
            "max_results": {
              "type": "integer",
              "minimum": 1,
              "maximum": 8,
              "default": 8
            }
          },
          "required": ["query"],
          "additionalProperties": false
        }
        """
    )

    private let searchCache = WebSearchResultCache()
    private let reader: FetchUrlTool
    private let engine: any SearchEngine
    private let locale: Locale

    init(
        engine: any SearchEngine = DuckDuckGoHTMLEngine(),
        locale: Locale = .current,
        reader: FetchUrlTool = FetchUrlTool()
    ) {
        self.reader = reader
        self.engine = engine
        self.locale = locale
    }

    func execute(call: ToolCall) async throws -> ToolResult {
        do {
            let arguments = try ToolArguments.object(from: call.argumentsJSON)
            guard let query = (arguments["query"] as? String)?.trimmedNonEmpty else {
                throw ProviderClientError.parseFailure("web_search requires a non-empty query")
            }
            let requestedLimit = ToolArguments.int(arguments["max_results"]) ?? DuckDuckGoHTMLEngine.resultLimit
            let limit = min(max(1, requestedLimit), DuckDuckGoHTMLEngine.resultLimit)
            let cacheKey = query.precomposedStringWithCompatibilityMapping.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ") + ":" + locale.identifier
            let cached = await searchCache.value(for: cacheKey)
            let allResults: [SearchResult]
            if let cached { allResults = cached }
            else {
                allResults = try await engine.search(query: query, locale: locale, maxResults: DuckDuckGoHTMLEngine.resultLimit)
                await searchCache.store(allResults, for: cacheKey)
            }
            let results = Array(allResults.prefix(limit))
            let goal = (arguments["goal"] as? String)?.trimmedNonEmpty
            let pages: [ToolResult]
            if let goal {
                pages = await withTaskGroup(of: (Int, ToolResult).self) { group in
                    for (index, result) in results.prefix(2).enumerated() {
                        group.addTask {
                            let arguments: [String: Any] = ["url": result.url, "goal": goal, "max_characters": 3000]
                            let json = (try? JSONSerialization.data(withJSONObject: arguments)).map { String(decoding: $0, as: UTF8.self) } ?? "{}"
                            let pageCall = ToolCall(id: "\(call.id)-source-\(index)", name: FetchUrlTool.name,
                                                    argumentsJSON: json, providerMetadata: nil)
                            do { return (index, try await reader.execute(call: pageCall)) }
                            catch { return (index, ToolResult(callId: pageCall.id, name: pageCall.name,
                                                             content: LocalToolRegistry.errorContent(error.localizedDescription), isError: true)) }
                        }
                    }
                    var collected: [(Int, ToolResult)] = []
                    for await item in group { collected.append(item) }
                    return collected.sorted { $0.0 < $1.0 }.map(\.1)
                }
                try Task.checkCancellation()
            } else { pages = [] }
            var object: [String: Any] = [
                "query": query,
                "search_cache_hit": cached != nil,
                "results": results.map { result -> [String: Any] in
                    [
                        "title": result.title,
                        "snippet": result.snippet,
                        "url": result.url,
                        "published_at": result.publishedAt ?? NSNull()
                    ]
                }
            ]
            if goal != nil {
                object["pages"] = pages.enumerated().map { index, page -> [String: Any] in
                    let payload = (try? JSONSerialization.jsonObject(with: Data(page.content.utf8))) ?? page.content
                    return ["source": page.provenance?.url ?? results[index].url, "status": page.status.rawValue, "document": payload]
                }
                object["next_action"] = "Evaluate the returned evidence now. Answer supported facts; read a specific unresolved document section or source link before another search."
            }
            let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            let content = String(decoding: data, as: UTF8.self)
            let sources = results.map { ToolSource(title: $0.title, url: $0.url) }

            DiagnosticsLogger.log(
                "Client web search completed",
                category: .network,
                metadata: [
                    "query": query,
                    "result_count": String(results.count)
                ]
            )
            return ToolResult(
                callId: call.id,
                name: call.name,
                content: content,
                status: results.isEmpty ? .insufficient : .complete,
                sources: sources
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            let query = Self.query(from: call.argumentsJSON) ?? "-"
            let limit = Self.limit(from: call.argumentsJSON)
            DiagnosticsLogger.log(
                "Client web search failed",
                level: .error,
                category: .network,
                metadata: [
                    "query": query,
                    "max_results": String(limit)
                ],
                error: error
            )
            return ToolResult(
                callId: call.id,
                name: call.name,
                content: LocalToolRegistry.errorContent(error.localizedDescription),
                isError: true
            )
        }
    }

    private static func query(from argumentsJSON: String) -> String? {
        guard let data = argumentsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let query = (object["query"] as? String)?.trimmedNonEmpty
        else {
            return nil
        }
        return query
    }

    private static func limit(from argumentsJSON: String) -> Int {
        guard let data = argumentsJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return DuckDuckGoHTMLEngine.resultLimit
        }
        let requestedLimit = ToolArguments.int(object["max_results"]) ?? DuckDuckGoHTMLEngine.resultLimit
        return min(max(1, requestedLimit), DuckDuckGoHTMLEngine.resultLimit)
    }
}

enum ToolArguments {
    static func object(from json: String) throws -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw ProviderClientError.parseFailure("Tool arguments must be a JSON object")
        }
        return object
    }

    static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }
}

private actor WebSearchResultCache {
    private var entries: [String: (Date, [SearchResult])] = [:]
    func value(for key: String) -> [SearchResult]? {
        entries = entries.filter { Date().timeIntervalSince($0.value.0) < 60 }
        return entries[key]?.1
    }
    func store(_ results: [SearchResult], for key: String) {
        if entries.count >= 16, let oldest = entries.min(by: { $0.value.0 < $1.value.0 })?.key { entries.removeValue(forKey: oldest) }
        entries[key] = (Date(), results)
    }
}
