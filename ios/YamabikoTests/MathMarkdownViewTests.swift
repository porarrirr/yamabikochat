import XCTest
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
}
