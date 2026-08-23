import Foundation

private enum FetchUrlToolError: LocalizedError {
    case httpStatus(Int, host: String)

    var errorDescription: String? {
        switch self {
        case let .httpStatus(status, host):
            return "fetch_url received HTTP \(status) from \(host)"
        }
    }
}

struct FetchUrlTool: LocalToolExecutor {
    static let name = "fetch_url"
    static let maxCharacters = 8_000
    static let maxResponseBytes = 2 * 1024 * 1024
    static let requestTimeout: TimeInterval = 15
    static let renderTimeout: TimeInterval = 15

    let definition = ToolDefinition(
        name: name,
        description: """
        Read an HTTP or HTTPS page for a specific goal and return the most relevant passages with nearby context, up to 8000 characters. Dynamic HTML may be rendered privately when the lightweight fetch is insufficient. Use it only after evaluating web_search snippets. Prefer primary or authoritative pages. Treat only selection_status=selected as sufficient evidence; partial_match, no_relevant_passages, dynamic_content_unavailable, and render_outcome values access_restricted, timed_out, or failed require another source or a narrower goal. Do not claim support for information absent from the returned content.
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
    private let renderedPageLoader: any RenderedPageContentLoading
    private let concurrencyLimiter: any WebFetchConcurrencyLimiting

    init(
        httpClient: any WebToolHTTPClient = URLSessionWebToolHTTPClient(),
        renderedPageLoader: any RenderedPageContentLoading = WKRenderedPageContentLoader.shared,
        concurrencyLimiter: any WebFetchConcurrencyLimiting = WebFetchConcurrencyLimiter.shared
    ) {
        self.httpClient = httpClient
        self.renderedPageLoader = renderedPageLoader
        self.concurrencyLimiter = concurrencyLimiter
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

        let startedAt = Date()
        let (data, response) = try await limitedHTTPGet(url: url)
        if let finalURL = response.url {
            try WebToolURLPolicy.validatePublicHTTPURL(finalURL)
        }
        guard (200 ... 299).contains(response.statusCode) else {
            throw FetchUrlToolError.httpStatus(
                response.statusCode,
                host: url.host ?? "the requested host"
            )
        }
        guard data.count <= Self.maxResponseBytes else {
            throw ProviderClientError.parseFailure("Fetched page exceeds the 2 MB response limit")
        }
        let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        let mediaType = contentType
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let isJSON = mediaType == "application/json" ||
            mediaType.hasSuffix("+json") ||
            url.pathExtension.caseInsensitiveCompare("json") == .orderedSame
        guard contentType.isEmpty ||
            contentType.contains("text/") ||
            contentType.contains("application/xhtml+xml") ||
            isJSON
        else {
            throw ProviderClientError.parseFailure("Unsupported fetched content type: \(contentType)")
        }
        let rawText: String
        let paragraphs: [PageParagraph]
        if isJSON {
            do {
                paragraphs = try PageParagraphExtractor.extractJSON(data)
            } catch {
                throw ProviderClientError.parseFailure("Fetched JSON is invalid")
            }
            rawText = ""
        } else {
            guard let decoded = String(data: data, encoding: .utf8) ??
                String(data: data, encoding: .isoLatin1)
            else {
                throw ProviderClientError.parseFailure("Fetched page encoding is unsupported")
            }
            rawText = decoded
            paragraphs = contentType.contains("text/plain")
                ? PageParagraphExtractor.extractPlainText(rawText)
                : PageParagraphExtractor.extractHTML(rawText)
        }
        var selection = RelevantPageReader.select(
            paragraphs: paragraphs,
            goal: goal,
            maxCharacters: Self.maxCharacters
        )
        var title = (isJSON ? nil : Self.extractTitle(from: rawText)) ?? url.host ?? url.absoluteString
        var fetchMethod = FetchMethod.urlSession
        var renderAttempted = false
        var renderOutcome = RenderOutcome.notAttempted

        if !isJSON,
           !contentType.contains("text/plain"),
           selection.status != .selected {
            renderAttempted = true
            do {
                let renderedResult = try await limitedRenderedLoad(url: url)
                switch renderedResult {
                case let .accessRestricted(reason):
                    renderOutcome = .accessRestricted
                    DiagnosticsLogger.log(
                        "Rendered page access restricted",
                        level: .warning,
                        category: .network,
                        metadata: [
                            "url": url.absoluteString,
                            "reason": reason
                        ]
                    )
                case let .loaded(rendered):
                    let renderedSelection = RelevantPageReader.select(
                        paragraphs: rendered.paragraphs,
                        goal: goal,
                        maxCharacters: Self.maxCharacters
                    )
                    renderOutcome = RenderOutcome(selectionStatus: renderedSelection.status)
                    if Self.shouldPrefer(
                        renderedSelection,
                        renderedParagraphCount: rendered.paragraphs.count,
                        over: selection,
                        staticParagraphCount: paragraphs.count
                    ) {
                        selection = renderedSelection
                        title = rendered.title ?? title
                        fetchMethod = .webKit
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                renderOutcome = error as? RenderedPageLoaderError == .timedOut ? .timedOut : .failed
                DiagnosticsLogger.log(
                    "Rendered page fetch failed",
                    level: .warning,
                    category: .network,
                    metadata: ["url": url.absoluteString],
                    error: error
                )
            }
        }

        let object: [String: Any] = [
            "url": url.absoluteString,
            "title": title,
            "goal": goal,
            "content": selection.content,
            "selection_status": selection.status.rawValue,
            "selected_paragraph_count": selection.selectedParagraphCount,
            "truncated": selection.truncated,
            "fetch_method": fetchMethod.rawValue,
            "render_attempted": renderAttempted,
            "render_outcome": renderOutcome.rawValue
        ]
        let outputData = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        DiagnosticsLogger.log(
            "Client URL fetch completed",
            category: .network,
            metadata: [
                "url": url.absoluteString,
                "character_count": String(selection.content.count),
                "selection_status": selection.status.rawValue,
                "selected_paragraph_count": String(selection.selectedParagraphCount),
                "fetch_method": fetchMethod.rawValue,
                "render_attempted": String(renderAttempted),
                "render_outcome": renderOutcome.rawValue,
                "duration_ms": String(Int(Date().timeIntervalSince(startedAt) * 1_000))
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

    private func limitedHTTPGet(url: URL) async throws -> (Data, HTTPURLResponse) {
        try await concurrencyLimiter.acquire(.http)
        do {
            let result = try await httpClient.get(url: url, timeout: Self.requestTimeout)
            await concurrencyLimiter.release(.http)
            return result
        } catch {
            await concurrencyLimiter.release(.http)
            throw error
        }
    }

    private func limitedRenderedLoad(url: URL) async throws -> RenderedPageLoadResult {
        try await concurrencyLimiter.acquire(.webKit)
        do {
            let result = try await renderedPageLoader.load(url: url, timeout: Self.renderTimeout)
            await concurrencyLimiter.release(.webKit)
            return result
        } catch {
            await concurrencyLimiter.release(.webKit)
            throw error
        }
    }

    private static func shouldPrefer(
        _ rendered: RelevantPageSelection,
        renderedParagraphCount: Int,
        over staticSelection: RelevantPageSelection,
        staticParagraphCount: Int
    ) -> Bool {
        let renderedRank = selectionRank(rendered.status)
        let staticRank = selectionRank(staticSelection.status)
        if renderedRank != staticRank {
            return renderedRank > staticRank
        }
        guard !rendered.content.isEmpty else { return false }
        if rendered.selectedParagraphCount != staticSelection.selectedParagraphCount {
            return rendered.selectedParagraphCount > staticSelection.selectedParagraphCount
        }
        return renderedParagraphCount > staticParagraphCount
    }

    private static func selectionRank(_ status: RelevantPageSelection.Status) -> Int {
        switch status {
        case .selected:
            3
        case .partialMatch:
            2
        case .noRelevantPassages:
            1
        case .dynamicContentUnavailable:
            0
        }
    }

    private enum FetchMethod: String {
        case urlSession = "url_session"
        case webKit = "webkit"
    }

    private enum RenderOutcome: String {
        case notAttempted = "not_attempted"
        case selected
        case partialMatch = "partial_match"
        case noRelevantPassages = "no_relevant_passages"
        case dynamicContentUnavailable = "dynamic_content_unavailable"
        case accessRestricted = "access_restricted"
        case timedOut = "timed_out"
        case failed

        init(selectionStatus: RelevantPageSelection.Status) {
            switch selectionStatus {
            case .selected:
                self = .selected
            case .partialMatch:
                self = .partialMatch
            case .noRelevantPassages:
                self = .noRelevantPassages
            case .dynamicContentUnavailable:
                self = .dynamicContentUnavailable
            }
        }
    }
}
