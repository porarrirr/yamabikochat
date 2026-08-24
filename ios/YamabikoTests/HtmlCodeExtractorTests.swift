import XCTest
@testable import YamabikoChat

final class HtmlCodeExtractorTests: XCTestCase {
    func testPreviewPolicyDoesNotExtractHtmlWhileStreaming() {
        let text = """
        ```html
        <!doctype html><html><body>preview</body></html>
        ```
        """

        XCTAssertTrue(
            HtmlPreviewPolicy.blocks(
                from: text,
                isChatError: false,
                isActivelyStreaming: true
            ).isEmpty
        )
        XCTAssertEqual(
            HtmlPreviewPolicy.blocks(
                from: text,
                isChatError: false,
                isActivelyStreaming: false
            ).count,
            1
        )
    }

    func testExtractsFencedHtmlBlock() {
        let text = """
        Before
        ```html
        <!DOCTYPE html>
        <html lang="ja">
        <head><title>解説 2008 物理</title></head>
        <body><p>hello</p></body>
        </html>
        ```
        After
        """

        let blocks = HtmlCodeExtractor.extract(from: text)

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].language, "html")
        XCTAssertEqual(blocks[0].extractionMethod, "markdown")
        XCTAssertTrue(blocks[0].filename.hasSuffix(".html"))
        XCTAssertTrue(blocks[0].content.contains("<!DOCTYPE html>"))
    }

    func testExtractsHtmlDocumentLabeledAsSvg() {
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

        let blocks = HtmlCodeExtractor.extract(from: text)

        XCTAssertEqual(blocks.count, 1)
        XCTAssertEqual(blocks[0].language, "html")
        XCTAssertTrue(blocks[0].filename.hasPrefix("2008"))
        XCTAssertTrue(blocks[0].filename.hasSuffix(".html"))
    }

    func testDoesNotExtractRootSvg() {
        let text = """
        ```svg
        <svg viewBox="0 0 10 10"><circle cx="5" cy="5" r="4" /></svg>
        ```
        """

        let blocks = HtmlCodeExtractor.extract(from: text)

        XCTAssertTrue(blocks.isEmpty)
    }

    func testDoesNotExtractXmlRootSvg() {
        let text = """
        ```xml
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
            <circle cx="5" cy="5" r="4" />
        </svg>
        ```
        """

        let blocks = HtmlCodeExtractor.extract(from: text)

        XCTAssertTrue(blocks.isEmpty)
    }

    func testRemoveExtractedBlocksLeavesSurroundingText() {
        let text = """
        Before

        ```html
        <!DOCTYPE html>
        <html><head><title>Page</title></head><body></body></html>
        ```

        After
        """
        let blocks = HtmlCodeExtractor.extract(from: text)
        let cleaned = HtmlCodeExtractor.removeExtractedBlocks(from: text, blocks: blocks)

        XCTAssertEqual(cleaned, "Before\n\nAfter")
    }
}
