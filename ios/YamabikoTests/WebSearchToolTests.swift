import XCTest
import WebKit
@testable import YamabikoChat

private actor RecordingWebToolHTTPClient: WebToolHTTPClient {
    private(set) var requestedURLs: [URL] = []

    func get(url: URL, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        requestedURLs.append(url)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/plain"]
        )!
        return (Data("ok".utf8), response)
    }
}

private actor FailingWebToolHTTPClient: WebToolHTTPClient {
    let statusCode: Int
    let body: String

    init(statusCode: Int = 500, body: String = "server error") {
        self.statusCode = statusCode
        self.body = body
    }

    func get(url: URL, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/plain"]
        )!
        return (Data(body.utf8), response)
    }
}

private actor StaticWebToolHTTPClient: WebToolHTTPClient {
    let body: String
    let contentType: String

    init(body: String, contentType: String = "text/html") {
        self.body = body
        self.contentType = contentType
    }

    func get(url: URL, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": contentType]
        )!
        return (Data(body.utf8), response)
    }
}

@MainActor
private final class RecordingRenderedPageLoader: RenderedPageContentLoading, @unchecked Sendable {
    var result: Result<RenderedPageLoadResult, Error>
    private(set) var callCount = 0
    private(set) var activeCount = 0
    private(set) var maximumActiveCount = 0
    var delay: Duration?

    init(
        result: Result<RenderedPageLoadResult, Error> = .success(.accessRestricted(reason: "test_restricted")),
        delay: Duration? = nil
    ) {
        self.result = result
        self.delay = delay
    }

    func load(url: URL, timeout: TimeInterval) async throws -> RenderedPageLoadResult {
        callCount += 1
        activeCount += 1
        maximumActiveCount = max(maximumActiveCount, activeCount)
        defer { activeCount -= 1 }
        if let delay {
            try await Task.sleep(for: delay)
        }
        return try result.get()
    }
}

private actor URLRoutingWebToolHTTPClient: WebToolHTTPClient {
    func get(url: URL, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        let fails = url.path.contains("fail")
        let response = HTTPURLResponse(
            url: url,
            statusCode: fails ? 500 : 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/html"]
        )!
        let body = fails
            ? "server error"
            : "<title>Guide</title><main><p>Odette recommended party details.</p></main>"
        return (Data(body.utf8), response)
    }
}

private struct StaticSearchEngine: SearchEngine {
    let results: [SearchResult]

    func search(query: String, locale: Locale, maxResults: Int) async throws -> [SearchResult] {
        Array(results.prefix(maxResults))
    }
}

