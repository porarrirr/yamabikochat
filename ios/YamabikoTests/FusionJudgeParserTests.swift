import XCTest
@testable import YamabikoChat

final class FusionJudgeParserTests: XCTestCase {
    private let validJSON = """
    {
      "consensus": ["both agree"],
      "contradictions": [],
      "unique_insights": [],
      "coverage_gaps": [],
      "suspected_errors": [],
      "strongest_answer_parts": [{"model": "m1", "part": "answer", "reason": "clear"}],
      "recommended_final_position": "Merged",
      "confidence": "high"
    }
    """

    func testParseValidJSON() {
        let analysis = FusionJudgeParser.parse(validJSON)
        XCTAssertNotNil(analysis)
        XCTAssertEqual(analysis?.recommendedFinalPosition, "Merged")
        XCTAssertEqual(analysis?.confidence, .high)
        XCTAssertEqual(analysis?.consensus, ["both agree"])
    }

    func testParseWrappedInMarkdownFence() {
        let wrapped = """
        ```json
        \(validJSON)
        ```
        """
        let analysis = FusionJudgeParser.parse(wrapped)
        XCTAssertNotNil(analysis)
        XCTAssertEqual(analysis?.recommendedFinalPosition, "Merged")
    }

    func testParseInvalidJSONReturnsNil() {
        XCTAssertNil(FusionJudgeParser.parse("not json"))
        XCTAssertNil(FusionJudgeParser.parse("{invalid"))
    }

    func testExtractJSONFindsObjectBoundaries() {
        let text = "Here is the result:\n\(validJSON)\nDone."
        let extracted = FusionJudgeParser.extractJSON(from: text)
        XCTAssertTrue(extracted.hasPrefix("{"))
        XCTAssertTrue(extracted.hasSuffix("}"))
        XCTAssertNotNil(FusionJudgeParser.parse(extracted))
    }
}