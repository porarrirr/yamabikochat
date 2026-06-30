import XCTest
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

    init(statusCode: Int = 500) {
        self.statusCode = statusCode
    }

    func get(url: URL, timeout: TimeInterval) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "text/plain"]
        )!
        return (Data("server error".utf8), response)
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

    func testLocaleMapsJapaneseToDuckDuckGoJapanRegion() {
        XCTAssertEqual(
            DuckDuckGoHTMLEngine.regionParameter(for: Locale(identifier: "ja_JP")),
            "jp-jp"
        )
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
                    argumentsJSON: #"{"url":"http://127.0.0.1/admin"}"#,
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
}
