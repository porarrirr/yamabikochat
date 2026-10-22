import XCTest
import WebKit
import PDFKit
import UIKit
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
    private(set) var calls = 0
    let statusCode: Int
    let body: String

    init(statusCode: Int = 500, body: String = "server error") {
        self.statusCode = statusCode
        self.body = body
    }

    func get(url: URL, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        calls += 1
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

    func load(html: String, sourceURL: URL, timeout: TimeInterval) async throws -> RenderedPageLoadResult {
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

private actor ScriptedSearchEngine: SearchEngine {
    let results: [SearchResult]
    private(set) var calls = 0
    init(results: [SearchResult]) { self.results = results }
    func search(query: String, locale: Locale, maxResults: Int) async throws -> [SearchResult] {
        calls += 1
        return Array(results.prefix(maxResults))
    }
}

private struct BinaryWebToolHTTPClient: WebToolHTTPClient {
    let data: Data
    let contentType: String
    func get(url: URL, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        (data, HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                              headerFields: ["Content-Type": contentType])!)
    }
}

private actor SlowSearchEngine: SearchEngine {
    private(set) var cancelled = false
    func search(query: String, locale: Locale, maxResults: Int) async throws -> [SearchResult] {
        do { try await Task.sleep(for: .seconds(30)); return [] }
        catch { cancelled = true; throw error }
    }
}

private actor DelayedWebToolHTTPClient: WebToolHTTPClient {
    let delay: Duration
    private(set) var calls = 0
    private(set) var cancellations = 0
    init(delay: Duration = .seconds(30)) { self.delay = delay }
    func get(url: URL, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        calls += 1
        if url.path.contains("slow") {
            do { try await Task.sleep(for: delay) }
            catch { cancellations += 1; throw error }
        }
        return (Data("<p>Warranty repairs last two years.</p>".utf8),
            HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/html"])!)
    }
}

final class WebSearchToolTests: XCTestCase {
    func testYahooParserUsesOnlyOrganicCardsAndKeepsSnippetWithItsSource() {
        let html = """
        <div class="Ad"><section><a href="https://ads.example.com"><h3>広告</h3></a></section></div>
        <div class="AnswerGenerativeAI"><section><h3>AI回答</h3></section></div>
        <div class="sw-Card Algo Algo-Default"><section>
          <a href="https://example.com/kyoto?a=1&amp;b=2"><cite>example.com</cite>
            <h3 class="sw-Card__titleMain"><span>京都の<strong>紅葉</strong></span></h3></a>
          <p class="sw-Card__summary">京都の紅葉スポット &amp; 見頃。</p>
        </section></div>
        <div class="sw-Card Algo Algo-Default"><section>
          <a href="https://example.org/autumn"><h3>秋の京都</h3></a><p>別の出典。</p>
        </section></div>
        """
        let hits = PublicHTMLSearchEngine.parse(html: html, provider: .yahooJapan)
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(hits[0].url, "https://example.com/kyoto?a=1&b=2")
        XCTAssertTrue(hits[0].title.contains("紅葉"))
        XCTAssertEqual(hits[0].snippet, "京都の紅葉スポット & 見頃。")
        XCTAssertEqual(hits[1].snippet, "別の出典。")
        XCTAssertNil(hits[0].publishedAt)
        XCTAssertEqual(hits[0].searchEngines, ["yahoo_japan"])
        XCTAssertTrue(PublicHTMLSearchEngine.parse(html: "<h3>アクセス制限</h3>", provider: .yahooJapan).isEmpty)
    }

    func testBingParserDecodesDestinationAndExcludesAds() {
        let target = "https://example.com/page?a=1&b=2"
        let encoded = Data(target.utf8).base64EncodedString().replacingOccurrences(of: "=", with: "")
        let html = """
        <li class="b_ad"><h2><a href="https://ads.example.com">Ad</a></h2></li>
        <li data-id="1" class="b_algo"><h2><a href="https://www.bing.com/ck/a?u=a1\(encoded)&amp;ntb=1">Source</a></h2>
          <div><p>A source snippet.</p></div></li>
        """
        let hits = PublicHTMLSearchEngine.parse(html: html, provider: .bing)
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits.first?.url, target)
        XCTAssertEqual(hits.first?.snippet, "A source snippet.")
        XCTAssertNil(PublicHTMLSearchEngine.destination("javascript:alert(1)", provider: .bing))
        XCTAssertNil(PublicHTMLSearchEngine.destination("https://www.bing.com/ck/a?u=broken", provider: .bing))
    }

    func testBingMobileHeadingOutsideAnchorRetainsCorrectURL() {
        let hits = PublicHTMLSearchEngine.parse(html: """
        <li class="b_algo"><div class="b_tpcn"><a href="https://example.com">Site navigation</a></div>
          <div class="b_algoheader"><a href="https://example.com/article"><h2>京都 紅葉</h2></a></div>
          <div class="b_caption"><p>見頃の情報</p></div></li>
        """, provider: .bing)
        XCTAssertEqual(hits.first?.url, "https://example.com/article")
        XCTAssertEqual(hits.first?.snippet, "見頃の情報")
    }

    func testSearchMergeDeduplicatesTrackingWithoutCollapsingDifferentResources() {
        let batches = [
            [SearchResult(title: "京都 紅葉", snippet: "", url: "https://example.com/article?id=1&utm_source=yahoo", searchEngines: ["yahoo_japan"])],
            [SearchResult(title: "京都 紅葉", snippet: "見頃の情報", url: "https://example.com/article?id=1", searchEngines: ["bing"]),
             SearchResult(title: "別の記事", snippet: "", url: "https://example.com/article?id=2")]
        ]
        let hits = FederatedSearchEngine.merge(batches, query: "京都 紅葉", japanese: true, maxResults: 8)
        XCTAssertEqual(hits.count, 2)
        XCTAssertEqual(hits[0].url, "https://example.com/article?id=1")
        XCTAssertEqual(hits[0].snippet, "見頃の情報")
        XCTAssertEqual(hits[0].searchEngines, ["bing", "yahoo_japan"])
        XCTAssertNotEqual(FederatedSearchEngine.canonicalURL("https://example.com/#/a"),
                          FederatedSearchEngine.canonicalURL("https://example.com/#/b"))
    }

    func testFederatedSearchKeepsBingResultsWhenYahooIsRestricted() async throws {
        let restricted = PublicHTMLSearchEngine(provider: .yahooJapan, httpClient: FailingWebToolHTTPClient(statusCode: 403))
        let fallback = ScriptedSearchEngine(results: [])
        let expected = SearchResult(title: "京都 紅葉", snippet: "見頃", url: "https://example.com/autumn")
        let engine = FederatedSearchEngine(japaneseEngine: restricted,
            globalEngine: StaticSearchEngine(results: [expected]), fallback: fallback)
        let results = try await engine.search(query: "京都 紅葉", locale: Locale(identifier: "en_US"), maxResults: 8)
        XCTAssertEqual(results, [expected])
        let fallbackCalls = await fallback.calls
        XCTAssertEqual(fallbackCalls, 0)
    }

    func testFederatedSearchFallsBackOnlyWhenPrimaryEnginesHaveNoResults() async throws {
        let fallback = ScriptedSearchEngine(results: [SearchResult(title: "Source", snippet: "", url: "https://example.com")])
        let engine = FederatedSearchEngine(japaneseEngine: StaticSearchEngine(results: []),
            globalEngine: StaticSearchEngine(results: []), fallback: fallback)
        let results = try await engine.search(query: "検索", locale: Locale(identifier: "ja_JP"), maxResults: 1)
        XCTAssertEqual(results.count, 1)
        let calls = await fallback.calls
        XCTAssertEqual(calls, 1)
    }

    func testFederatedSearchDeadlineRetainsCompletedResultsAndCancelsSlowProvider() async throws {
        let slow = SlowSearchEngine()
        let fallback = ScriptedSearchEngine(results: [])
        let engine = FederatedSearchEngine(japaneseEngine: slow,
            globalEngine: StaticSearchEngine(results: [SearchResult(title: "Source", snippet: "", url: "https://example.com")]),
            fallback: fallback, budget: .milliseconds(40))
        let results = try await engine.search(query: "検索", locale: Locale(identifier: "ja_JP"), maxResults: 8)
        XCTAssertEqual(results.count, 1)
        let cancelled = await slow.cancelled
        XCTAssertTrue(cancelled)
        let fallbackCalls = await fallback.calls
        XCTAssertEqual(fallbackCalls, 0)
    }

    func testFederatedSearchPropagatesCancellation() async throws {
        let slow = SlowSearchEngine()
        let engine = FederatedSearchEngine(japaneseEngine: slow, globalEngine: slow)
        let task = Task { try await engine.search(query: "検索", locale: Locale(identifier: "ja_JP"), maxResults: 8) }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
    }

    func testSearchGoalDoesNotAutomaticallyFetchPages() async throws {
        let http = RecordingWebToolHTTPClient()
        let tool = WebSearchTool(engine: StaticSearchEngine(results: [
            SearchResult(title: "Source", snippet: "Summary", url: "https://example.com")
        ]), reader: FetchUrlTool(httpClient: http))
        let result = try await tool.execute(call: ToolCall(id: "fast", name: WebSearchTool.name,
            argumentsJSON: #"{"query":"test","goal":"needed evidence"}"#, providerMetadata: nil))
        let requests = await http.requestedURLs
        XCTAssertTrue(requests.isEmpty)
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("Summary"))
    }

    func testSourceReadingDeadlineKeepsCompletedPageWithCorrectAttribution() async throws {
        let http = DelayedWebToolHTTPClient()
        let tool = WebSearchTool(engine: StaticSearchEngine(results: [
            SearchResult(title: "Slow", snippet: "", url: "https://example.com/slow"),
            SearchResult(title: "Fast", snippet: "", url: "https://example.com/fast")
        ]), reader: FetchUrlTool(httpClient: http), sourceReadBudget: .milliseconds(200))
        let result = try await tool.execute(call: ToolCall(id: "budget", name: WebSearchTool.name,
            argumentsJSON: #"{"query":"warranty","goal":"warranty repairs","read_sources":true}"#, providerMetadata: nil))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.content.utf8)) as? [String: Any])
        let pages = try XCTUnwrap(object["pages"] as? [[String: Any]])
        XCTAssertEqual(pages.count, 1)
        XCTAssertEqual(pages.first?["source"] as? String, "https://example.com/fast")
        XCTAssertEqual(object["source_reading_status"] as? String, "deadline_reached")
        XCTAssertTrue(result.content.contains("two years"))
        XCTAssertFalse(result.isError)
    }

    func testCancelledFetchWaiterDoesNotCancelAnotherReaderOfSameURL() async throws {
        let http = DelayedWebToolHTTPClient(delay: .milliseconds(200))
        let reader = FetchUrlTool(httpClient: http)
        func call(_ id: String) -> ToolCall {
            ToolCall(id: id, name: FetchUrlTool.name,
                argumentsJSON: #"{"url":"https://example.com/slow","goal":"warranty"}"#, providerMetadata: nil)
        }
        let first = Task { try await reader.execute(call: call("first")) }
        let second = Task { try await reader.execute(call: call("second")) }
        try await Task.sleep(for: .milliseconds(50))
        first.cancel()
        do { _ = try await first.value; XCTFail("Expected cancellation") }
        catch is CancellationError { }
        let result = try await second.value
        XCTAssertFalse(result.isError)
        let calls = await http.calls
        let cancellations = await http.cancellations
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(cancellations, 0)
    }

    func testSearchGuidanceAllowsEvidenceDrivenProgressAndTransientRetries() {
        let description = WebSearchTool().definition.description
        XCTAssertTrue(description.contains("Stable explanations and transformations of user-supplied content usually do not need search"))
        XCTAssertTrue(description.contains("Reuse passages already returned"))
        XCTAssertTrue(SystemPromptComposer.agenticWebSearchInstructions.contains("After a transient error, retry only when there is a reasonable prospect of success"))
        XCTAssertFalse(description.contains("externally verifiable information"))
        XCTAssertFalse(description.contains("After two approaches"))
    }

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
                url: "https://example.org/page",
                searchEngines: ["duckduckgo"]
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

    func testRelevantPageReaderReturnsReadableOverviewWhenWordingDiffers() {
        let selection = RelevantPageReader.select(
            paragraphs: [PageParagraph(index: 0, heading: "Cooking", text: "Bake bread slowly.")],
            goal: "quantum entanglement experiment",
            maxCharacters: 8_000
        )

        XCTAssertEqual(selection.status, .overview)
        XCTAssertTrue(selection.content.contains("Bake bread slowly."))
        XCTAssertEqual(selection.selectedParagraphCount, 1)
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

    func testWeatherTableRetainsEntitiesValuesMergedHeadersAndMissingCells() {
        let html = """
        <h2>2026年10月13日 20時現在</h2>
        <table><tr><td rowspan="3">地点</td><td colspan="4">気温</td></tr>
        <tr><td colspan="2">最高</td><td colspan="2">最低</td></tr>
        <tr><td>値(℃)</td><td>起時</td><td>値(℃)</td><td>起時</td></tr>
        <tr><td>大阪</td><td>27.4)</td><td>13:00)</td><td>19.2)</td><td>05:00)</td></tr>
        <tr><td>名古屋</td><td>28.1]</td><td>14:00]</td><td></td><td></td></tr>
        <tr><td>東京</td><td>26.8</td><td>12:00</td><td>18.5</td><td>04:00</td></tr></table>
        """
        let paragraphs = PageParagraphExtractor.extractHTML(html)
        XCTAssertEqual(paragraphs.count, 3)
        let selection = RelevantPageReader.select(
            paragraphs: paragraphs,
            goal: "大阪、名古屋、東京の2026年10月13日の最高気温と最低気温を確認する",
            maxCharacters: 8_000
        )
        XCTAssertTrue(selection.content.contains("地点: 大阪 | 気温 / 最高 / 値(℃): 27.4)"))
        XCTAssertTrue(selection.content.contains("地点: 東京 | 気温 / 最高 / 値(℃): 26.8"))
        XCTAssertTrue(selection.content.contains("気温 / 最低 / 値(℃):  | 気温 / 最低 / 起時: "))
        XCTAssertTrue(selection.content.contains("2026年10月13日 20時現在"))
    }

    func testTableEntityRowsBeatSharedHeadingsOnLongPage() {
        var html = "<h2>2026年10月13日 最高気温 最低気温</h2><table><tr><th>地点</th><th>最高気温</th><th>最低気温</th></tr>"
        for i in 0 ..< 150 {
            html += "<tr><td>地点\(i)</td><td>25.0</td><td>15.0</td></tr>"
        }
        html += "<tr><td>大阪</td><td>27.4</td><td>19.2</td></tr>"
        html += "<tr><td>名古屋</td><td>28.1</td><td>18.8</td></tr>"
        html += "<tr><td>東京</td><td>26.8</td><td>18.5</td></tr></table>"
        let selection = RelevantPageReader.select(
            paragraphs: PageParagraphExtractor.extractHTML(html),
            goal: "大阪 名古屋 東京 最高気温 最低気温 2026年10月13日",
            maxCharacters: 1_000,
            seedLimit: 3,
            contextRadius: 0
        )
        XCTAssertTrue(selection.content.contains("大阪"))
        XCTAssertTrue(selection.content.contains("名古屋"))
        XCTAssertTrue(selection.content.contains("東京"))
        XCTAssertFalse(selection.content.contains("地点0 |"))
    }

    func testTableDataRowHeaderAndCaptionStayTogether() {
        let paragraphs = PageParagraphExtractor.extractHTML("""
        <table><caption>Observed temperatures (℃)</caption>
        <tr><th>City</th><th>High</th><th>Low</th></tr>
        <tr><th scope="row">Tokyo</th><td>26.8</td><td>18.5</td></tr></table>
        """)
        XCTAssertEqual(paragraphs.map(\.text), [
            "Observed temperatures (℃)", "City: Tokyo | High: 26.8 | Low: 18.5"
        ])
    }

    func testTableWithRowHeadersDoesNotTreatFirstDataRowAsColumnLabels() {
        let paragraphs = PageParagraphExtractor.extractHTML("""
        <table><tr><th scope="row">大阪</th><td>27.4</td></tr>
        <tr><th scope="row">東京</th><td>26.8</td></tr></table>
        """)
        XCTAssertEqual(paragraphs.map(\.text), ["大阪 | 27.4", "東京 | 26.8"])
    }

    func testQuestionFocusPreservesOtherMeasuresForIndependentEvidenceAssessment() {
        let paragraphs = PageParagraphExtractor.extractHTML("""
        <table><tr><th>地点</th><th>最高気温(℃)</th><th>最低気温(℃)</th><th>降水量(mm)</th></tr>
        <tr><td>大阪</td><td>27.4)</td><td>19.2)</td><td>0.0)</td></tr></table>
        """)
        let selection = RelevantPageReader.select(paragraphs: paragraphs,
            goal: "大阪の最高気温と最低気温を確認する", maxCharacters: 8_000)
        XCTAssertTrue(selection.content.contains("地点: 大阪"))
        XCTAssertTrue(selection.content.contains("最高気温(℃): 27.4)"))
        XCTAssertTrue(selection.content.contains("最低気温(℃): 19.2)"))
        XCTAssertTrue(selection.content.contains("降水量"))
    }

    func testTableFocusPreservesRequestedEntityOutsideFirstColumn() {
        let paragraphs = PageParagraphExtractor.extractHTML("""
        <table><tr><th>日付</th><th>都市</th><th>最高気温</th><th>降水量</th></tr>
        <tr><td>2026-10-13</td><td>大阪</td><td>27.4</td><td>0.0</td></tr></table>
        """)
        let selection = RelevantPageReader.select(paragraphs: paragraphs,
            goal: "大阪 最高気温", maxCharacters: 8_000)
        XCTAssertTrue(selection.content.contains("日付: 2026-10-13"))
        XCTAssertTrue(selection.content.contains("都市: 大阪"))
        XCTAssertTrue(selection.content.contains("最高気温: 27.4"))
        XCTAssertTrue(selection.content.contains("降水量"))
    }

    func testFetchURLReturnsSourceLinksWithoutInventingRoutes() async throws {
        let tool = FetchUrlTool(httpClient: StaticWebToolHTTPClient(body: """
        <p>東京の観測値はこちら</p>
        <a href="../daily?city=tokyo&amp;day=13">東京の日別の値</a>
        <a href="javascript:alert(1)">東京</a><a href="#top">東京</a>
        <a href="/login">ログイン</a>
        """))
        let result = try await tool.execute(call: ToolCall(
            id: "links", name: FetchUrlTool.name,
            argumentsJSON: #"{"url":"https://example.com/data/index","goal":"東京 気温"}"#,
            providerMetadata: nil
        ))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.content.utf8)) as? [String: Any])
        let links = try XCTUnwrap(object["links"] as? [[String: String]])
        XCTAssertEqual(links.first, ["title": "東京の日別の値", "url": "https://example.com/daily?city=tokyo&day=13"])
        XCTAssertFalse(links.contains { ($0["url"] ?? "").hasPrefix("javascript:") })
    }

    func testFetchURLReusesResponseAcrossGoalsAndPreservesRetrievalTime() async throws {
        let client = RecordingWebToolHTTPClient()
        let tool = FetchUrlTool(httpClient: client)
        func call(_ goal: String) -> ToolCall {
            ToolCall(id: goal, name: FetchUrlTool.name,
                     argumentsJSON: "{\"url\":\"https://example.com/page\",\"goal\":\"\(goal)\"}", providerMetadata: nil)
        }
        let first = try await tool.execute(call: call("ok"))
        let second = try await tool.execute(call: call("different goal"))
        let requests = await client.requestedURLs
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(first.provenance?.fetchedAtMs, second.provenance?.fetchedAtMs)
        XCTAssertTrue(second.content.contains("\"cache_hit\":true"))
    }

    func testFetchURLCacheKeepsDifferentQueryParametersSeparate() async throws {
        let client = RecordingWebToolHTTPClient()
        let tool = FetchUrlTool(httpClient: client)
        for day in [12, 13] {
            _ = try await tool.execute(call: ToolCall(id: "day-\(day)", name: FetchUrlTool.name,
                argumentsJSON: "{\"url\":\"https://example.com/page?day=\(day)\",\"goal\":\"ok\"}", providerMetadata: nil))
        }
        let requests = await client.requestedURLs
        XCTAssertEqual(requests.count, 2)
    }

    func testSearchWithGoalReturnsOriginalSourcePassagesInOneCall() async throws {
        let reader = FetchUrlTool(httpClient: StaticWebToolHTTPClient(body: "<h2>Product policy</h2><p>The warranty covers repairs for two years.</p>"))
        let tool = WebSearchTool(engine: StaticSearchEngine(results: [
            SearchResult(title: "Policy", snippet: "Policy details", url: "https://example.com/policy"),
            SearchResult(title: "Terms", snippet: "Warranty terms", url: "https://example.com/terms"),
            SearchResult(title: "Other", snippet: "Other", url: "https://example.com/other")
        ]), reader: reader)
        let result = try await tool.execute(call: ToolCall(id: "one-round", name: WebSearchTool.name,
            argumentsJSON: #"{"query":"product warranty","goal":"warranty repairs duration","read_sources":true}"#, providerMetadata: nil))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.content.utf8)) as? [String: Any])
        let pages = try XCTUnwrap(object["pages"] as? [[String: Any]])
        XCTAssertEqual(pages.count, 2)
        XCTAssertTrue(result.content.contains("two years"))
        XCTAssertEqual(pages[0]["source"] as? String, "https://example.com/policy", result.content)
        XCTAssertEqual(pages[1]["source"] as? String, "https://example.com/terms", result.content)
    }

    func testSearchKeepsOtherEvidenceWhenOneTopSourceFails() async throws {
        let tool = WebSearchTool(engine: StaticSearchEngine(results: [
            SearchResult(title: "Unavailable", snippet: "", url: "https://example.com/fail"),
            SearchResult(title: "Guide", snippet: "", url: "https://example.com/guide")
        ]), reader: FetchUrlTool(httpClient: URLRoutingWebToolHTTPClient()))
        let result = try await tool.execute(call: ToolCall(id: "partial", name: WebSearchTool.name,
            argumentsJSON: #"{"query":"guide","goal":"Odette party","read_sources":true}"#, providerMetadata: nil))
        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("Odette recommended party details"))
        XCTAssertTrue(result.content.contains("failure"))
    }

    func testSessionSkipsEquivalentQueriesAndResetsForEachExecution() async throws {
        let engine = ScriptedSearchEngine(results: [SearchResult(title: "Cache", snippet: "", url: "https://example.com/cache")])
        let base = LocalToolRegistry(executors: [WebSearchTool(engine: engine)])
        let session = base.scopedForExecution()
        func call(_ id: String, _ query: String) -> ToolCall {
            ToolCall(id: id, name: WebSearchTool.name, argumentsJSON: "{\"query\":\"\(query)\"}", providerMetadata: nil)
        }
        _ = await session.execute(call: call("first", "cache ttl"))
        let repeated = await session.execute(call: call("second", "ttl cache"))
        XCTAssertTrue(repeated.content.contains("cached_evidence_recovered"))
        XCTAssertTrue(repeated.content.contains("first"))
        let initialCount = await engine.calls
        XCTAssertEqual(initialCount, 1)
        let fresh = await base.scopedForExecution().execute(call: call("fresh", "cache ttl"))
        XCTAssertFalse(fresh.content.contains("duplicate_request"))
        let freshCount = await engine.calls
        XCTAssertEqual(freshCount, 1) // public response cache is reusable; execution bookkeeping is fresh
    }

    func testSessionPreservesQuotedPhraseMeaning() async throws {
        let engine = ScriptedSearchEngine(results: [])
        let session = LocalToolRegistry(executors: [WebSearchTool(engine: engine)])
        for (index, query) in [#""cache ttl""#, #""ttl cache""#].enumerated() {
            let json = String(decoding: try JSONSerialization.data(withJSONObject: ["query": query]), as: UTF8.self)
            _ = await session.execute(call: ToolCall(id: "phrase-\(index)", name: WebSearchTool.name, argumentsJSON: json, providerMetadata: nil))
        }
        let count = await engine.calls
        XCTAssertEqual(count, 2)
    }

    func testStalledSearchesStopButNewDocumentEvidenceReopensResearch() async throws {
        let engine = ScriptedSearchEngine(results: [SearchResult(title: "Source", snippet: "", url: "https://example.com/source")])
        let session = LocalToolRegistry(executors: [WebSearchTool(engine: engine),
            FetchUrlTool(httpClient: StaticWebToolHTTPClient(body: "<p>A warranty includes repair for two years.</p>"))])
        for i in 0 ..< 4 {
            _ = await session.execute(call: ToolCall(id: "search-\(i)", name: WebSearchTool.name,
                argumentsJSON: "{\"query\":\"approach \(i)\"}", providerMetadata: nil))
        }
        let blocked = await session.execute(call: ToolCall(id: "blocked", name: WebSearchTool.name,
            argumentsJSON: #"{"query":"new approach"}"#, providerMetadata: nil))
        XCTAssertTrue(blocked.content.contains("search_no_new_sources"))
        let count = await engine.calls
        XCTAssertEqual(count, 4)
        _ = await session.execute(call: ToolCall(id: "read", name: FetchUrlTool.name,
            argumentsJSON: #"{"url":"https://example.com/source","goal":"warranty"}"#, providerMetadata: nil))
        let resumed = await session.execute(call: ToolCall(id: "resumed", name: WebSearchTool.name,
            argumentsJSON: #"{"query":"new approach"}"#, providerMetadata: nil))
        XCTAssertFalse(resumed.content.contains("search_no_new_sources"))
        let resumedCount = await engine.calls
        XCTAssertEqual(resumedCount, 5)
    }

    func testLongParagraphWindowContinuationDoesNotLoseItsTail() {
        let text = String(repeating: "a", count: 5000) + "TAIL FACT"
        let paragraphs = [PageParagraph(index: 0, heading: nil, text: text)]
        var offset = 0
        var reconstructed = ""
        for _ in 0 ..< 10 {
            let page = RelevantPageReader.window(paragraphs: paragraphs, start: 0, maxCharacters: 1000, startCharacter: offset)
            reconstructed += page.content
            guard let next = page.nextCharacter else { break }
            XCTAssertEqual(page.nextParagraph, 0)
            XCTAssertGreaterThan(next, offset)
            offset = next
        }
        XCTAssertEqual(reconstructed, text)
    }

    func testFetchFindsTechnicalFactAtEndOfLongParagraph() async throws {
        let body = "<h2>Configuration</h2><p>" + String(repeating: "Introduction. ", count: 900)
            + "The ZetaCache timeout is 42 milliseconds.</p>"
        let tool = FetchUrlTool(httpClient: StaticWebToolHTTPClient(body: body))
        let result = try await tool.execute(call: ToolCall(id: "late-fact", name: FetchUrlTool.name,
            argumentsJSON: #"{"url":"https://example.com/docs","goal":"ZetaCache timeout milliseconds"}"#, providerMetadata: nil))
        XCTAssertTrue(result.content.contains("42 milliseconds"))
    }

    func testMultilingualReaderRetrievesDistinctiveTerms() {
        for (goal, evidence) in [
            ("garantía reparación", "La garantía incluye reparación durante dos años."),
            ("гарантия ремонт", "Гарантия включает ремонт в течение двух лет."),
            ("보증 수리", "보증 기간 동안 무료 수리가 가능합니다.")
        ] {
            let selection = RelevantPageReader.select(paragraphs: [
                PageParagraph(index: 0, heading: nil, text: "Unrelated news."),
                PageParagraph(index: 1, heading: nil, text: evidence)
            ], goal: goal, maxCharacters: 2000, seedLimit: 1, contextRadius: 0)
            XCTAssertEqual(selection.content, evidence)
        }
    }

    func testHTMLReaderPreservesTechnicalCodeAndDefinitionLists() {
        let paragraphs = PageParagraphExtractor.extractHTML("""
        <h4>Timeout</h4><dl><dt>Default</dt><dd>42 milliseconds</dd></dl>
        <pre>if enabled:\n    timeout = 42</pre>
        """)
        XCTAssertTrue(paragraphs.contains { $0.heading == "Timeout" && $0.text.contains("42 milliseconds") })
        XCTAssertTrue(paragraphs.contains { $0.text.contains("\n    timeout = 42") })
    }

    func testFetchReadsTextPDFThroughSameGoalReader() async throws {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 300, height: 300))
        let pdf = renderer.pdfData { context in
            context.beginPage()
            ("Product warranty covers two years of repairs." as NSString).draw(at: CGPoint(x: 20, y: 30),
                withAttributes: [.font: UIFont.systemFont(ofSize: 14)])
        }
        let tool = FetchUrlTool(httpClient: BinaryWebToolHTTPClient(data: pdf, contentType: "application/pdf"))
        let result = try await tool.execute(call: ToolCall(id: "pdf", name: FetchUrlTool.name,
            argumentsJSON: #"{"url":"https://example.com/policy.pdf","goal":"warranty repairs"}"#, providerMetadata: nil))
        XCTAssertTrue(result.content.contains("two years"))
        XCTAssertTrue(result.content.contains("PDF page 1"))
    }

    func testFetchWindowReadsCachedDocumentWithoutAnotherDownload() async throws {
        let client = RecordingWebToolHTTPClient()
        let tool = FetchUrlTool(httpClient: client)
        _ = try await tool.execute(call: ToolCall(id: "first", name: FetchUrlTool.name,
            argumentsJSON: #"{"url":"https://example.com/doc","goal":"unknown wording"}"#, providerMetadata: nil))
        let window = try await tool.execute(call: ToolCall(id: "window", name: FetchUrlTool.name,
            argumentsJSON: #"{"url":"https://example.com/doc","goal":"inspect","read_mode":"window","start_paragraph":0}"#, providerMetadata: nil))
        let count = await client.requestedURLs.count
        XCTAssertEqual(count, 1)
        XCTAssertTrue(window.content.contains("\"read_mode\":\"window\""))
        XCTAssertTrue(window.content.contains("ok"))
    }

    func testSearchReusesDiscoveryWhenGoalChanges() async throws {
        let engine = ScriptedSearchEngine(results: [SearchResult(title: "Policy", snippet: "", url: "https://example.com/policy")])
        let tool = WebSearchTool(engine: engine,
            reader: FetchUrlTool(httpClient: StaticWebToolHTTPClient(body: "<p>The warranty covers repairs for two years. Returns are allowed for 30 days.</p>")))
        for (id, goal) in [("warranty", "warranty"), ("returns", "returns")] {
            _ = try await tool.execute(call: ToolCall(id: id, name: WebSearchTool.name,
                argumentsJSON: "{\"query\":\"product policy\",\"goal\":\"\(goal)\"}", providerMetadata: nil))
        }
        let count = await engine.calls
        XCTAssertEqual(count, 1)
    }

    func testSessionDoesNotRetryUnavailablePageWithDifferentGoal() async throws {
        let client = FailingWebToolHTTPClient(statusCode: 404)
        let session = LocalToolRegistry(executors: [FetchUrlTool(httpClient: client)])
        _ = await session.execute(call: ToolCall(id: "missing", name: FetchUrlTool.name,
            argumentsJSON: #"{"url":"https://example.com/missing","goal":"pricing"}"#, providerMetadata: nil))
        let second = await session.execute(call: ToolCall(id: "retry", name: FetchUrlTool.name,
            argumentsJSON: #"{"url":"https://example.com/missing","goal":"details"}"#, providerMetadata: nil))
        XCTAssertTrue(second.content.contains("source_unavailable_this_execution"))
        XCTAssertTrue(second.content.contains("missing"))
        let count = await client.calls
        XCTAssertEqual(count, 1)
    }

    func testContentRootRetainsSourceMetadataAndConditions() {
        let paragraphs = PageParagraphExtractor.extractHTML("""
        <header>Site menu</header><article>
        <header>Author: Example. Published 2026-10-13.</header>
        <h1>New findings</h1><p>The trial showed an improvement.</p>
        <aside>Condition: this applies only to the measured group.</aside>
        </article><footer>Global copyright</footer>
        """)
        let content = paragraphs.map(\.text).joined(separator: "\n")
        XCTAssertTrue(content.contains("Published 2026-10-13"))
        XCTAssertTrue(content.contains("measured group"))
        XCTAssertFalse(content.contains("Site menu"))
    }

    func testSourceLinksKeepGenericDeeperLeadsAndExcludeScriptLiterals() async throws {
        let tool = FetchUrlTool(httpClient: StaticWebToolHTTPClient(body: """
        <article><p>The report describes the experiment.</p><a href=/full-report>Read more</a></article>
        <script>let fake = '<a href="https://example.com/fake">experiment</a>';</script>
        """))
        let result = try await tool.execute(call: ToolCall(id: "leads", name: FetchUrlTool.name,
            argumentsJSON: #"{"url":"https://example.com/article","goal":"experiment outcomes"}"#, providerMetadata: nil))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.content.utf8)) as? [String: Any])
        let links = try XCTUnwrap(object["links"] as? [[String: String]])
        XCTAssertEqual(links, [["title": "Read more", "url": "https://example.com/full-report"]])
    }

    func testRenderedDocumentIsReusedForFurtherReading() async throws {
        let loader = await RecordingRenderedPageLoader(result: .success(.loaded(RenderedPageContent(
            title: "Guide", finalURL: URL(string: "https://example.com/guide")!,
            paragraphs: [PageParagraph(index: 0, heading: "Policy", text: "Warranty repairs last two years.")]
        ))))
        let tool = FetchUrlTool(httpClient: StaticWebToolHTTPClient(body: "<div id=app></div>"), renderedPageLoader: loader)
        _ = try await tool.execute(call: ToolCall(id: "initial", name: FetchUrlTool.name,
            argumentsJSON: #"{"url":"https://example.com/guide","goal":"warranty"}"#, providerMetadata: nil))
        let next = try await tool.execute(call: ToolCall(id: "more", name: FetchUrlTool.name,
            argumentsJSON: #"{"url":"https://example.com/guide","goal":"inspect","read_mode":"window"}"#, providerMetadata: nil))
        let count = await loader.callCount
        XCTAssertEqual(count, 1)
        XCTAssertTrue(next.content.contains("Warranty repairs"))
    }

    func testParallelGoalsShareOneHTTPRetrieval() async throws {
        let client = RecordingWebToolHTTPClient()
        let reader = FetchUrlTool(httpClient: client)
        async let first = reader.execute(call: ToolCall(id: "a", name: FetchUrlTool.name,
            argumentsJSON: #"{"url":"https://example.com/doc","goal":"alpha"}"#, providerMetadata: nil))
        async let second = reader.execute(call: ToolCall(id: "b", name: FetchUrlTool.name,
            argumentsJSON: #"{"url":"https://example.com/doc","goal":"beta"}"#, providerMetadata: nil))
        _ = try await (first, second)
        let count = await client.requestedURLs.count
        XCTAssertEqual(count, 1)
    }

    func testEvidenceRecoveryAfterContextLossDoesNotRepeatNetworkWork() async throws {
        let engine = ScriptedSearchEngine(results: [SearchResult(title: "Policy", snippet: "Repairs for two years", url: "https://example.com/policy")])
        let session = LocalToolRegistry(executors: [WebSearchTool(engine: engine)])
        _ = await session.execute(call: ToolCall(id: "original", name: WebSearchTool.name,
            argumentsJSON: #"{"query":"product policy"}"#, providerMetadata: nil))
        let restored = await session.execute(call: ToolCall(id: "recover", name: WebSearchTool.name,
            argumentsJSON: #"{"query":"product policy","recover_cached":true}"#, providerMetadata: nil))
        XCTAssertTrue(restored.content.contains("cached_evidence_recovered"))
        XCTAssertTrue(restored.content.contains("Repairs for two years"))
        XCTAssertEqual(restored.sources.first?.url, "https://example.com/policy")
        let count = await engine.calls
        XCTAssertEqual(count, 1)
    }

    func testLiteralTemplateExamplesAreNeverDiscardedAsMissingContent() {
        let paragraphs = PageParagraphExtractor.extractHTML("""
        <article><h2>Template syntax</h2><pre>Hello {{ customer.name }}</pre>
        <p>Use {% if enabled %} for conditional rendering.</p></article>
        """)
        let selected = RelevantPageReader.select(paragraphs: paragraphs, goal: "template syntax customer enabled", maxCharacters: 4000)
        XCTAssertTrue(selected.content.contains("{{ customer.name }}"))
        XCTAssertTrue(selected.content.contains("{% if enabled %}"))
        let window = RelevantPageReader.window(paragraphs: paragraphs, start: 0, maxCharacters: 4000)
        XCTAssertTrue(window.content.contains("{{ customer.name }}"))
    }

    func testPlainTextReaderPreservesCodeIndentationAndTabularDelimiters() {
        let code = "if enabled:\n    timeout = 42"
        let table = "name\tvalue\tcondition\nExample\t\tunknown"
        XCTAssertEqual(PageParagraphExtractor.extractPlainText(code).first?.text, code)
        XCTAssertEqual(PageParagraphExtractor.extractPlainText(table).first?.text, table)
    }

    func testNonHTMLTextIsNeverDestructivelyParsedAsHTML() async throws {
        let xml = "<policy><warranty>2 years</warranty><condition>repairs only</condition></policy>"
        let tool = FetchUrlTool(httpClient: StaticWebToolHTTPClient(body: xml, contentType: "text/xml"))
        let result = try await tool.execute(call: ToolCall(id: "xml", name: FetchUrlTool.name,
            argumentsJSON: #"{"url":"https://example.com/policy.xml","goal":"warranty"}"#, providerMetadata: nil))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.content.utf8)) as? [String: Any])
        XCTAssertEqual(object["content"] as? String, xml)
        XCTAssertEqual(object["document_format"] as? String, "text")
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

    func testFetchURLRetainsReadableContentWhenUnrelatedTemplateIsUnresolved() async throws {
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

        XCTAssertEqual(object["selection_status"] as? String, "partial_match")
        XCTAssertEqual(object["selected_paragraph_count"] as? Int, 2)
        XCTAssertTrue((object["content"] as? String)?.contains("8月22日") == true)
        XCTAssertTrue((object["content"] as? String)?.contains("{{ content.title }}") == true)
        XCTAssertEqual(object["render_attempted"] as? Bool, false)
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

    func testFetchURLUsesRenderedDOMWhenStaticHTMLHasNoReadableText() async throws {
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
            httpClient: StaticWebToolHTTPClient(body: "<div id=app></div>"),
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

    @MainActor
    func testRenderedPageLoaderDoesNotExecuteUntrustedPageJavaScript() async throws {
        let result = try await WKRenderedPageContentLoader.shared.load(
            html: """
            <html><head><title>Static Article</title></head><body>
              <main><p id="content">Safe static text</p></main>
              <script>
                document.getElementById('content').textContent = 'EXECUTED UNTRUSTED SCRIPT';
              </script>
              <img src="http://127.0.0.1/private" onerror="document.title='EXECUTED HANDLER'">
            </body></html>
            """,
            sourceURL: URL(string: "https://example.com/article")!,
            timeout: 5
        )

        guard case let .loaded(content) = result else {
            return XCTFail("Expected isolated static HTML extraction")
        }
        let combined = content.paragraphs.map(\.text).joined(separator: "\n")
        XCTAssertEqual(content.finalURL, URL(string: "https://example.com/article"))
        XCTAssertEqual(content.title, "Static Article")
        XCTAssertTrue(combined.contains("Safe static text"))
        XCTAssertFalse(combined.contains("EXECUTED UNTRUSTED SCRIPT"))
        XCTAssertNotEqual(content.title, "EXECUTED HANDLER")
    }

    func testFetchURLSkipsRenderingReadablePartialContent() async throws {
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
        XCTAssertEqual(object["render_attempted"] as? Bool, false)
        XCTAssertEqual(object["render_outcome"] as? String, "not_attempted")
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
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.content.utf8)) as? [String: Any])
        XCTAssertEqual(object["content"] as? String, rawJSON)
        XCTAssertEqual(object["document_format"] as? String, "json")
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
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.content.utf8)) as? [String: Any])
        XCTAssertEqual(object["content"] as? String, #"{"title":"Release notes","version":"2.0"}"#)
    }

    func testFetchURLReadsLargeJSONThroughGoalAwarePassages() async throws {
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

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("$.payload"))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.content.utf8)) as? [String: Any])
        XCTAssertLessThanOrEqual((object["content"] as? String)?.count ?? Int.max, 4000)
        XCTAssertGreaterThan(object["total_paragraph_count"] as? Int ?? 0, 1)
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
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.content.utf8)) as? [String: Any])
        XCTAssertEqual(object["content"] as? String, #"{"status":"ok"}"#)
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
