import XCTest
@testable import YamabikoChat

final class GenUIHostPolicyTests: XCTestCase {
    func testFlowFixtureAndDeclarativeStageContract() throws {
        let document = GenUIDocument(title: "Flow", code: GenUIRichDemoFixture.flowCode)
        let json = String(decoding: try JSONEncoder().encode(document), as: UTF8.self)
        XCTAssertEqual(try GenUIDocument.validated(from: json), document)
        XCTAssertNoThrow(try GenUIDocument.validated(from: #"{"title":"Flow","ui":{"type":"list","props":{"connector":true,"marker":"none"},"children":[{"type":"list-item","props":{"icon":"cpu","iconColor":"info","variant":"outline","label":"Compute"}}]}}"#))
        let properties = try XCTUnwrap(GenUIDocument.componentCatalog["list-item"])
        for property in ["icon", "iconColor", "variant"] {
            XCTAssertTrue(properties.contains(property))
            XCTAssertTrue(GenUITool.definition.description.contains("\"" + property + "\""))
        }
    }

    func testCodeValidationParsesWithoutExecutingTheBody() throws {
        XCTAssertThrowsError(try GenUICodeValidator.validate("return ("))
        XCTAssertNoThrow(try GenUICodeValidator.validate("throw new Error('must not execute');"))
    }

    func testExternalLinksRequireHTTPSWithoutEmbeddedCredentials() {
        XCTAssertNotNil(GenUIHostPolicy.externalURL("https://example.com/page"))
        for url in ["javascript:alert(1)", "file:///private/secret", "data:text/html,hello", "http://example.com", "https://user:password@example.com"] {
            XCTAssertNil(GenUIHostPolicy.externalURL(url))
        }
    }

    func testInteractionSnapshotsRequireJSONWithoutFixedByteLimit() {
        XCTAssertEqual(GenUIHostPolicy.snapshot(from: ["bindings": ["count": 3]])?["bindings"], .object(["count": .number(3)]))
        XCTAssertNil(GenUIHostPolicy.snapshot(from: ["value": Double.infinity]))
        let text = String(repeating: "資料", count: 100_000)
        XCTAssertEqual(GenUIHostPolicy.snapshot(from: ["value": text])?["value"], .string(text))
    }

    func testRichDemoUsesTheSameValidatedToolContract() throws {
        let document = GenUIDocument(title: "Demo", code: GenUIRichDemoFixture.code)
        let json = String(decoding: try JSONEncoder().encode(document), as: UTF8.self)
        XCTAssertEqual(try GenUIDocument.validated(from: json), document)
    }
}
