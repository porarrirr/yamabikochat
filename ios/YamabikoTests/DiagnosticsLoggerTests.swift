import Foundation
import XCTest
@testable import YamabikoChat

final class DiagnosticsLoggerTests: XCTestCase {
    func testRenderedErrorLinesIncludeUnderlyingFoundationModelsError() {
        let internalError = NSError(
            domain: "GenerativeFunctionsFoundation.GenerativeError",
            code: 2_010_000,
            userInfo: [NSLocalizedDescriptionKey: "Internal generation failure"]
        )
        let publicError = NSError(
            domain: "FoundationModels.LanguageModelError",
            code: -1,
            userInfo: [
                NSLocalizedDescriptionKey: "Generation failed",
                NSUnderlyingErrorKey: internalError
            ]
        )

        let lines = DiagnosticsLogger.renderedErrorLines(publicError)

        XCTAssertTrue(lines.contains { $0.contains("error=FoundationModels.LanguageModelError (-1)") })
        XCTAssertTrue(lines.contains { $0.contains("underlying[1].error=GenerativeFunctionsFoundation.GenerativeError (2010000)") })
    }
}
