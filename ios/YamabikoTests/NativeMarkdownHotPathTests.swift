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
        // Detect delimiters before CommonMark consumes escapes.
        for source in ["式 $x^2$ です", "式 $$x^2$$ です", #"式 \\[x^2\\] です"#, #"式 \\(x^2\\) です"#, #"式 \(x^2\) です"#, #"式 \[x^2\] です"#] {
            guard case .math = try XCTUnwrap(NativeMarkdownParser.parse(source).first) else {
                return XCTFail("Expected math for \(source)")
            }
            guard case .paragraph = try XCTUnwrap(NativeMarkdownParser.parse(source, rendersMath: false).first) else {
                return XCTFail("Explicitly disabled math should remain native")
            }
        }
        for source in ["普通の本文", "Price: $5 and $10", "Unclosed $x", #"Escaped \$5"#, #"`$x^2$`"#, #"`\[x\]`"#] {
            guard case .paragraph = try XCTUnwrap(NativeMarkdownParser.parse(source).first) else {
                return XCTFail("Unexpected math for \(source)")
            }
        }
    }

    func testDisplayMathPreservesBlankLinesCommandsAndSurroundingMarkdown() throws {
        let equation = #"\["# + "\n\ndS=2" + #"\pi r^2\cos\theta\,d\theta"# + "\n\n" + #"\]"#
        let blocks = NativeMarkdownParser.parse("**球の面積**\n\n" + equation + "\n\n終わり")
        XCTAssertEqual(blocks.count, 3)
        guard case let .math(_, markdown) = blocks[1] else { return XCTFail("Expected display math") }
        XCTAssertEqual(markdown, equation)
        guard case .paragraph = blocks[2] else { return XCTFail("Expected following paragraph") }
    }

    func testMatrixEqualityIsMathRatherThanSetextHeading() throws {
        let source = #"""
        点 \(P(\beta)\) を回転させると、
        \[
        \begin{pmatrix}
        \cos(\alpha+\beta)\\
        \sin(\alpha+\beta)
        \end{pmatrix}
        =
        \begin{pmatrix}
        \cos\beta\\
        \sin\beta
        \end{pmatrix}.
        \]
        """#
        for fixture in [source, source.replacingOccurrences(of: #"\["#, with: "$$")
            .replacingOccurrences(of: #"\]"#, with: "$$")] {
            let blocks = NativeMarkdownParser.parse(fixture)
            XCTAssertEqual(blocks.count, 1)
            guard case let .math(_, markdown) = try XCTUnwrap(blocks.first) else {
                return XCTFail("Matrix equality must preserve its original TeX, including the equals line")
            }
            XCTAssertEqual(markdown, fixture)
        }
    }

    func testMathPreservesMarkdownFormattingAndEscapesInOriginalSource() throws {
        let source = #"**公式** \(4\pi r^2\) と `code`"#
        guard case let .math(_, markdown) = try XCTUnwrap(NativeMarkdownParser.parse(source).first) else {
            return XCTFail("Expected inline math")
        }
        XCTAssertEqual(markdown, source)
    }

    func testMathListsPreserveSourceAndRespectDisabledRendering() throws {
        for marker in ["1.", "-", "7."] {
            let source = "\(marker) **半径** $r$\n\n   $$\n   S = 4" + #"\pi r^2"# + "\n\n   $$\n\n\(marker) 次の項目"
            let blocks = NativeMarkdownParser.parse(source)
            guard case let .math(_, markdown) = try XCTUnwrap(blocks.first) else {
                return XCTFail("Expected math list for \(marker)")
            }
            XCTAssertEqual(markdown, source)
            guard case .list = try XCTUnwrap(NativeMarkdownParser.parse(source, rendersMath: false).first) else {
                return XCTFail("Explicitly disabled math should keep native lists")
            }
        }
        for source in ["1. `$r$`", "- 普通の本文", "1. Price: $5 and $10"] {
            guard case .list = try XCTUnwrap(NativeMarkdownParser.parse(source).first) else {
                return XCTFail("Non-math lists must remain native")
            }
        }
    }

    func testHeadingsAndTablesRouteOriginalMathToRenderer() throws {
        for source in [
            #"### 公式 \(a^2+b^2=c^2\)"#,
            "| 式 |\n| --- |\n| $x^2$ |"
        ] {
            guard case let .math(_, markdown) = try XCTUnwrap(NativeMarkdownParser.parse(source).first) else {
                return XCTFail("Expected original math source: \(source)")
            }
            XCTAssertEqual(markdown, source)
            XCTAssertFalse(NativeMarkdownParser.parse(source, rendersMath: false).contains {
                if case .math = $0 { return true }
                return false
            })
        }
    }

    func testDisplayMathSurvivesOtherCommonMarkBlockKinds() throws {
        for interior in ["x\n---\ny", "x\n- y", "x\n\n    y", "x\n\n<div>\ny\n</div>"] {
            let source = "\\[\n" + interior + "\n\\]"
            let blocks = NativeMarkdownParser.parse(source)
            XCTAssertEqual(blocks.count, 1, source)
            guard case let .math(_, markdown) = try XCTUnwrap(blocks.first) else {
                return XCTFail("Expected complete display math: \(source)")
            }
            XCTAssertEqual(markdown, source)
        }
    }

    @MainActor
    func testStreamingRendersClosedMathBeforeAnswerFinishes() throws {
        for (opening, closing) in [("$", "$"), ("$$", "$$"), (#"\("#, #"\)"#), (#"\["#, #"\]"#)] {
            let parser = NativeMarkdownIncrementalParser()
            let unfinished = "式 " + opening + "x^2"
            XCTAssertFalse(parser.streamingBlocks(for: unfinished).contains {
                if case .math = $0 { return true }
                return false
            })
            if closing == "$$" {
                XCTAssertFalse(parser.streamingBlocks(for: unfinished + "$").contains {
                    if case .math = $0 { return true }
                    return false
                }, "A display equation needs both closing dollars")
            }
            let completed = unfinished + closing
            guard case let .math(id, markdown) = try XCTUnwrap(parser.streamingBlocks(for: completed).first) else {
                return XCTFail("Closed equation should render during streaming")
            }
            XCTAssertEqual(markdown, completed)
            for suffix in ["\n\n次の段落", "\n\n次の段落\n\nさらに続く\n\n末尾"] {
                let blocks = parser.streamingBlocks(for: completed + suffix)
                XCTAssertEqual(blocks.first, .math(id: id, markdown: completed))
                XCTAssertEqual(blocks, NativeMarkdownParser.parse(completed + suffix))
            }
        }
    }

    @MainActor
    func testStreamingDisplayMathDoesNotFreezeAcrossBlankLines() {
        for (opening, closing) in [("$$", "$$"), (#"\["#, #"\]"#)] {
            let parser = NativeMarkdownIncrementalParser()
            let source = "前文\n\n" + opening + "\n\na\n\nb\n\nc\n\nd\n\n" + closing + "\n\n続き\n\n末尾"
            // Replay every token, including the individual closing delimiter bytes.
            var partial = ""
            for character in source {
                partial.append(character)
                XCTAssertEqual(parser.streamingBlocks(for: partial), NativeMarkdownParser.parse(partial), partial)
            }
            XCTAssertEqual(parser.streamingBlocks(for: source), NativeMarkdownParser.parse(source))
        }
    }

    @MainActor
    func testStreamingMathInListsAndCodeMatchesFreshParsing() {
        for source in [
            "1. 項目\n2. 続き\n3. $x^2$\n4. 末尾\n5. 追加",
            "```tex\n$$x$$\n```\n\n`$x$`\n\nPrice: $5 and $10",
            #"見出し \(x\)"# + "\n\n$$\na\n\nb\n\n$$\n\n次\n\n末尾"
        ] {
            let parser = NativeMarkdownIncrementalParser()
            var partial = ""
            for character in source {
                partial.append(character)
                XCTAssertEqual(parser.streamingBlocks(for: partial), NativeMarkdownParser.parse(partial), partial)
            }
            XCTAssertEqual(parser.streamingBlocks(for: "置き換え $y$"), NativeMarkdownParser.parse("置き換え $y$"))
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
