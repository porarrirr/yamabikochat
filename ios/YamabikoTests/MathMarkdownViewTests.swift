import XCTest
import JavaScriptCore
@testable import YamabikoChat

final class MathMarkdownViewTests: XCTestCase {
    func testBuildHTMLIncludesMathJaxWhenEnabled() {
        let html = MathMarkdownHTMLBuilder.buildHTML(
            markdownPayload: "\"hello\"",
            markdownRendererScript: "window.yamabikoRenderMarkdown = function(){ return ''; };",
            bodyTextColor: "#000000",
            codeBackgroundColor: "#111111",
            borderColor: "#222222",
            linkColor: "#333333",
            mathRenderingEnabled: true,
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

    func testBuildHTMLOmitsMathJaxWhenDisabled() {
        let html = MathMarkdownHTMLBuilder.buildHTML(
            markdownPayload: "\"hello\"",
            markdownRendererScript: "window.yamabikoRenderMarkdown = function(){ return ''; };",
            bodyTextColor: "#000000",
            codeBackgroundColor: "#111111",
            borderColor: "#222222",
            linkColor: "#333333",
            mathRenderingEnabled: false,
            mathJaxScriptTag: "<script src=\"tex-svg.js\"></script>"
        )

        XCTAssertFalse(html.contains("window.MathJax ="))
        XCTAssertFalse(html.contains("tex-svg.js"))
        XCTAssertFalse(html.contains("typesetPromise([root])"))
    }

    func testBuildHTMLIncludesMathOverflowGuards() {
        let html = MathMarkdownHTMLBuilder.buildHTML(
            markdownPayload: "\"$$x$$\"",
            markdownRendererScript: "window.yamabikoRenderMarkdown = function(){ return ''; };",
            bodyTextColor: "#000000",
            codeBackgroundColor: "#111111",
            borderColor: "#222222",
            linkColor: "#333333",
            mathRenderingEnabled: true,
            mathJaxScriptTag: "<script src=\"tex-svg.js\"></script>"
        )

        XCTAssertTrue(html.contains("mjx-container[display=\"true\"]"))
        XCTAssertTrue(html.contains("overflow-x: auto;"))
        XCTAssertTrue(html.contains("mjx-container svg"))
        XCTAssertTrue(html.contains("max-width: 100%;"))
    }

    func testBuildHTMLIncludesCodeBlockCopyBridge() {
        let html = MathMarkdownHTMLBuilder.buildHTML(
            markdownPayload: "\"```swift\\nprint(1)\\n```\"",
            markdownRendererScript: "window.yamabikoRenderMarkdown = function(){ return ''; };",
            bodyTextColor: "#000000",
            codeBackgroundColor: "#111111",
            borderColor: "#222222",
            linkColor: "#333333",
            mathRenderingEnabled: false,
            mathJaxScriptTag: ""
        )

        XCTAssertTrue(html.contains("copyCodeBlock"))
        XCTAssertTrue(html.contains("yamabiko-copy-button"))
        XCTAssertTrue(html.contains("コピー済み"))
    }

    func testBuildHTMLIncludesTableStyles() {
        let html = MathMarkdownHTMLBuilder.buildHTML(
            markdownPayload: "\"| A | B |\\n| --- | --- |\\n| 1 | 2 |\"",
            markdownRendererScript: "window.yamabikoRenderMarkdown = function(){ return ''; };",
            bodyTextColor: "#000000",
            codeBackgroundColor: "#111111",
            borderColor: "#222222",
            linkColor: "#333333",
            mathRenderingEnabled: false,
            mathJaxScriptTag: ""
        )

        XCTAssertTrue(html.contains(".yamabiko-table-wrap"))
        XCTAssertTrue(html.contains("touch-action: pan-x pan-y"))
        XCTAssertTrue(html.contains("overscroll-behavior-x: contain"))
        XCTAssertTrue(html.contains(".yamabiko-table-wrap mjx-container"))
        XCTAssertTrue(html.contains("max-width: none"))
        XCTAssertTrue(html.contains("table {"))
        XCTAssertTrue(html.contains("th, td {"))
        XCTAssertTrue(html.contains("min-width: 8.5em"))
        XCTAssertTrue(html.contains("max-width: 18em"))
        XCTAssertTrue(html.contains("border-bottom: 1px solid"))
        XCTAssertTrue(html.contains("background: transparent"))
        XCTAssertTrue(html.contains("font-weight: 400"))
    }

    func testBuildHTMLIncludesHorizontalScrollHelper() {
        let html = MathMarkdownHTMLBuilder.buildHTML(
            markdownPayload: "\"| A | B |\\n| --- | --- |\\n| 1 | 2 |\"",
            markdownRendererScript: "window.yamabikoRenderMarkdown = function(){ return ''; };",
            bodyTextColor: "#000000",
            codeBackgroundColor: "#111111",
            borderColor: "#222222",
            linkColor: "#333333",
            mathRenderingEnabled: false,
            mathJaxScriptTag: ""
        )

        XCTAssertTrue(html.contains("enableHorizontalScrollContainers"))
        XCTAssertTrue(html.contains("__yamabikoEnableHorizontalScroll"))
        XCTAssertTrue(html.contains(".yamabiko-table-wrap, pre, mjx-container[display=\"true\"]"))
        XCTAssertTrue(html.contains("var scrollGain = 1.6"))
        XCTAssertTrue(html.contains("startMomentum"))
        XCTAssertTrue(html.contains("requestAnimationFrame(step)"))
        XCTAssertTrue(html.contains("clampScrollLeft"))
    }

    func testHeightScriptMeasuresRenderedMarkdownRootInsteadOfViewport() {
        let script = MathMarkdownHeightScript.source(messageName: "contentHeight")

        XCTAssertTrue(script.contains("getElementById('yamabiko-markdown')"))
        XCTAssertTrue(script.contains("root.scrollHeight"))
        XCTAssertTrue(script.contains("root.offsetHeight"))
        XCTAssertTrue(script.contains("root.getBoundingClientRect()"))
        XCTAssertTrue(script.contains("lastPostedHeight"))
        XCTAssertTrue(script.contains("requestAnimationFrame"))
        XCTAssertTrue(script.contains("postMessage(roundedHeight)"))
        XCTAssertFalse(script.contains("document.documentElement"))
        XCTAssertFalse(script.contains("doc.clientHeight"))
        XCTAssertFalse(script.contains("doc.scrollHeight"))
        XCTAssertFalse(script.contains("doc.offsetHeight"))
    }

    func testBuildHTMLCanShrinkAfterSvgBlockIsExtracted() throws {
        let response = """
        ```svg
        <svg viewBox="0 0 1200 900"><rect width="1200" height="900" /></svg>
        ```

        After
        """
        let blocks = SvgCodeExtractor.extract(from: response)
        let cleaned = SvgCodeExtractor.removeExtractedBlocks(from: response, blocks: blocks)
        let html = MathMarkdownHTMLBuilder.buildHTML(
            markdownPayload: try jsonLiteral(cleaned),
            markdownRendererScript: "window.yamabikoRenderMarkdown = function(value){ return '<p>' + value + '</p>'; };",
            bodyTextColor: "#000000",
            codeBackgroundColor: "#111111",
            borderColor: "#222222",
            linkColor: "#333333",
            mathRenderingEnabled: false,
            mathJaxScriptTag: ""
        )
        let script = MathMarkdownHeightScript.source(messageName: "contentHeight")

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(cleaned, "After")
        XCTAssertTrue(html.contains("var source = \"After\";"))
        XCTAssertFalse(html.contains("<svg viewBox"))
        XCTAssertTrue(script.contains("root.scrollHeight"))
        XCTAssertFalse(script.contains("doc.clientHeight"))
    }

    func testBuildHTMLIncludesLiveMarkdownRenderBridge() {
        let html = MathMarkdownHTMLBuilder.buildHTML(
            markdownPayload: "\"# Title\"",
            markdownRendererScript: "window.yamabikoRenderMarkdown = function(value){ return '<p>' + value + '</p>'; };",
            bodyTextColor: "#000000",
            codeBackgroundColor: "#111111",
            borderColor: "#222222",
            linkColor: "#333333",
            mathRenderingEnabled: true,
            mathJaxScriptTag: "<script src=\"tex-svg.js\"></script>"
        )

        XCTAssertTrue(html.contains("window.__yamabikoRenderSource = function(nextSource, shouldTypeset)"))
        XCTAssertTrue(html.contains("window.__yamabikoRenderSource(source, true);"))
        XCTAssertTrue(html.contains("root.innerHTML = window.yamabikoRenderMarkdown(source);"))
        XCTAssertTrue(html.contains("typesetRenderedContent(root, finishRender)"))
        XCTAssertTrue(html.contains("if (shouldTypeset && window.MathJax && window.MathJax.typesetClear)"))
        XCTAssertTrue(html.contains("if (shouldTypeset)"))
        XCTAssertTrue(html.contains("if (window.__yamabikoSendHeight) window.__yamabikoSendHeight();"))
    }

    func testBuildHTMLUsesSharedRendererForInitialAndLiveContent() {
        let html = MathMarkdownHTMLBuilder.buildHTML(
            markdownPayload: "\"**hello**\"",
            markdownRendererScript: "window.yamabikoRenderMarkdown = function(value){ return '<strong>' + value + '</strong>'; };",
            bodyTextColor: "#000000",
            codeBackgroundColor: "#111111",
            borderColor: "#222222",
            linkColor: "#333333",
            mathRenderingEnabled: false,
            mathJaxScriptTag: ""
        )

        XCTAssertTrue(html.contains("var source = \"**hello**\";"))
        XCTAssertTrue(html.contains("source = String(nextSource || '');"))
        XCTAssertTrue(html.contains("window.__yamabikoRenderSource(source, true);"))
        XCTAssertEqual(html.components(separatedBy: "window.yamabikoRenderMarkdown(source)").count - 1, 1)
    }

    func testBuildHTMLIncludesStreamingTypographyStyles() {
        let html = MathMarkdownHTMLBuilder.buildHTML(
            markdownPayload: "\"hello\"",
            markdownRendererScript: "window.yamabikoRenderMarkdown = function(){ return ''; };",
            bodyTextColor: "#000000",
            codeBackgroundColor: "#111111",
            borderColor: "#222222",
            linkColor: "#333333",
            mathRenderingEnabled: false,
            mathJaxScriptTag: ""
        )

        XCTAssertTrue(html.contains("line-height: 1.48;"))
        XCTAssertTrue(html.contains("font-weight: 650;"))
        XCTAssertTrue(html.contains("h1 { font-size: 1.42em; }"))
        XCTAssertTrue(html.contains("pre code {"))
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

    func testNormalizeEscapedMathIfNeededWhenDisabledReturnsOriginal() {
        let input = #"本文 \$sum$"#
        let normalized = MathMarkdownNormalizer.normalizeEscapedMathIfNeeded(
            input,
            mathRenderingEnabled: false
        )

        XCTAssertEqual(normalized, input)
    }

    func testNormalizeEscapedMathIfNeededWhenEnabledNormalizes() {
        let input = #"本文 \$sum$"#
        let normalized = MathMarkdownNormalizer.normalizeEscapedMathIfNeeded(
            input,
            mathRenderingEnabled: true
        )

        XCTAssertEqual(normalized, #"本文 $sum$"#)
    }

    func testNormalizeEscapedMathIfNeededNormalizesEscapedSequencesWhenMathPresent() {
        let input = #"1行目\\n\\(a+b\\) と \\$sum_{k=1}^{n}k\\$"#
        let normalized = MathMarkdownNormalizer.normalizeEscapedMathIfNeeded(
            input,
            mathRenderingEnabled: true
        )

        let expected = """
        1行目
        \\(a+b\\) と $sum_{k=1}^{n}k$
        """
        XCTAssertEqual(normalized, expected)
    }

    func testNormalizeEscapedMathIfNeededDoesNotNormalizeEscapedSequencesWithoutMath() {
        let input = #"line1\\nline2"#
        let normalized = MathMarkdownNormalizer.normalizeEscapedMathIfNeeded(
            input,
            mathRenderingEnabled: true
        )

        XCTAssertEqual(normalized, input)
    }

    func testNormalizeEscapedMathIfNeededSkipsEscapedSequenceNormalizationInCode() {
        let input = #"""
```text
\\n\\(x\\)
```
本文 \\(x+y\\)
"""#
        let normalized = MathMarkdownNormalizer.normalizeEscapedMathIfNeeded(
            input,
            mathRenderingEnabled: true
        )

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
        let normalized = MathMarkdownNormalizer.normalizeEscapedMathIfNeeded(
            input,
            mathRenderingEnabled: true
        )

        XCTAssertEqual(normalized, input)
    }

    func testMathJaxLoadPlannerPrefersLocalScriptWhenAvailable() {
        let localURL = URL(fileURLWithPath: "/tmp/mathjax/tex-svg.js")

        let plan = MathJaxLoadPlanner.plan(
            mathRenderingEnabled: true,
            localScriptURL: localURL
        )

        XCTAssertTrue(plan.scriptTag.contains("src=\"tex-svg.js\""))
        XCTAssertEqual(plan.baseURL, localURL.deletingLastPathComponent())
    }

    func testMathJaxLoadPlannerDisablesRenderingWhenLocalScriptMissing() {
        var logs: [String] = []

        let plan = MathJaxLoadPlanner.plan(
            mathRenderingEnabled: true,
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

    func testMarkdownRendererUsesPlaceholderKeysWithoutUnderscores() throws {
        let script = try loadMarkdownRendererSource()

        XCTAssertTrue(script.contains("@@YBMATH"))
        XCTAssertTrue(script.contains("@@YBCODE"))
        XCTAssertTrue(script.contains("@@YBLINK"))
        XCTAssertTrue(script.contains("@@YBBARELINK"))
        XCTAssertFalse(script.contains("@@INLINE_MATH_"))
        XCTAssertFalse(script.contains("@@INLINE_CODE_"))
        XCTAssertFalse(script.contains("@@INLINE_LINK_"))
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

    private func jsonLiteral(_ value: String) throws -> String {
        let data = try JSONEncoder().encode(value)
        return String(decoding: data, as: UTF8.self)
    }
}
