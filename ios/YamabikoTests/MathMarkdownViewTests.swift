import XCTest
import SwiftUI
import WebKit
import JavaScriptCore
@testable import YamabikoChat

final class MathMarkdownViewTests: XCTestCase {
    @MainActor
    func testMathRendersInActualWebView() async throws {
        try await assertMathRenders(AppStoreScreenshotDemoSeeder.mathRenderingFixtureText)
    }

    @MainActor
    func testStandaloneFractionFitsWebViewHeight() async throws {
        try await assertMathRenders(#"\[S=\frac{dV}{dr}=\frac{d}{dr}\left(\frac{4}{3}\pi r^3\right)=4\pi r^2.\]"#)
    }

    @MainActor
    func testMathParagraphRemainsVisibleBelowUserMessage() async throws {
        let source = AppStoreScreenshotDemoSeeder.mathRenderingFixtureText
        let expectedBlocks = NativeMarkdownParser.parse(source).filter {
            if case .math = $0 { return true }
            return false
        }.count
        let store = ChatTimelineStore()
        store.update(messages: [
            FullChatMessage(id: 1, message: ChatMessage(id: 1, conversationId: 1, role: "user", text: "球の表面積を説明してください", createdAtMs: 1), thinkingStream: nil, variants: []),
            FullChatMessage(id: 2, message: ChatMessage(id: 2, conversationId: 1, role: "model", text: source, createdAtMs: 2), thinkingStream: nil, variants: [])
        ])
        let controller = ChatTimelineViewController()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        controller.configure(store: store, scrollToLatestRequest: 0, regeneratableMessageID: nil,
            fusionDebugModeEnabled: false, dualSplitLayout: "VERTICAL", dualSplitRatio: 0.5,
            fusionTraceForMessage: { _ in nil }, onRoute: { _ in }, onPreviousVariant: { _ in },
            onNextVariant: { _ in }, onBranch: { _ in }, onRegenerate: {}, onAskChatWithSelection: { _ in },
            onEditUserMessage: { _ in }, onSelectUserMessageText: { _ in })
        func webViews(_ view: UIView) -> [WKWebView] {
            (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap(webViews)
        }
        let expectedEquations = source.components(separatedBy: #"\("#).count - 1
            + source.components(separatedBy: #"\["#).count - 1
        var rendered = false
        for _ in 0..<100 {
            controller.view.layoutIfNeeded()
            let views = webViews(controller.view)
            if views.count == expectedBlocks {
                var equations = 0
                for view in views {
                    equations += (try? await view.evaluateJavaScript("document.querySelectorAll('mjx-container svg').length")) as? Int ?? 0
                }
                rendered = equations == expectedEquations
                if rendered { break }
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(rendered)
        try await Task.sleep(for: .milliseconds(300))
        controller.view.layoutIfNeeded()
        for view in webViews(controller.view) {
            var ancestor = view.superview
            while ancestor != nil, !(ancestor is UICollectionViewCell) { ancestor = ancestor?.superview }
            let cell = try XCTUnwrap(ancestor as? UICollectionViewCell)
            let frameInCell = view.convert(view.bounds, to: cell)
            XCTAssertGreaterThanOrEqual(frameInCell.minY, -1, "Math paragraph must not start above its clipped chat cell")
            XCTAssertLessThanOrEqual(frameInCell.maxY, cell.bounds.maxY + 1, "Math paragraph must fit inside its chat cell")
            let top = try await view.evaluateJavaScript("document.getElementById('yamabiko-markdown').getBoundingClientRect().top") as? Double
            XCTAssertGreaterThanOrEqual(try XCTUnwrap(top), -1)
        }
    }

    @MainActor
    private func assertMathRenders(_ source: String) async throws {
        let expectedCount = source.components(separatedBy: #"\("#).count - 1
            + source.components(separatedBy: #"\["#).count - 1
        let mathBlocks = NativeMarkdownParser.parse(source).compactMap { block -> String? in
            guard case let .math(_, markdown) = block else { return nil }
            return markdown
        }.joined(separator: "\n")
        XCTAssertEqual(mathBlocks.components(separatedBy: #"\("#).count - 1
            + mathBlocks.components(separatedBy: #"\["#).count - 1, expectedCount)
        let controller = UIHostingController(rootView: ScrollView { MathMarkdownView(markdownText: source) })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = controller
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil }
        func webViews(_ view: UIView) -> [WKWebView] {
            (view as? WKWebView).map { [$0] } ?? view.subviews.flatMap(webViews)
        }
        var count = 0
        var state = ""
        var outsideViewport = -1
        for _ in 0..<100 {
            controller.view.layoutIfNeeded()
            let views = webViews(controller.view)
            count = 0
            for webView in views {
                count += (try? await webView.evaluateJavaScript("document.querySelectorAll('mjx-container svg').length")) as? Int ?? 0
                state = String(describing: try? await webView.evaluateJavaScript("JSON.stringify({math:typeof window.MathJax, viewport:innerHeight, root:document.getElementById('yamabiko-markdown').getBoundingClientRect().toJSON(), svg:Array.from(document.querySelectorAll('mjx-container svg')).map(s=>s.getBoundingClientRect().toJSON())})")) + " frame=\(webView.frame)"
                if count == expectedCount {
                    outsideViewport = (try await webView.evaluateJavaScript("""
                        Array.from(document.querySelectorAll('mjx-container svg')).filter(svg => {
                            const box = svg.getBoundingClientRect();
                            return box.top < -1 || box.bottom > window.innerHeight + 1;
                        }).length
                        """)) as? Int ?? -1
                    let clipped = try await webView.evaluateJavaScript("""
                        Array.from(document.querySelectorAll('mjx-container[display="true"]')).filter(container => {
                            const svg = container.querySelector('svg').getBoundingClientRect();
                            const box = container.getBoundingClientRect();
                            return svg.top < box.top - 1 || svg.bottom > box.bottom + 1;
                        }).length
                        """) as? Int
                    XCTAssertEqual(clipped, 0, "Display equations must fit their scroll containers")
                    let errors = try await webView.evaluateJavaScript("document.querySelectorAll('mjx-merror').length") as? Int
                    XCTAssertEqual(errors, 0)
                }

            }
            if count == expectedCount, outsideViewport == 0 { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "Math rendering in iOS simulator"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(count, expectedCount, state)
        XCTAssertEqual(outsideViewport, 0, "All equations must fit inside the measured WebView height: \(state)")
    }

    func testBuildHTMLIncludesMathJax() {
        let html = MathMarkdownHTMLBuilder.buildHTML(
            markdownPayload: "\"hello\"",
            markdownRendererScript: "window.yamabikoRenderMarkdown = function(){ return ''; };",
            bodyTextColor: "#000000",
            codeBackgroundColor: "#111111",
            borderColor: "#222222",
            linkColor: "#333333",
            mathJaxScriptTag: "<script src=\"tex-svg.js\"></script>"
        )

        XCTAssertTrue(html.contains("window.MathJax ="))
        XCTAssertTrue(html.contains("tex-svg.js"))
        XCTAssertTrue(html.contains("typesetPromise([root])"))
        XCTAssertTrue(html.contains("packages: {'[-]': ['require']}"))
        XCTAssertTrue(html.contains("options: { enableMenu: false }"))
        XCTAssertTrue(html.contains("Content-Security-Policy"))
        XCTAssertTrue(html.contains("connect-src 'none'"))
    }

    func testResolveResourceURLPrefersMathJaxSubdirectory() {
        let subdirectoryURL = URL(fileURLWithPath: "/tmp/mathjax/markdown-renderer.js")
        let rootURL = URL(fileURLWithPath: "/tmp/markdown-renderer.js")

        let resolved = MathMarkdownResourceResolver.resolveResourceURL(
            resource: "markdown-renderer",
            withExtension: "js",
            subdirectories: ["mathjax", nil],
            using: { _, _, subdirectory in
                if subdirectory == "mathjax" {
                    return subdirectoryURL
                }
                if subdirectory == nil {
                    return rootURL
                }
                return nil
            }
        )

        XCTAssertEqual(resolved, subdirectoryURL)
    }

    func testResolveResourceURLFallsBackToRootWhenSubdirectoryMissing() {
        let rootURL = URL(fileURLWithPath: "/tmp/markdown-renderer.js")

        let resolved = MathMarkdownResourceResolver.resolveResourceURL(
            resource: "markdown-renderer",
            withExtension: "js",
            subdirectories: ["mathjax", nil],
            using: { _, _, subdirectory in
                subdirectory == nil ? rootURL : nil
            }
        )

        XCTAssertEqual(resolved, rootURL)
    }

    func testMarkdownRendererScriptFallsBackAndLogsWhenResourceMissing() {
        var logs: [String] = []

        let script = MathMarkdownResourceResolver.markdownRendererScript(
            fallbackScript: "fallback-renderer",
            lookup: { _, _, _ in nil },
            scriptLoader: { _ in
                XCTFail("scriptLoader should not be called when lookup fails")
                return nil
            },
            logger: { message in
                logs.append(message)
            }
        )

        XCTAssertEqual(script, "fallback-renderer")
        XCTAssertEqual(logs.count, 1)
        XCTAssertTrue(logs[0].contains("fallback"))
    }

    func testGeneratedFallbackMatchesBundledRendererAndPreservesBlankLinesInMath() throws {
        let bundled = MathMarkdownResourceResolver.markdownRendererScript(
            fallbackScript: "",
            logger: { _ in XCTFail("Bundled renderer must be present") }
        )
        XCTAssertEqual(MathMarkdownRendererSource.script, bundled)
        for unavailableScript in [nil, "", "  "] as [String?] {
            var warnings: [String] = []
            let fallback = MathMarkdownResourceResolver.markdownRendererScript(
                fallbackScript: MathMarkdownRendererSource.script,
                lookup: { _, _, _ in URL(fileURLWithPath: "/missing.js") },
                scriptLoader: { _ in unavailableScript },
                logger: { warnings.append($0) }
            )
            XCTAssertEqual(warnings.count, 1)
            let context = try XCTUnwrap(JSContext())
            context.evaluateScript("var window = this;")
            context.evaluateScript(fallback)
            let render = try XCTUnwrap(context.objectForKeyedSubscript("yamabikoRenderMarkdown"))
            for math in ["$$\nx = 1\n\ny = 2\n$$", #"\["# + "\nx = 1\n\ny = 2\n" + #"\]"#] {
                let html = try XCTUnwrap(render.call(withArguments: [math])?.toString())
                XCTAssertEqual(html.components(separatedBy: "<p>").count - 1, 1, html)
                XCTAssertTrue(html.contains("x = 1"))
                XCTAssertTrue(html.contains("y = 2"))
            }
        }
    }

    func testMarkdownRendererScriptUsesLoadedScriptWhenAvailable() {
        let resolvedURL = URL(fileURLWithPath: "/tmp/mathjax/markdown-renderer.js")
        let rendererScript = "window.yamabikoRenderMarkdown = function(){ return '<p>ok</p>'; };"

        let script = MathMarkdownResourceResolver.markdownRendererScript(
            fallbackScript: "fallback-renderer",
            lookup: { _, _, _ in resolvedURL },
            scriptLoader: { _ in rendererScript },
            logger: { _ in
                XCTFail("logger should not be called when script is loaded")
            }
        )

        XCTAssertEqual(script, rendererScript)
    }

    func testNormalizeEscapedDollarDelimitersBothSides() {
        let input = #"数式: \$sum_{k=1}^{n} k\$ を表示"#
        let normalized = MathMarkdownNormalizer.normalizeEscapedDollarDelimiters(input)

        XCTAssertEqual(normalized, #"数式: $sum_{k=1}^{n} k$ を表示"#)
    }

    func testNormalizeEscapedDollarDelimitersEscapedOpeningOnly() {
        let input = #"数式: \$sum_{k=1}^{n} k$ を表示"#
        let normalized = MathMarkdownNormalizer.normalizeEscapedDollarDelimiters(input)

        XCTAssertEqual(normalized, #"数式: $sum_{k=1}^{n} k$ を表示"#)
    }

    func testNormalizeEscapedDollarDelimitersPreservesEscapedCurrency() {
        let input = #"価格は \$5 です"#
        let normalized = MathMarkdownNormalizer.normalizeEscapedDollarDelimiters(input)

        XCTAssertEqual(normalized, input)
    }

    func testNormalizeEscapedDollarDelimitersSkipsInlineCode() {
        let input = #"`x = \$sum$` と本文 \$sum$"#
        let normalized = MathMarkdownNormalizer.normalizeEscapedDollarDelimiters(input)

        XCTAssertEqual(normalized, #"`x = \$sum$` と本文 $sum$"#)
    }

    func testNormalizeEscapedDollarDelimitersSkipsFencedCodeBlock() {
        let input = #"""
```tex
\$sum$
```
本文 \$sum$
"""#
        let normalized = MathMarkdownNormalizer.normalizeEscapedDollarDelimiters(input)
        let expected = #"""
```tex
\$sum$
```
本文 $sum$
"""#

        XCTAssertEqual(normalized, expected)
    }

    func testNormalizeEscapedMathIfNeededNormalizes() {
        let input = #"本文 \$sum$"#
        let normalized = MathMarkdownNormalizer.normalizeEscapedMathIfNeeded(input)

        XCTAssertEqual(normalized, #"本文 $sum$"#)
    }

    func testNormalizeEscapedMathIfNeededNormalizesEscapedSequencesWhenMathPresent() {
        let input = #"1行目\\n\\(a+b\\) と \\$sum_{k=1}^{n}k\\$"#
        let normalized = MathMarkdownNormalizer.normalizeEscapedMathIfNeeded(input)

        let expected = """
        1行目
        \\(a+b\\) と $sum_{k=1}^{n}k$
        """
        XCTAssertEqual(normalized, expected)
    }

    func testNormalizeEscapedMathIfNeededDoesNotNormalizeEscapedSequencesWithoutMath() {
        let input = #"line1\\nline2"#
        let normalized = MathMarkdownNormalizer.normalizeEscapedMathIfNeeded(input)

        XCTAssertEqual(normalized, input)
    }

    func testNormalizeEscapedMathIfNeededSkipsEscapedSequenceNormalizationInCode() {
        let input = #"""
```text
\\n\\(x\\)
```
本文 \\(x+y\\)
"""#
        let normalized = MathMarkdownNormalizer.normalizeEscapedMathIfNeeded(input)

        let expected = #"""
```text
\\n\\(x\\)
```
本文 \(x+y\)
"""#
        XCTAssertEqual(normalized, expected)
    }

    func testNormalizeEscapedMathIfNeededIgnoresMathMarkersInsideCodeOnly() {
        let input = #"""
```text
\$sum$
```
line1\\nline2
"""#
        let normalized = MathMarkdownNormalizer.normalizeEscapedMathIfNeeded(input)

        XCTAssertEqual(normalized, input)
    }

    func testMathJaxLoadPlannerPrefersLocalScriptWhenAvailable() {
        let localURL = URL(fileURLWithPath: "/tmp/mathjax/tex-svg.js")

        let plan = MathJaxLoadPlanner.plan(
            localScriptURL: localURL
        )

        XCTAssertTrue(plan.scriptTag.contains("src=\"tex-svg.js\""))
        XCTAssertEqual(plan.baseURL, localURL.deletingLastPathComponent())
    }

    func testMathJaxLoadPlannerReportsMissingLocalScript() {
        var logs: [String] = []

        let plan = MathJaxLoadPlanner.plan(
            localScriptURL: nil,
            logger: { message in
                logs.append(message)
            }
        )

        XCTAssertTrue(plan.scriptTag.isEmpty)
        XCTAssertNil(plan.baseURL)
        XCTAssertEqual(logs.count, 1)
        XCTAssertTrue(logs[0].contains("local script missing"))
    }

    func testMarkdownRendererDoesNotLeakMathPlaceholdersAfterEmphasisReplacement() throws {
        let result = try renderMarkdownWithJavaScript("本文 *強調* と $x_i$")

        XCTAssertFalse(result.contains("@@"))
        XCTAssertTrue(result.contains("$x_i$"))
        XCTAssertTrue(result.contains("<em>強調</em>"))
    }

    func testMarkdownRendererEscapesHTMLInsideMathDelimiters() throws {
        let result = try renderMarkdownWithJavaScript("$<img src=x onerror=alert(1)>$")

        XCTAssertFalse(result.contains("<img"))
        XCTAssertTrue(result.contains("&lt;img"))
    }

    func testMarkdownRendererWrapsCodeBlockWithCopyButton() throws {
        let result = try renderMarkdownWithJavaScript(
            """
            ```swift
            let value = 42
            ```
            """
        )

        XCTAssertTrue(result.contains("yamabiko-code-block"))
        XCTAssertTrue(result.contains("yamabiko-copy-button"))
        XCTAssertTrue(result.contains(">Copy<"))
        XCTAssertTrue(result.contains("let value = 42"))
        XCTAssertFalse(result.contains("```"))
    }

    func testMarkdownRendererRendersGfmTable() throws {
        let result = try renderMarkdownWithJavaScript(
            """
            | 項目 | 値 |
            | --- | --- |
            | A | 1 |
            | B | 2 |
            """
        )

        XCTAssertTrue(result.contains("yamabiko-table-wrap"))
        XCTAssertTrue(result.contains("<table>"))
        XCTAssertTrue(result.contains("<thead>"))
        XCTAssertTrue(result.contains("<tbody>"))
        XCTAssertTrue(result.contains("<th>項目</th>"))
        XCTAssertTrue(result.contains("<td>A</td>"))
    }

    func testMarkdownRendererConvertsBareURLToDomainLink() throws {
        let result = try renderMarkdownWithJavaScript(
            "参考: https://www.ankerjapan.com/blogs/magazine/example?source=chat"
        )

        XCTAssertTrue(result.contains("href=\"https://www.ankerjapan.com/blogs/magazine/example?source=chat\""))
        XCTAssertTrue(result.contains(">ankerjapan.com <"))
        XCTAssertTrue(result.contains("yamabiko-external-arrow"))
        XCTAssertTrue(result.contains(">↗</span>"))
        XCTAssertFalse(result.contains(">https://www.ankerjapan.com"))
    }

    func testMarkdownRendererPreservesEncodedURLAndExcludesTrailingPunctuation() throws {
        let result = try renderMarkdownWithJavaScript(
            "参照（https://pick-navi.com/ranking/%E3%83%A2%E3%83%90%E3%82%A4%E3%83%AB）。"
        )

        XCTAssertTrue(result.contains("href=\"https://pick-navi.com/ranking/%E3%83%A2%E3%83%90%E3%82%A4%E3%83%AB\""))
        XCTAssertTrue(result.contains(">pick-navi.com <"))
        XCTAssertTrue(result.contains("</a>）。"))
    }

    func testMarkdownRendererKeepsBalancedClosingParenthesisInBareURL() throws {
        let result = try renderMarkdownWithJavaScript(
            "https://example.com/wiki/Swift_(programming_language)"
        )

        XCTAssertTrue(result.contains("href=\"https://example.com/wiki/Swift_(programming_language)\""))
    }

    func testMarkdownRendererKeepsMarkdownLinkLabelAndAddsExternalIndicator() throws {
        let result = try renderMarkdownWithJavaScript("[公式サイト](https://example.com/path)")

        XCTAssertTrue(result.contains("href=\"https://example.com/path\""))
        XCTAssertTrue(result.contains(">公式サイト <"))
        XCTAssertTrue(result.contains(">↗</span>"))
        XCTAssertFalse(result.contains(">example.com <"))
    }

    func testMarkdownRendererDoesNotDuplicateExistingExternalIndicator() throws {
        let result = try renderMarkdownWithJavaScript("[公式サイト ↗](https://example.com/path)")

        XCTAssertEqual(result.components(separatedBy: "↗").count - 1, 1)
    }

    func testMarkdownRendererDoesNotAutoLinkCodeMathOrUnsafeScheme() throws {
        let result = try renderMarkdownWithJavaScript(
            "`https://code.example/path` と $https://math.example/x$ と javascript:alert(1)"
        )

        XCTAssertTrue(result.contains("<code>https://code.example/path</code>"))
        XCTAssertTrue(result.contains("$https://math.example/x$"))
        XCTAssertTrue(result.contains("javascript:alert(1)"))
        XCTAssertFalse(result.contains("href="))
    }

    func testMarkdownRendererAutoLinksBareURLInsideTableCell() throws {
        let result = try renderMarkdownWithJavaScript(
            """
            | サイト | URL |
            | --- | --- |
            | Example | https://www.example.com/very/long/path |
            """
        )

        XCTAssertTrue(result.contains("<td>Example</td>"))
        XCTAssertTrue(result.contains("href=\"https://www.example.com/very/long/path\""))
        XCTAssertTrue(result.contains(">example.com <"))
    }

    func testMarkdownRendererAppliesTableAlignment() throws {
        let result = try renderMarkdownWithJavaScript(
            """
            | L | C | R |
            | :--- | :---: | ---: |
            | a | b | c |
            """
        )

        XCTAssertTrue(result.contains("text-align: left;"))
        XCTAssertTrue(result.contains("text-align: center;"))
        XCTAssertTrue(result.contains("text-align: right;"))
    }

    func testMarkdownRendererPreservesBrInTableCell() throws {
        let result = try renderMarkdownWithJavaScript(
            """
            | 説明 |
            | --- |
            | 1行目<br>2行目 |
            """
        )

        XCTAssertTrue(result.contains("<td>1行目<br/>2行目</td>"))
    }

    func testMarkdownRendererEscapesUnsafeHtmlInTableCell() throws {
        let result = try renderMarkdownWithJavaScript(
            """
            | 説明 |
            | --- |
            | <script>alert(1)</script> |
            """
        )

        XCTAssertTrue(result.contains("&lt;script&gt;alert(1)&lt;/script&gt;"))
        XCTAssertFalse(result.contains("<script>alert(1)</script>"))
    }

    func testMarkdownRendererPreservesMathTokensInTableCell() throws {
        let result = try renderMarkdownWithJavaScript(
            """
            | 式 |
            | --- |
            | $a_c = v^2/r$ |
            """
        )

        XCTAssertTrue(result.contains("yamabiko-table-wrap"))
        XCTAssertTrue(result.contains("$a_c = v^2/r$"))
        XCTAssertFalse(result.contains("&amp;"))
    }

    func testMarkdownRendererPreservesMathWithSpecialCharacters() throws {
        let result = try renderMarkdownWithJavaScript("本文 $a < b$ と $c & d$")

        XCTAssertTrue(result.contains("$a &lt; b$"))
        XCTAssertTrue(result.contains("$c &amp; d$"))
        XCTAssertFalse(result.contains("$a < b$"))
    }

    func testMarkdownRendererEscapesExecutableMarkupInsideMath() throws {
        let payloads = [
            #"$<img src=x onerror=alert(1)>$"#,
            #"$$<svg onload=alert(1)></svg>$$"#,
            #"\(<math href=\"javascript:alert(1)\">x</math>\)"#,
            #"\[<a href=\"data:text/html,boom\">x</a>\]"#
        ]

        for payload in payloads {
            let result = try renderMarkdownWithJavaScript(payload)
            XCTAssertFalse(result.contains("<img"), payload)
            XCTAssertFalse(result.contains("<svg"), payload)
            XCTAssertFalse(result.contains("<math"), payload)
            XCTAssertFalse(result.contains("<a "), payload)
            XCTAssertTrue(result.contains("&lt;"), payload)
        }
    }

    func testMarkdownRendererDoesNotParseInvalidTableDelimiter() throws {
        let result = try renderMarkdownWithJavaScript(
            """
            | a | b |
            | nope | nope |
            """
        )

        XCTAssertFalse(result.contains("<table>"))
        XCTAssertTrue(result.contains("<p>| a | b | | nope | nope |</p>"))
    }

    func testDisplayMathWithBlankLinesStaysInOneTextNode() throws {
        for equation in [#"\["# + "\n\nx^2 < y\n\n" + #"\]"#, "$$\n\nx^2 < y\n\n$$"] {
            let html = try renderMarkdownWithJavaScript(equation)
            XCTAssertEqual(html, "<p>" + equation.replacingOccurrences(of: "<", with: "&lt;") + "</p>")
        }
    }

    private func loadMarkdownRendererSource() throws -> String {
        let testDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let rendererURL = testDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("YamabikoChat")
            .appendingPathComponent("App")
            .appendingPathComponent("Resources")
            .appendingPathComponent("mathjax")
            .appendingPathComponent("markdown-renderer.js")

        return try String(contentsOf: rendererURL, encoding: .utf8)
    }

    private func renderMarkdownWithJavaScript(_ input: String) throws -> String {
        let script = try loadMarkdownRendererSource()
        guard let context = JSContext() else {
            XCTFail("Failed to create JSContext")
            return ""
        }

        var jsError: String?
        context.exceptionHandler = { _, exception in
            jsError = exception?.toString()
        }

        context.evaluateScript("var window = this;")
        context.evaluateScript(script)
        if let jsError {
            XCTFail("Renderer script evaluation failed: \(jsError)")
        }

        guard let renderer = context.objectForKeyedSubscript("yamabikoRenderMarkdown") else {
            XCTFail("Renderer function was not registered")
            return ""
        }

        let output = renderer.call(withArguments: [input])?.toString() ?? ""
        if let jsError {
            XCTFail("Renderer function failed: \(jsError)")
        }
        return output
    }

}
