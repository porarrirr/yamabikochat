import XCTest
@testable import YamabikoChat

final class GenUICELRuntimeTests: XCTestCase {
    private func result(_ expression: String, _ bindings: [String: Any] = [:]) throws -> [String: Any] {
        let data = try JSONSerialization.data(withJSONObject: ["expression": expression, "bindings": bindings])
        let output = GenUICELRuntime.evaluate(String(decoding: data, as: UTF8.self))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any])
    }

    func testOriginalArithmeticCollectionsAndScope() throws {
        XCTAssertEqual(try result("price * quantity", ["price": 12, "quantity": 3])["value"] as? Int, 36)
        XCTAssertEqual(try result("items.map(x, x * 2)", ["items": [1, 2, 3]])["value"] as? [Int], [2, 4, 6])
        XCTAssertEqual(try result("items.filter(x, x >= 2)", ["items": [1, 2, 3]])["value"] as? [Int], [2, 3])
        XCTAssertEqual(try result("user.name", ["user": ["name": "Tokyo"]])["value"] as? String, "Tokyo")
    }

    func testCompiledExpressionReadsUpdatedState() throws {
        XCTAssertEqual(try result("n + 1", ["n": 2])["value"] as? Int, 3)
        XCTAssertEqual(try result("n + 1", ["n": 8])["value"] as? Int, 9)
    }

    func testInvalidExpressionsReturnTheOriginalTypedError() throws {
        let value = try result("items.map(")
        XCTAssertEqual(value["kind"] as? String, "CELExpressionError")
        XCTAssertNotNil(value["error"])
        XCTAssertNil(value["value"])
        XCTAssertEqual(try result("1 + 1")["value"] as? Int, 2)
    }

    func testOriginalSVGAreaAndDonutRenderersExecuteTheirRecoveredCode() throws {
        func render(_ type: String) throws -> String {
            let data = try JSONSerialization.data(withJSONObject: ["operation": "chart", "width": 320, "height": 240, "viewModel": ["chartType": type, "theme": "light", "data": [["x": "A", "value": 3], ["x": "B", "value": 5]], "series": [["dataKey": "value", "type": type]], "xAxis": "x", "innerRadius": "49%"]])
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(GenUICELRuntime.evaluate(String(decoding: data, as: UTF8.self)).utf8)) as? [String: Any])
            XCTAssertNil(object["error"])
            return try XCTUnwrap(object["svg"] as? String)
        }
        let area = try render("area")
        XCTAssertTrue(area.contains("viewBox=\"0 0 320 240\""))
        XCTAssertTrue(area.contains("<path"))
        let pie = try render("pie")
        XCTAssertTrue(pie.contains("A 79.2 79.2"))
        XCTAssertTrue(pie.contains("#0169cc"))
    }

    func testCELPropValidationPreservesTheExpression() throws {
        let doc = try GenUIDocument.validated(from: #"{"title":"CEL","ui":{"type":"input","props":{"$value":"price * quantity"}},"state":{"price":12,"quantity":3}}"#)
        XCTAssertEqual(doc.ui?.props?["$value"], .string("price * quantity"))
        XCTAssertThrowsError(try GenUIDocument.validated(from: #"{"title":"CEL","ui":{"type":"input","props":{"$value":12}}}"#))
    }
}
