import XCTest
@testable import YamabikoChat

final class SvgCodeExtractorTests: XCTestCase {
    func testExtractsFencedSvgBlock() {
        let text = """
        Before
        ```svg
        <svg viewBox="0 0 10 10"><path d="M0 0 L10 10" /></svg>
        ```
        After
        """

        let blocks = SvgCodeExtractor.extract(from: text)

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].language, "svg")
        XCTAssertEqual(blocks[0].extractionMethod, "markdown")
        XCTAssertTrue(blocks[0].content.contains("<svg"))
    }

    func testPromotesFencedNonSvgLanguageWhenContentIsSvg() {
        let text = """
        ```xml
        <svg viewBox="0 0 10 10"><circle cx="5" cy="5" r="4" /></svg>
        ```
        """

        let blocks = SvgCodeExtractor.extract(from: text)

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].language, "svg")
        XCTAssertEqual(blocks[0].extractionMethod, "markdown")
    }

    func testExtractsInlineSvgOutsideCodeFence() {
        let text = """
        Here
        <svg viewBox="0 0 10 10"><rect width="10" height="10" /></svg>
        End
        """

        let blocks = SvgCodeExtractor.extract(from: text)

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].extractionMethod, "inline_svg")
    }

    func testSkipsInlineSvgInsideFencedCodeBlock() {
        let text = """
        ```text
        <svg><g></g></svg>
        ```
        """

        let blocks = SvgCodeExtractor.extract(from: text)

        XCTAssertTrue(blocks.isEmpty)
    }

    func testRemoveExtractedBlocksNormalizesSpacing() {
        let text = """
        Before

        ```svg
        <svg viewBox="0 0 10 10"><path d="M0 0 L10 10" /></svg>
        ```

        After
        """
        let blocks = SvgCodeExtractor.extract(from: text)
        let cleaned = SvgCodeExtractor.removeExtractedBlocks(from: text, blocks: blocks)

        XCTAssertEqual(cleaned, "Before\n\nAfter")
    }

    func testExtractedSvgIdentityIsStableAcrossExtractions() {
        let text = """
        ```svg
        <svg viewBox="0 0 10 10"><title>Preview</title><path d="M0 0 L10 10" /></svg>
        ```
        """

        let first = SvgCodeExtractor.extract(from: text)
        let second = SvgCodeExtractor.extract(from: text)

        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first[0].id, second[0].id)
        XCTAssertEqual(first[0].filename, second[0].filename)
        XCTAssertTrue(first[0].filename.hasPrefix("Preview_"))
        XCTAssertTrue(first[0].filename.hasSuffix(".svg"))
    }

    func testDoesNotExtractFencedHtmlWithNestedSvg() {
        let text = """
        ```html
        <!DOCTYPE html>
        <html lang="ja">
        <head>
        <title>解説 2008 物理</title>
        </head>
        <body>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
            <circle cx="5" cy="5" r="4" />
        </svg>
        </body>
        </html>
        ```
        """

        let blocks = SvgCodeExtractor.extract(from: text)

        XCTAssertTrue(blocks.isEmpty)
    }

    func testDoesNotExtractHtmlDocumentLabeledAsSvg() {
        let text = """
        ```svg
        <!DOCTYPE html>
        <html lang="ja">
        <head>
        <meta charset="UTF-8">
        <title>【解説】2008 甲南大 物理 (一部)- 電気力線と電場</title>
        </head>
        <body>
        <p>ると、</p>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 20">
            <text x="0" y="15">4\\pi k_0 q</text>
        </svg>
        </body>
        </html>
        ```
        """

        let blocks = SvgCodeExtractor.extract(from: text)

        XCTAssertTrue(blocks.isEmpty)
    }

    func testDoesNotExtractInlineSvgInsideUnfencedHtmlDocument() {
        let text = """
        <!DOCTYPE html>
        <html>
        <head><title>2008 physics</title></head>
        <body>
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
            <rect width="10" height="10" />
        </svg>
        </body>
        </html>
        """

        let blocks = SvgCodeExtractor.extract(from: text)

        XCTAssertTrue(blocks.isEmpty)
    }

    func testExtractsStandaloneSvgAfterClosedHtmlDocument() {
        let text = """
        <html><body><p>page</p></body></html>
        <svg viewBox="0 0 10 10"><rect width="10" height="10" /></svg>
        """

        let blocks = SvgCodeExtractor.extract(from: text)

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].extractionMethod, "inline_svg")
    }

    func testExtractsSvgWithXmlDeclaration() {
        let text = """
        ```xml
        <?xml version="1.0" encoding="UTF-8"?>
        <!-- icon -->
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
            <circle cx="5" cy="5" r="4" />
        </svg>
        ```
        """

        let blocks = SvgCodeExtractor.extract(from: text)

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].language, "svg")
        XCTAssertEqual(blocks[0].extractionMethod, "markdown")
    }
}
