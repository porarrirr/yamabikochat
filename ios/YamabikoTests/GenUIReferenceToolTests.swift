import XCTest
@testable import YamabikoChat

final class GenUIReferenceToolTests: XCTestCase {
    func testEveryCanonicalSourceIsAvailableVerbatim() throws {
        XCTAssertEqual(GenUIReferenceCatalog.components.count, 283)
        for name in GenUIReferenceCatalog.components.keys {
            let source = try XCTUnwrap(GenUIReferenceTool.source(named: name), name)
            XCTAssertTrue(source.hasPrefix("((createComponent) => {"), name)
            XCTAssertTrue(source.hasSuffix("})()))"), name)
        }
    }

    func testLookupReturnsStateContractAndOriginalCalculation() async throws {
        let result = try await GenUIReferenceTool().execute(call: ToolCall(id: "lookup", name: GenUIReferenceTool.name, argumentsJSON: #"{"componentName":"CurrencyConverterWidget"}"#))
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.content.utf8)) as? [String: Any])
        XCTAssertTrue((object["stateFields"] as? [String] ?? []).contains("exchange_rate"))
        XCTAssertTrue((object["source"] as? String ?? "").contains("function currencyProduct"))
        XCTAssertTrue(object["nextOffset"] is NSNull)
    }

    func testPagesReassembleWithoutLosingSourceCharacters() async throws {
        let name = "DigitalTimerWidget"
        let source = try XCTUnwrap(GenUIReferenceTool.source(named: name))
        var offset = 0
        var restored = ""
        while offset < source.count {
            let arguments = "{\"componentName\":\"\(name)\",\"sourceOffset\":\(offset),\"maxCharacters\":1024}"
            let result = try await GenUIReferenceTool().execute(call: ToolCall(id: "page", name: GenUIReferenceTool.name, argumentsJSON: arguments))
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.content.utf8)) as? [String: Any])
            let page = try XCTUnwrap(object["source"] as? String)
            restored += page
            offset += page.count
        }
        XCTAssertEqual(restored, source)
    }

    func testUnknownComponentReturnsAnExplicitError() async {
        let registry = LocalToolRegistry(executors: [GenUIReferenceTool()])
        let result = await registry.execute(call: ToolCall(id: "missing", name: GenUIReferenceTool.name, argumentsJSON: #"{"componentName":"MissingWidget"}"#))
        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.content.contains("unknown reference component"))
    }
}
