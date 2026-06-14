import Foundation

struct WebSearchTool: LocalToolExecutor {
    static let name = "web_search"

    let definition = ToolDefinition(
        name: name,
        description: "Search the public web. Returns up to 8 result titles, snippets, and URLs. Use fetch_url only when page text is needed.",
        parametersJSON: """
        {
          "type": "object",
          "properties": {
            "query": {
              "type": "string",
              "description": "The search query."
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

    private let engine: any SearchEngine
    private let locale: Locale

    init(
        engine: any SearchEngine = DuckDuckGoHTMLEngine(),
        locale: Locale = .current
    ) {
        self.engine = engine
        self.locale = locale
    }

    func execute(call: ToolCall) async throws -> ToolResult {
        let arguments = try ToolArguments.object(from: call.argumentsJSON)
        guard let query = (arguments["query"] as? String)?.trimmedNonEmpty else {
            throw ProviderClientError.parseFailure("web_search requires a non-empty query")
        }
        let requestedLimit = ToolArguments.int(arguments["max_results"]) ?? DuckDuckGoHTMLEngine.resultLimit
        let limit = min(max(1, requestedLimit), DuckDuckGoHTMLEngine.resultLimit)
        let results = try await engine.search(query: query, locale: locale, maxResults: limit)
        let object: [String: Any] = [
            "query": query,
            "results": results.map {
                [
                    "title": $0.title,
                    "snippet": $0.snippet,
                    "url": $0.url
                ]
            }
        ]
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
            sources: sources
        )
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
