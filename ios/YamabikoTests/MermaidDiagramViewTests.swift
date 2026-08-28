import CryptoKit
import SwiftUI
import WebKit
import XCTest
@testable import YamabikoChat

final class MermaidDiagramViewTests: XCTestCase {
    func testParserRecognizesMermaidFenceCaseInsensitively() throws {
        let markdown = """
        Before

        ```MerMaId
        flowchart LR
          A[開始] --> B[完了]
        ```

        After
        """

        let blocks = NativeMarkdownParser.parse(markdown)
        XCTAssertEqual(blocks.count, 3)
        guard case let .mermaid(_, source) = blocks[1] else {
            return XCTFail("Expected a Mermaid block")
        }
        XCTAssertTrue(source.contains("A[開始] --> B[完了]"))
    }

    func testParserKeepsOtherCodeFencesAsCode() throws {
        let blocks = NativeMarkdownParser.parse(
            """
            ```swift
            print("hello")
            ```
            """
        )

        guard case let .code(_, language, code) = try XCTUnwrap(blocks.first) else {
            return XCTFail("Expected an ordinary code block")
        }
        XCTAssertEqual(language, "swift")
        XCTAssertTrue(code.contains("print"))
    }

    func testParserSupportsMultipleMermaidBlocks() {
        let blocks = NativeMarkdownParser.parse(
            """
            ```mermaid
            flowchart LR
              A --> B
            ```

            text

            ```MERMAID
            sequenceDiagram
              A->>B: hello
            ```
            """
        )

        XCTAssertEqual(blocks.filter {
            if case .mermaid = $0 { return true }
            return false
        }.count, 2)
    }

    func testStreamingPresentationDoesNotRenderMermaid() {
        XCTAssertFalse(MermaidPresentationPolicy.shouldRender(isStreaming: true))
        XCTAssertTrue(MermaidPresentationPolicy.shouldRender(isStreaming: false))
    }

    func testHTMLBuilderUsesStrictOfflineConfiguration() throws {
        let source = "flowchart LR\nA --> B"
        let html = MermaidHTMLBuilder.buildHTML(
            sourcePayload: try jsonLiteral(source),
            colorScheme: .light,
            allowsZoom: false
        )

        XCTAssertTrue(html.contains("securityLevel: 'strict'"))
        XCTAssertTrue(html.contains("htmlLabels: false"))
        XCTAssertTrue(html.contains("flowchart: { htmlLabels: false }"))
        XCTAssertTrue(html.contains("secure:"))
        XCTAssertTrue(html.contains("connect-src 'none'"))
        XCTAssertTrue(html.contains("frame-src 'none'"))
        XCTAssertTrue(html.contains("maxTextSize: 50000"))
        XCTAssertTrue(html.contains("maxEdges: 500"))
        XCTAssertTrue(html.contains("mermaid.min.js"))
        XCTAssertFalse(html.contains("https://"))
        XCTAssertFalse(html.contains("http://"))
    }

    func testHTMLBuilderSafelyEmbedsScriptTerminator() throws {
        let payload = try jsonLiteral("flowchart LR\nA[</script><script>alert(1)</script>] --> B")
        let html = MermaidHTMLBuilder.buildHTML(
            sourcePayload: payload,
            colorScheme: .dark,
            allowsZoom: true
        )

        XCTAssertFalse(html.contains("A[</script><script>alert(1)</script>]"))
        XCTAssertTrue(payload.contains("<\\/script>"))
        XCTAssertTrue(html.contains("theme: 'dark'"))
        XCTAssertTrue(html.contains("maximum-scale=5"))
        XCTAssertTrue(html.contains("max-height: calc(100vh - 24px)"))
    }

    func testOversizedSourceHasExplicitPreflightError() {
        let error = MermaidRenderError.sourceTooLarge(limit: MermaidHTMLBuilder.maximumSourceLength)
        XCTAssertTrue(error.localizedDescription.contains("50000"))
    }

