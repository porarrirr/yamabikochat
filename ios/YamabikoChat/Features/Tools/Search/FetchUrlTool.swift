import Foundation

struct FetchUrlTool: LocalToolExecutor {
    static let name = "fetch_url"
    static let maxCharacters = 8_000
    static let maxResponseBytes = 2 * 1024 * 1024
    static let requestTimeout: TimeInterval = 15

    let definition = ToolDefinition(
        name: name,
        description: """
        Read an HTTP or HTTPS page for a specific goal and return the most relevant passages with nearby context, up to 8000 characters. Use it only after evaluating web_search snippets. Prefer primary or authoritative pages. Do not claim support for information absent from the returned content.
        """,
        parametersJSON: """
        {
          "type": "object",
          "properties": {
            "url": {
              "type": "string",
              "description": "The HTTP or HTTPS URL to fetch."
            },
            "goal": {
              "type": "string",
              "description": "The specific facts or question to investigate on this page."
            }
          },
          "required": ["url", "goal"],
          "additionalProperties": false
        }
        """
    )

    private let httpClient: any WebToolHTTPClient

    init(httpClient: any WebToolHTTPClient = URLSessionWebToolHTTPClient()) {
        self.httpClient = httpClient
    }

    func execute(call: ToolCall) async throws -> ToolResult {
        let arguments = try ToolArguments.object(from: call.argumentsJSON)
        guard let goal = (arguments["goal"] as? String)?.trimmedNonEmpty else {
            throw ProviderClientError.parseFailure("fetch_url requires a non-empty goal")
        }
        guard let rawURL = (arguments["url"] as? String)?.trimmedNonEmpty,
              let url = URL(string: rawURL),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.trimmedNonEmpty != nil
        else {
            throw ProviderClientError.invalidBaseURL((arguments["url"] as? String) ?? "")
        }
        try WebToolURLPolicy.validatePublicHTTPURL(url)

        let (data, response) = try await httpClient.get(url: url, timeout: Self.requestTimeout)
        if let finalURL = response.url {
            try WebToolURLPolicy.validatePublicHTTPURL(finalURL)
        }
        guard (200 ... 299).contains(response.statusCode) else {
            throw ProviderClientError.httpStatus(response.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        guard data.count <= Self.maxResponseBytes else {
            throw ProviderClientError.parseFailure("Fetched page exceeds the 2 MB response limit")
        }
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        guard contentType.isEmpty ||
            contentType.contains("text/") ||
            contentType.contains("application/xhtml+xml")
        else {
            throw ProviderClientError.parseFailure("Unsupported fetched content type: \(contentType)")
        }
        guard let rawText = String(data: data, encoding: .utf8) ??
            String(data: data, encoding: .isoLatin1)
        else {
            throw ProviderClientError.parseFailure("Fetched page encoding is unsupported")
        }

        let paragraphs = contentType.contains("text/plain")
            ? PageParagraphExtractor.extractPlainText(rawText)
            : PageParagraphExtractor.extractHTML(rawText)
        guard !paragraphs.isEmpty else {
            throw ProviderClientError.parseFailure("Fetched page did not contain readable text")
        }
        let selection = RelevantPageReader.select(
            paragraphs: paragraphs,
            goal: goal,
            maxCharacters: Self.maxCharacters
        )

        let title = Self.extractTitle(from: rawText) ?? url.host ?? url.absoluteString
        let object: [String: Any] = [
            "url": url.absoluteString,
            "title": title,
            "goal": goal,
            "content": selection.content,
            "selection_status": selection.status.rawValue,
            "selected_paragraph_count": selection.selectedParagraphCount,
            "truncated": selection.truncated
        ]
        let outputData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        DiagnosticsLogger.log(
            "Client URL fetch completed",
            category: .network,
            metadata: [
                "url": url.absoluteString,
                "character_count": String(selection.content.count),
                "selection_status": selection.status.rawValue,
                "selected_paragraph_count": String(selection.selectedParagraphCount)
            ]
        )
        return ToolResult(
            callId: call.id,
            name: call.name,
            content: String(decoding: outputData, as: UTF8.self),
            sources: [ToolSource(title: title, url: url.absoluteString)]
        )
    }

    private static func extractTitle(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"(?is)<title\b[^>]*>(.*?)</title>"#),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let range = Range(match.range(at: 1), in: html)
        else {
            return nil
        }
        return HTMLTextExtractor.extract(from: String(html[range]), maxCharacters: 300).trimmedNonEmpty
    }
}
