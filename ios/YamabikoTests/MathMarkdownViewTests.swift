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

        XCTAssertTrue(result.contains("$a < b$"))
        XCTAssertTrue(result.contains("$c & d$"))
        XCTAssertFalse(result.contains("&lt;"))
        XCTAssertFalse(result.contains("&amp;"))
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
}
