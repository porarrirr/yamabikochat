import XCTest
@testable import YamabikoChat

final class NativeMarkdownHotPathTests: XCTestCase {
    func testMultipleBareURLsPreserveUnicodeTextPunctuationAndDestinations() throws {
        let blocks = NativeMarkdownParser.parse("👨‍👩‍👧‍👦 e\u{301} 参照 HTTPS://www.example.com/a。 次は http://other.example/b！ 終わり")
        guard case let .paragraph(_, text) = try XCTUnwrap(blocks.first) else {
            return XCTFail("Expected a paragraph")
        }
        XCTAssertEqual(String(text.characters), "👨‍👩‍👧‍👦 e\u{301} 参照 example.com↗。 次は other.example↗！ 終わり")
        XCTAssertEqual(text.runs.compactMap(\.link).map(\.absoluteString), ["HTTPS://www.example.com/a", "http://other.example/b"])
    }

    func testNonURLColonAndCodeRemainUnlinked() throws {
        let blocks = NativeMarkdownParser.parse("時刻 12:30 と mailto:hello@example.com と `https://example.com` と通常の本文")
        guard case let .paragraph(_, text) = try XCTUnwrap(blocks.first) else {
            return XCTFail("Expected a paragraph")
        }
        XCTAssertTrue(text.runs.compactMap(\.link).isEmpty)
        XCTAssertTrue(String(text.characters).contains("https://example.com"))
        XCTAssertTrue(text.runs.contains { $0.inlinePresentationIntent == .code })
    }

    func testMathDetectionPreservesDollarAndLiteralBackslashDelimiters() throws {
        // Markdown consumes one level of backslash escaping before math detection.
        for source in ["式 $x^2$ です", "式 $$x^2$$ です", #"式 \\[x^2\\] です"#, #"式 \\(x^2\\) です"#] {
            guard case .math = try XCTUnwrap(NativeMarkdownParser.parse(source).first) else {
                return XCTFail("Expected math for \(source)")
            }
            guard case .paragraph = try XCTUnwrap(NativeMarkdownParser.parse(source, rendersMath: false).first) else {
                return XCTFail("Streaming must defer math rendering")
            }
        }
        for source in ["普通の本文", "Price: $5 and $10", "Unclosed $x", #"Escaped \$5"#, #"式 \[x^2\] です"#] {
            guard case .paragraph = try XCTUnwrap(NativeMarkdownParser.parse(source).first) else {
                return XCTFail("Unexpected math for \(source)")
            }
        }
    }

    @MainActor
    func testStreamingContextResetsAfterReferencesAndUnicodeReplacements() {
        let parser = NativeMarkdownIncrementalParser()
        let prefix = "# 日本語\n\n👨‍👩‍👧‍👦 e\u{301}\n\nTail\n\n"
        let sources = [
            prefix,
            prefix + "[link][ref]",
            prefix + "[link][ref]\n\n[ref]: https://example.com",
            prefix.replacingOccurrences(of: "e\u{301}", with: "é"),
            "",
            prefix,
            prefix + "Plain text",
            prefix + "Plain text"
        ]
        for source in sources {
            let bridged = NSString(string: source) as String
            XCTAssertEqual(parser.streamingBlocks(for: bridged), NativeMarkdownParser.parse(source, rendersMath: false))
        }
    }
}