final class WebSearchToolTests: XCTestCase {
    func testDuckDuckGoHTMLParserExtractsResultsAndDecodesRedirectURL() throws {
        let html = """
        <div class="result">
          <a rel="nofollow" class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fexample.com%2Farticle&amp;rut=abc">
            Example &amp; Article
          </a>
          <a class="result__snippet">A <b>useful</b> summary &amp; details.</a>
        </div>
        """

        let results = DuckDuckGoHTMLEngine.parseResults(html: html)

        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].title, "Example & Article")
        XCTAssertEqual(results[0].snippet, "A useful summary & details.")
        XCTAssertEqual(results[0].url, "https://example.com/article")
    }

    func testDuckDuckGoLiteParserUsesNofollowLinks() {
        let html = """
        <table>
          <tr><td><a rel="nofollow" href="https://example.org/page">Lite Result</a></td></tr>
          <tr><td class="result-snippet">Lite snippet text</td></tr>
        </table>
        """

        let results = DuckDuckGoHTMLEngine.parseResults(html: html)

        XCTAssertEqual(results, [
            SearchResult(
                title: "Lite Result",
                snippet: "Lite snippet text",
                url: "https://example.org/page"
            )
        ])
    }

    func testHTMLTextExtractorRemovesInvisibleContentAndDecodesEntities() {
        let html = """
        <html>
          <head><style>.hidden { display: none; }</style><script>alert(1)</script></head>
          <body><h1>Title &amp; More</h1><p>Hello&nbsp;<b>world</b>.</p></body>
        </html>
        """

        let text = HTMLTextExtractor.extract(from: html)

        XCTAssertEqual(text, "Title & More\nHello world .")
        XCTAssertFalse(text.contains("alert"))
        XCTAssertFalse(text.contains("display"))
    }

    func testHTMLTextExtractorAppliesCharacterLimit() {
        let text = HTMLTextExtractor.extract(
            from: "<p>\(String(repeating: "a", count: 9_000))</p>",
            maxCharacters: 8_000
        )

        XCTAssertEqual(text.count, 8_000)
    }

    func testParagraphExtractorRemovesNavigationAdvertisingAndFooterContainers() {
        let html = """
        <header><p>Site title</p></header>
        <nav><li>Menu item</li></nav>
        <div class="advertisement"><p>Buy this product</p></div>
        <main><h1>Article</h1><p>Important article body.</p></main>
        <footer><p>Copyright notice</p></footer>
        """

        let paragraphs = PageParagraphExtractor.extractHTML(html)

        XCTAssertEqual(paragraphs.map(\.text), ["Important article body."])
        XCTAssertEqual(paragraphs.first?.heading, "Article")
    }

    func testParagraphExtractorPreservesHeadingAndDocumentOrder() {
        let html = """
        <script><p>Invisible</p></script>
        <h1>Overview &amp; Details</h1>
        <p>First <b>paragraph</b>.</p>
        <h2>Recommended Party</h2>
        <li>Odette is the main attacker.</li>
        <p>Sandrone provides support.</p>
        """

        let paragraphs = PageParagraphExtractor.extractHTML(html)

        XCTAssertEqual(paragraphs.map(\.index), [0, 1, 2])
        XCTAssertEqual(paragraphs.map(\.heading), ["Overview & Details", "Recommended Party", "Recommended Party"])
        XCTAssertEqual(
            paragraphs.map(\.text),
            ["First paragraph .", "Odette is the main attacker.", "Sandrone provides support."]
        )
        XCTAssertFalse(paragraphs.map(\.text).joined().contains("Invisible"))
    }

    func testPlainTextExtractorGroupsLinesSeparatedByBlankLines() {
        let paragraphs = PageParagraphExtractor.extractPlainText("First line\ncontinued\n\nSecond paragraph")

        XCTAssertEqual(paragraphs.map(\.text), ["First line\ncontinued", "Second paragraph"])
        XCTAssertEqual(paragraphs.map(\.index), [0, 1])
    }

    func testJSONExtractorPreservesPathsAndScalarValues() throws {
        let data = Data(#"{"city":"東京","forecast":{"high":33,"rain":true},"alerts":[]}"#.utf8)

        let paragraphs = try PageParagraphExtractor.extractJSON(data)

        XCTAssertEqual(
            paragraphs.map(\.text),
            ["$.alerts: []", "$.city: \"東京\"", "$.forecast.high: 33", "$.forecast.rain: true"]
        )
    }

    func testRelevantPageReaderSelectsLateHitWithContextInOriginalOrder() {
        let paragraphs = [
            PageParagraph(index: 0, heading: "Intro", text: "Unrelated introduction."),
            PageParagraph(index: 1, heading: "Other", text: "Another topic."),
            PageParagraph(index: 2, heading: "Party", text: "Context before the recommendation."),
            PageParagraph(index: 3, heading: "Party", text: "Odette, Sandrone, and Escoffier form the best party."),
            PageParagraph(index: 4, heading: "Party", text: "Sandrone supports Odette in this composition."),
            PageParagraph(index: 5, heading: "Footer", text: "Unrelated footer.")
        ]

        let selection = RelevantPageReader.select(
            paragraphs: paragraphs,
            goal: "Odette best party Sandrone Escoffier",
            maxCharacters: 8_000,
            seedLimit: 1
        )

        XCTAssertEqual(selection.status, .selected)
        XCTAssertEqual(selection.selectedParagraphCount, 3)
        XCTAssertTrue(selection.content.contains("Context before"))
        XCTAssertTrue(selection.content.contains("form the best party"))
        XCTAssertTrue(selection.content.contains("supports Odette"))
        XCTAssertLessThan(
            selection.content.range(of: "Context before")!.lowerBound,
            selection.content.range(of: "form the best party")!.lowerBound
        )
    }

    func testRelevantPageReaderNormalizesJapaneseWidthAndRewardsExactTerms() {
        let paragraphs = [
            PageParagraph(index: 0, heading: "一般情報", text: "別のキャラクターについて説明します。"),
            PageParagraph(index: 1, heading: "おすすめパーティー", text: "オデットとサンドローネを編成します。")
        ]

        let selection = RelevantPageReader.select(
            paragraphs: paragraphs,
            goal: "オデット　最適パーティー　ＳＡＮＤＲＯＮＥ サンドローネ",
            maxCharacters: 8_000,
            seedLimit: 1,
            contextRadius: 0
        )

        XCTAssertEqual(selection.content, "## おすすめパーティー\n\nオデットとサンドローネを編成します。")
    }

    func testRelevantPageReaderReturnsExplicitNoMatchWithoutLeadingFallback() {
        let selection = RelevantPageReader.select(
            paragraphs: [PageParagraph(index: 0, heading: "Cooking", text: "Bake bread slowly.")],
            goal: "quantum entanglement experiment",
            maxCharacters: 8_000
        )

        XCTAssertEqual(selection.status, .noRelevantPassages)
        XCTAssertEqual(selection.content, "")
        XCTAssertEqual(selection.selectedParagraphCount, 0)
        XCTAssertFalse(selection.truncated)
    }

    func testRelevantPageReaderKeepsBestSeedAndLimitsOversizedContent() {
        let oversized = "Odette " + String(repeating: "party ", count: 2_000)
        let selection = RelevantPageReader.select(
            paragraphs: [PageParagraph(index: 0, heading: "Party", text: oversized)],
            goal: "Odette party",
            maxCharacters: 500
        )

        XCTAssertEqual(selection.content.count, 500)
        XCTAssertTrue(selection.content.contains("Odette"))
        XCTAssertTrue(selection.truncated)
        XCTAssertEqual(selection.selectedParagraphCount, 1)
    }

    func testRelevantPageReaderMergesOverlappingContextWindows() {
        let paragraphs = (0 ..< 4).map {
            PageParagraph(index: $0, heading: "Party", text: "Odette party paragraph \($0)")
        }
        let selection = RelevantPageReader.select(
            paragraphs: paragraphs,
            goal: "Odette party",
            maxCharacters: 8_000,
            seedLimit: 2,
            contextRadius: 1
        )

        XCTAssertEqual(selection.selectedParagraphCount, 3)
        XCTAssertEqual(selection.content.components(separatedBy: "Odette party paragraph 1").count - 1, 1)
    }

    func testLocaleMapsJapaneseToDuckDuckGoJapanRegion() {
        XCTAssertEqual(
            DuckDuckGoHTMLEngine.regionParameter(for: Locale(identifier: "ja_JP")),
            "jp-jp"
        )
    }

    func testDuckDuckGoExtractsOnlyExplicitPublishedDates() {
        XCTAssertEqual(
            DuckDuckGoHTMLEngine.extractPublishedDate(from: "2026年8月14日 — 更新情報"),
            "2026-08-14"
        )
        XCTAssertEqual(
            DuckDuckGoHTMLEngine.extractPublishedDate(from: "Aug 14, 2026 — Release notes"),
            "2026-08-14"
        )
        XCTAssertNil(DuckDuckGoHTMLEngine.extractPublishedDate(from: "2 days ago — News"))
        XCTAssertNil(DuckDuckGoHTMLEngine.extractPublishedDate(from: "2026-02-30 — Invalid"))
    }

    func testDuckDuckGoParserAddsPublishedDateWhenSnippetContainsOne() {
        let html = """
        <a class="result__a" href="https://example.com/news">News</a>
        <div class="result__snippet">2026-08-14 — Important update.</div>
        """

        XCTAssertEqual(
            DuckDuckGoHTMLEngine.parseResults(html: html).first?.publishedAt,
            "2026-08-14"
        )
    }

    func testWebSearchOutputAlwaysIncludesPublishedAt() async throws {
        let tool = WebSearchTool(
            engine: StaticSearchEngine(results: [
                SearchResult(title: "Dated", snippet: "News", url: "https://example.com/dated", publishedAt: "2026-08-14"),
                SearchResult(title: "Undated", snippet: "Guide", url: "https://example.com/undated")
            ])
        )
        let result = try await tool.execute(
            call: ToolCall(
                id: "call-search",
                name: WebSearchTool.name,
                argumentsJSON: #"{"query":"example"}"#,
                providerMetadata: nil
            )
        )
        let data = try XCTUnwrap(result.content.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let results = try XCTUnwrap(object["results"] as? [[String: Any]])

        XCTAssertEqual(results[0]["published_at"] as? String, "2026-08-14")
        XCTAssertTrue(results[1]["published_at"] is NSNull)
    }

    func testFetchURLDefinitionRequiresGoal() throws {
        let schemaData = try XCTUnwrap(FetchUrlTool().definition.parametersJSON.data(using: .utf8))
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: schemaData) as? [String: Any])

        XCTAssertEqual(schema["required"] as? [String], ["url", "goal"])
    }

    func testFetchURLRejectsEmptyGoalBeforeNetworkRequest() async throws {
        let httpClient = RecordingWebToolHTTPClient()
        let tool = FetchUrlTool(httpClient: httpClient)

        do {
            _ = try await tool.execute(
                call: ToolCall(
                    id: "call-empty-goal",
                    name: FetchUrlTool.name,
                    argumentsJSON: #"{"url":"https://example.com","goal":"  "}"#,
                    providerMetadata: nil
                )
            )
            XCTFail("Expected an empty goal to be rejected")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("non-empty goal"))
        }

        let requestedURLs = await httpClient.requestedURLs
        XCTAssertTrue(requestedURLs.isEmpty)
    }

    func testFetchURLReturnsGoalAwareSelectionMetadata() async throws {
        let renderedLoader = await RecordingRenderedPageLoader()
        let tool = FetchUrlTool(
            httpClient: StaticWebToolHTTPClient(
                body: """
                <title>Party Guide</title>
                <h2>Recommended Party</h2>
                <p>Context before.</p>
                <p>Odette and Sandrone are the recommended party.</p>
                <p>Context after.</p>
                """
            ),
            renderedPageLoader: renderedLoader
        )
        let result = try await tool.execute(
            call: ToolCall(
                id: "call-fetch",
                name: FetchUrlTool.name,
                argumentsJSON: #"{"url":"https://example.com/guide","goal":"Odette recommended party"}"#,
                providerMetadata: nil
            )
        )
        let data = try XCTUnwrap(result.content.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["goal"] as? String, "Odette recommended party")
        XCTAssertEqual(object["selection_status"] as? String, "selected")
        XCTAssertEqual(object["selected_paragraph_count"] as? Int, 3)
        XCTAssertEqual(object["truncated"] as? Bool, false)
        XCTAssertTrue((object["content"] as? String)?.contains("Context before") == true)
        XCTAssertEqual(object["fetch_method"] as? String, "url_session")
        XCTAssertEqual(object["render_attempted"] as? Bool, false)
        XCTAssertEqual(object["render_outcome"] as? String, "not_attempted")
        let renderCallCount = await renderedLoader.callCount
        XCTAssertEqual(renderCallCount, 0)
    }

    func testFetchURLRejectsUnrenderedDynamicPageAsSelectedEvidence() async throws {
        let renderedLoader = await RecordingRenderedPageLoader()
        let tool = FetchUrlTool(
            httpClient: StaticWebToolHTTPClient(
                body: """
                <title>東京の天気</title>
                <h2>東京都の各地の天気</h2>
                <p>ライブ放送中 {{ content.title }}</p>
                <p>8月22日の各地の気温変化と服装情報</p>
                """
            ),
            renderedPageLoader: renderedLoader
        )
        let result = try await tool.execute(
            call: ToolCall(
                id: "call-dynamic",
                name: FetchUrlTool.name,
                argumentsJSON: #"{"url":"https://example.com/tokyo","goal":"東京 今日の天気 最高 最低気温"}"#,
                providerMetadata: nil
            )
        )
        let data = try XCTUnwrap(result.content.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["selection_status"] as? String, "dynamic_content_unavailable")
        XCTAssertEqual(object["selected_paragraph_count"] as? Int, 0)
        XCTAssertEqual(object["content"] as? String, "")
        XCTAssertEqual(object["render_attempted"] as? Bool, true)
        XCTAssertEqual(object["render_outcome"] as? String, "access_restricted")
    }

    func testFetchURLDoesNotSelectPassagesMissingMostGoalTerms() async throws {
        let renderedLoader = await RecordingRenderedPageLoader()
        let tool = FetchUrlTool(
            httpClient: StaticWebToolHTTPClient(
                body: """
                <title>東京のお知らせ</title>
                <h2>東京都の各地の天気</h2>
                <p>明日は全国的に気温が変化します。</p>
                """
            ),
            renderedPageLoader: renderedLoader
        )
        let result = try await tool.execute(
            call: ToolCall(
                id: "call-incomplete",
                name: FetchUrlTool.name,
                argumentsJSON: #"{"url":"https://example.com/tokyo","goal":"東京 今日の天気 最高 最低気温"}"#,
                providerMetadata: nil
            )
        )
        let data = try XCTUnwrap(result.content.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["selection_status"] as? String, "partial_match")
        XCTAssertFalse((object["content"] as? String)?.isEmpty ?? true)
    }

    func testFetchURLUsesRenderedDOMWhenStaticHTMLIsDynamicShell() async throws {
        let renderedLoader = await RecordingRenderedPageLoader(result: .success(.loaded(
            RenderedPageContent(
                title: "Rendered Party Guide",
                finalURL: URL(string: "https://example.com/dynamic")!,
                paragraphs: [
                    PageParagraph(index: 0, heading: "Recommended Party", text: "Odette and Sandrone are the recommended party."),
                    PageParagraph(index: 1, heading: "Recommended Party", text: "Escoffier completes the party composition.")
                ]
            )
        )))
        let tool = FetchUrlTool(
            httpClient: StaticWebToolHTTPClient(body: "<title>Loading</title><div id=app>{{ content }}</div>"),
            renderedPageLoader: renderedLoader
        )

        let result = try await tool.execute(call: ToolCall(
            id: "call-rendered",
            name: FetchUrlTool.name,
            argumentsJSON: #"{"url":"https://example.com/dynamic","goal":"Odette Sandrone Escoffier recommended party"}"#,
            providerMetadata: nil
        ))
        let data = try XCTUnwrap(result.content.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["selection_status"] as? String, "selected")
        XCTAssertEqual(object["fetch_method"] as? String, "webkit")
        XCTAssertEqual(object["render_outcome"] as? String, "selected")
        XCTAssertEqual(object["title"] as? String, "Rendered Party Guide")
        XCTAssertTrue((object["content"] as? String)?.contains("Escoffier") == true)
    }

    @MainActor
    func testRenderedDOMJavaScriptReadsDelayedContentAndRemovesPageChrome() async throws {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.loadHTMLString(
            """
            <html><head><title>Dynamic Article</title></head><body>
              <header><p>Site heading</p></header>
              <nav><li>Menu link</li></nav>
              <main><h1>Recommended Party</h1><p id="content">Loading</p></main>
              <div class="advertisement"><p>Advertisement text</p></div>
              <footer><p>Copyright footer</p></footer>
              <script>
                setTimeout(() => {
                  document.getElementById('content').textContent = 'Odette and Sandrone are the recommended party.';
                }, 100);
              </script>
            </body></html>
            """,
            baseURL: URL(string: "https://example.com/article")
        )
        var dynamicContentLoaded = false
        for _ in 0 ..< 30 {
            if let text = try? await webView.evaluateJavaScript("document.body?.innerText || ''") as? String,
               text.contains("Odette and Sandrone") {
                dynamicContentLoaded = true
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(dynamicContentLoaded)

        let value = try await webView.evaluateJavaScript(
            WKRenderedPageContentLoader.extractionJavaScriptForTesting
        )
        let json = try XCTUnwrap(value as? String)
        let data = try XCTUnwrap(json.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let paragraphs = try XCTUnwrap(object["paragraphs"] as? [[String: Any]])
        let combined = paragraphs.compactMap { $0["text"] as? String }.joined(separator: "\n")

        XCTAssertEqual(object["title"] as? String, "Dynamic Article")
        XCTAssertTrue(combined.contains("Odette and Sandrone"))
        XCTAssertFalse(combined.contains("Menu link"))
        XCTAssertFalse(combined.contains("Advertisement text"))
        XCTAssertFalse(combined.contains("Copyright footer"))
    }

    func testFetchURLReportsRenderedTimeoutWithoutDiscardingStaticPartialContent() async throws {
        let renderedLoader = await RecordingRenderedPageLoader(result: .failure(RenderedPageLoaderError.timedOut))
        let tool = FetchUrlTool(
            httpClient: StaticWebToolHTTPClient(body: "<p>Odette party overview.</p>"),
            renderedPageLoader: renderedLoader
        )

        let result = try await tool.execute(call: ToolCall(
            id: "call-timeout",
            name: FetchUrlTool.name,
            argumentsJSON: #"{"url":"https://example.com/slow","goal":"Odette Sandrone party"}"#,
            providerMetadata: nil
        ))
        let data = try XCTUnwrap(result.content.data(using: .utf8))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["fetch_method"] as? String, "url_session")
        XCTAssertEqual(object["render_attempted"] as? Bool, true)
        XCTAssertEqual(object["render_outcome"] as? String, "timed_out")
        XCTAssertEqual(object["selection_status"] as? String, "partial_match")
        XCTAssertTrue((object["content"] as? String)?.contains("Odette") == true)
    }

    func testWebKitFallbackIsSerializedAcrossMultiplePages() async throws {
        let renderedLoader = await RecordingRenderedPageLoader(
            result: .success(.loaded(RenderedPageContent(
                title: "Rendered",
                finalURL: URL(string: "https://example.com/page")!,
                paragraphs: [PageParagraph(index: 0, heading: nil, text: "Odette recommended party")]
            ))),
            delay: .milliseconds(100)
        )
        let limiter = WebFetchConcurrencyLimiter(httpLimit: 3, webKitLimit: 1)
        let tool = FetchUrlTool(
            httpClient: StaticWebToolHTTPClient(body: "<div id=app></div>"),
            renderedPageLoader: renderedLoader,
            concurrencyLimiter: limiter
        )

        async let first = tool.execute(call: ToolCall(
            id: "page-1",
            name: FetchUrlTool.name,
            argumentsJSON: #"{"url":"https://example.com/one","goal":"Odette party"}"#,
            providerMetadata: nil
        ))
        async let second = tool.execute(call: ToolCall(
            id: "page-2",
            name: FetchUrlTool.name,
            argumentsJSON: #"{"url":"https://example.com/two","goal":"Odette party"}"#,
            providerMetadata: nil
        ))
        _ = try await (first, second)

        let maximumActiveCount = await renderedLoader.maximumActiveCount
        XCTAssertEqual(maximumActiveCount, 1)
    }

    func testMultipleFetchesContinueWhenOnePageFails() async throws {
        let registry = LocalToolRegistry(executors: [
            FetchUrlTool(httpClient: URLRoutingWebToolHTTPClient())
        ])

        async let failed = registry.execute(call: ToolCall(
            id: "failed-page",
            name: FetchUrlTool.name,
            argumentsJSON: #"{"url":"https://example.com/fail","goal":"Odette recommended party"}"#,
            providerMetadata: nil
        ))
        async let succeeded = registry.execute(call: ToolCall(
            id: "successful-page",
            name: FetchUrlTool.name,
            argumentsJSON: #"{"url":"https://example.com/success","goal":"Odette recommended party"}"#,
            providerMetadata: nil
        ))
        let results = await (failed, succeeded)

        XCTAssertTrue(results.0.isError)
        XCTAssertFalse(results.1.isError)
        XCTAssertTrue(results.1.content.contains("Odette recommended party details"))
    }

    func testFetchURLReturnsSmallApplicationJSONWithoutPassageExtraction() async throws {
        let rawJSON = #"{"cities":[{"name":"東京","temperature":33},{"name":"大阪","temperature":36}]}"#
        let tool = FetchUrlTool(
            httpClient: StaticWebToolHTTPClient(
                body: rawJSON,
                contentType: "application/json; charset=utf-8"
            )
        )
        let result = try await tool.execute(
            call: ToolCall(
                id: "call-json",
                name: FetchUrlTool.name,
                argumentsJSON: #"{"url":"https://example.com/weather.json","goal":"大阪 temperature"}"#,
                providerMetadata: nil
            )
        )
        XCTAssertEqual(result.content, rawJSON)
        XCTAssertEqual(result.status, .complete)
        XCTAssertEqual(result.provenance?.contentType, "application/json; charset=utf-8")
        XCTAssertEqual(result.provenance?.url, "https://example.com/weather.json")
        XCTAssertGreaterThan(result.provenance?.fetchedAtMs ?? 0, 0)
    }

    func testFetchURLReadsStructuredSyntaxSuffixJSON() async throws {
        let tool = FetchUrlTool(
            httpClient: StaticWebToolHTTPClient(
                body: #"{"title":"Release notes","version":"2.0"}"#,
                contentType: "application/problem+json"
            )
        )
        let result = try await tool.execute(
            call: ToolCall(
                id: "call-suffix-json",
                name: FetchUrlTool.name,
                argumentsJSON: #"{"url":"https://example.com/release.json","goal":"version"}"#,
                providerMetadata: nil
            )
        )

        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.content, #"{"title":"Release notes","version":"2.0"}"#)
    }

    func testFetchURLMarksLargeJSONInsufficientWithoutPassageExtraction() async throws {
        let rawJSON = #"{"payload":"\#(String(repeating: "x", count: FetchUrlTool.maxCharacters))"}"#
        let tool = FetchUrlTool(
            httpClient: StaticWebToolHTTPClient(body: rawJSON, contentType: "application/json")
        )
        let result = try await tool.execute(call: ToolCall(
            id: "call-large-json",
            name: FetchUrlTool.name,
            argumentsJSON: #"{"url":"https://example.com/large.json","goal":"payload"}"#,
            providerMetadata: nil
        ))

        XCTAssertEqual(result.status, .insufficient)
        XCTAssertFalse(result.isError)
        XCTAssertFalse(result.content.contains("$.payload"))
        XCTAssertTrue(result.content.contains("direct-return limit"))
    }

    func testFetchURLReadsJSONFileWithGenericContentType() async throws {
        let tool = FetchUrlTool(
            httpClient: StaticWebToolHTTPClient(
                body: #"{"status":"ok"}"#,
                contentType: "application/octet-stream"
            )
        )
        let result = try await tool.execute(
            call: ToolCall(
                id: "call-json-file",
                name: FetchUrlTool.name,
                argumentsJSON: #"{"url":"https://example.com/status.json","goal":"status"}"#,
                providerMetadata: nil
            )
        )

        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.content, #"{"status":"ok"}"#)
    }

    func testFetchURLRejectsMalformedJSONWithoutHTMLFallback() async throws {
        let tool = FetchUrlTool(
            httpClient: StaticWebToolHTTPClient(
                body: #"{"weather":"sunny""#,
                contentType: "application/json"
            )
        )

        do {
            _ = try await tool.execute(
                call: ToolCall(
                    id: "call-invalid-json",
                    name: FetchUrlTool.name,
                    argumentsJSON: #"{"url":"https://example.com/weather.json","goal":"weather"}"#,
                    providerMetadata: nil
                )
            )
            XCTFail("Expected malformed JSON to be rejected")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Fetched JSON is invalid"))
        }
    }

    func testWebSearchFailureWritesDiagnosticsLog() async throws {
        DiagnosticsLogger.clear()
        defer { DiagnosticsLogger.clear() }

        let tool = WebSearchTool(
            engine: DuckDuckGoHTMLEngine(httpClient: FailingWebToolHTTPClient())
        )
        let result = try await tool.execute(
            call: ToolCall(
                id: "call-search-1",
                name: WebSearchTool.name,
                argumentsJSON: #"{"query":"swift concurrency"}"#,
                providerMetadata: nil
            )
        )

        XCTAssertTrue(result.isError)
        let log = DiagnosticsLogger.read()
        XCTAssertTrue(log.contains("Client web search failed"))
        XCTAssertTrue(log.contains("DuckDuckGo search HTTP error"))
        XCTAssertTrue(log.contains("query=swift concurrency"))
        XCTAssertFalse(log.contains("Local tool execution failed"))
    }

    func testFetchURLRejectsLoopbackBeforeNetworkRequest() async throws {
        let httpClient = RecordingWebToolHTTPClient()
        let tool = FetchUrlTool(httpClient: httpClient)

        do {
            _ = try await tool.execute(
                call: ToolCall(
                    id: "call-1",
                    name: FetchUrlTool.name,
                    argumentsJSON: #"{"url":"http://127.0.0.1/admin","goal":"inspect admin"}"#,
                    providerMetadata: nil
                )
            )
            XCTFail("Expected loopback URL to be rejected")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("publicly routable") || error.localizedDescription.contains("base URL"))
        }

        let requestedURLs = await httpClient.requestedURLs
        XCTAssertTrue(requestedURLs.isEmpty)
    }

    func testFetchURLHTTPErrorDoesNotExposeResponseBodyToAgentContext() async throws {
        let secretMarker = "BODY-MUST-NOT-ENTER-TOOL-RESULT"
        let registry = LocalToolRegistry(executors: [
            FetchUrlTool(httpClient: FailingWebToolHTTPClient(
                statusCode: 404,
                body: String(repeating: secretMarker, count: 1_000)
            ))
        ])

        let result = await registry.execute(call: ToolCall(
            id: "call-404",
            name: FetchUrlTool.name,
            argumentsJSON: #"{"url":"https://example.com/missing","goal":"read the page"}"#,
            providerMetadata: nil
        ))

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("HTTP 404"))
        XCTAssertTrue(result.content.contains("example.com"))
        XCTAssertFalse(result.content.contains(secretMarker))
        XCTAssertLessThan(result.content.count, 300)
    }
}
