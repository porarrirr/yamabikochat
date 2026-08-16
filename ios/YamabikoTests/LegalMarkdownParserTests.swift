import XCTest
@testable import YamabikoChat

final class LegalMarkdownParserTests: XCTestCase {
    func testParsesHeadingsParagraphsTablesAndCode() {
        let markdown = """
        # Third-party notices

        See [LICENSE](LICENSE) and **Apache License 2.0**.

        ## Android libraries

        | Component | Version | SPDX | Source |
        | --- | --- | --- | --- |
        | Markwon (`core`) | 4.6.2 | Apache-2.0 | https://github.com/noties/Markwon |
        | AndroidSVG | 1.4 | Apache-2.0 | https://github.com/BigBadaboom/androidsvg |

        ## License texts

        ```
        MIT License text
        ```
        """

        let blocks = LegalMarkdownParser.parse(markdown)
        XCTAssertEqual(blocks.count, 6)

        guard case let .heading(level, title) = blocks[0] else {
            return XCTFail("expected heading")
        }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(title, "Third-party notices")

        guard case let .paragraph(paragraph) = blocks[1] else {
            return XCTFail("expected paragraph")
        }
        XCTAssertEqual(paragraph, "See LICENSE and Apache License 2.0.")
        XCTAssertFalse(paragraph.contains("["))
        XCTAssertFalse(paragraph.contains("**"))

        guard case let .heading(sectionLevel, sectionTitle) = blocks[2] else {
            return XCTFail("expected section heading")
        }
        XCTAssertEqual(sectionLevel, 2)
        XCTAssertEqual(sectionTitle, "Android libraries")

        guard case let .table(headers, rows) = blocks[3] else {
            return XCTFail("expected table")
        }
        XCTAssertEqual(headers, ["Component", "Version", "SPDX", "Source"])
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0][0], "Markwon (core)")
        XCTAssertEqual(rows[0][1], "4.6.2")
        XCTAssertEqual(rows[1][0], "AndroidSVG")

        guard case let .code(code) = blocks[5] else {
            return XCTFail("expected code")
        }
        XCTAssertEqual(code, "MIT License text")
    }

    func testIgnoresAlignmentRowAndKeepsCellCount() {
        let markdown = """
        | Package | Version | License |
        | :--- | ---: | --- |
        | typebox | 1.3.7 | MIT |
        """
        let blocks = LegalMarkdownParser.parse(markdown)
        guard case let .table(headers, rows) = blocks.first else {
            return XCTFail("expected table")
        }
        XCTAssertEqual(headers.count, 3)
        XCTAssertEqual(rows, [["typebox", "1.3.7", "MIT"]])
    }
}