    func testSecureConfigurationCannotBeOverriddenByDiagramDirective() throws {
        let source = "%%{init: {'securityLevel': 'loose', 'htmlLabels': true}}%%\nflowchart LR\nA --> B"
        let html = MermaidHTMLBuilder.buildHTML(
            sourcePayload: try jsonLiteral(source),
            colorScheme: .light,
            allowsZoom: false
        )

        XCTAssertTrue(html.contains("'securityLevel'"))
        XCTAssertTrue(html.contains("'htmlLabels'"))
        XCTAssertTrue(html.contains("securityLevel: 'strict'"))
    }

    func testNavigationPolicyOnlyAllowsInitialLocalDocument() {
        XCTAssertTrue(MermaidNavigationPolicy.allowsInitialDocument(
            URL(fileURLWithPath: "/tmp/index.html"),
            isMainFrame: true
        ))
        XCTAssertTrue(MermaidNavigationPolicy.allowsInitialDocument(
            URL(string: "about:blank"),
            isMainFrame: true
        ))
        XCTAssertFalse(MermaidNavigationPolicy.allowsInitialDocument(
            URL(string: "https://example.com"),
            isMainFrame: true
        ))
        XCTAssertFalse(MermaidNavigationPolicy.allowsInitialDocument(
            URL(fileURLWithPath: "/tmp/index.html"),
            isMainFrame: false
        ))
    }

    func testVendoredMermaidAssetMatchesPinnedVersion() throws {
        let scriptURL = try sourceResourceDirectory()
            .appendingPathComponent("mermaid.min.js")
        let data = try Data(contentsOf: scriptURL)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        XCTAssertEqual(MermaidResourceResolver.version, "11.17.2")
        XCTAssertEqual(digest, "581ed7d74bd9048d0e3a91363927d72ef22942d7722546b27f7cc29e35390eb8")
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: try sourceResourceDirectory().appendingPathComponent("MERMAID_LICENSE.txt").path
        ))
    }

    @MainActor
    func testVendoredMermaidRendersJapaneseFlowchartToSVG() async throws {
        let state = try await render(
            """
            flowchart LR
              A[開始] --> B[完了]
            """
        )

        XCTAssertEqual(state["status"] as? String, "success")
        XCTAssertGreaterThan((state["height"] as? NSNumber)?.doubleValue ?? 0, 0)
    }

    @MainActor
    func testInvalidMermaidReportsExplicitError() async throws {
        let state = try await render("flowchart LR\nA[broken")
        XCTAssertEqual(state["status"] as? String, "error")
        XCTAssertFalse((state["message"] as? String ?? "").isEmpty)
    }

    @MainActor
    private func render(_ source: String) async throws -> [String: Any] {
        let expectation = expectation(description: "Mermaid render result")
        let recorder = MermaidRenderMessageRecorder(expectation: expectation)
        let controller = WKUserContentController()
        controller.add(recorder, name: "mermaidRenderState")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 800), configuration: configuration)
        let html = MermaidHTMLBuilder.buildHTML(
            sourcePayload: try jsonLiteral(source),
            colorScheme: .light,
            allowsZoom: false
        )
        webView.loadHTMLString(html, baseURL: try sourceResourceDirectory())

        await fulfillment(of: [expectation], timeout: 15)
        controller.removeScriptMessageHandler(forName: "mermaidRenderState")
        return try XCTUnwrap(recorder.message)
    }

    private func sourceResourceDirectory() throws -> URL {
        let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let directory = testDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("YamabikoChat")
            .appendingPathComponent("App")
            .appendingPathComponent("Resources")
            .appendingPathComponent("mermaid")
        guard FileManager.default.fileExists(atPath: directory.path) else {
            throw MermaidTestError.missingResourceDirectory(directory.path)
        }
        return directory
    }

    private func jsonLiteral(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
            .replacingOccurrences(of: "</", with: "<\\/")
    }
}

private final class MermaidRenderMessageRecorder: NSObject, WKScriptMessageHandler {
    let expectation: XCTestExpectation
    private(set) var message: [String: Any]?

    init(expectation: XCTestExpectation) {
        self.expectation = expectation
    }

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard self.message == nil, let body = message.body as? [String: Any] else { return }
        self.message = body
        expectation.fulfill()
    }
}

private enum MermaidTestError: Error {
    case missingResourceDirectory(String)
}
