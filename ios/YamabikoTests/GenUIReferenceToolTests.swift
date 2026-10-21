import XCTest
@testable import YamabikoChat

final class GenUIReferenceToolTests: XCTestCase {
    private func lookup(_ arguments: String) async throws -> [String: Any] {
        let result = try await GenUIReferenceTool().execute(call: ToolCall(
            id: "reference", name: GenUIReferenceTool.name, argumentsJSON: arguments
        ))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(result.content.utf8)) as? [String: Any])
    }

    func testGuidePreservesRuntimeContractsWithoutDumpingTheCatalog() async throws {
        let object = try await lookup(#"{"componentName":"@guide"}"#)
        let guide = try XCTUnwrap(object["guide"] as? String)
        for hook in ["useState", "useEffect", "useMemo"] {
            XCTAssertTrue(guide.contains(hook), hook)
        }
        XCTAssertTrue(guide.contains("4px/unit"))
        XCTAssertTrue(guide.contains("$-props:CEL"))
        XCTAssertTrue(guide.contains("Never invent data") || guide.contains("Never fabricate live data"))
        XCTAssertFalse(guide.contains(GenUIDocument.componentGuide))
    }

    func testSearchFindsPrimitivesAliasesAndTemplatesWithoutTheirSource() async throws {
        for (query, expected) in [("  SLIDER  ", "slider"), ("map", "MapWidgetV2"), ("currency", "CurrencyConverterWidget")] {
            let arguments = String(decoding: try JSONEncoder().encode(["componentName": "*", "query": query]), as: UTF8.self)
            let object = try await lookup(arguments)
            XCTAssertTrue((object["componentNames"] as? [String] ?? []).contains(expected))
            XCTAssertNil(object["source"])
        }
        let empty = try await lookup(#"{"componentName":"*","query":"no-such-component"}"#)
        XCTAssertEqual(empty["componentNames"] as? [String], [])
        XCTAssertEqual(empty["totalMatches"] as? Int, 0)
        XCTAssertTrue(empty["nextOffset"] is NSNull)
    }

    func testSearchPagesReachTheEntireCatalogInStableOrder() async throws {
        var offset = 0
        var restored: [String] = []
        while true {
            let object = try await lookup("{\"componentName\":\"*\",\"offset\":\(offset)}")
            let names = try XCTUnwrap(object["componentNames"] as? [String])
            XCTAssertLessThanOrEqual(names.count, 32)
            XCTAssertEqual(object["totalMatches"] as? Int, GenUIDocument.componentCatalog.count)
            restored += names
            guard let next = object["nextOffset"] as? Int else { break }
            XCTAssertGreaterThan(next, offset)
            offset = next
        }
        XCTAssertEqual(restored, GenUIDocument.componentCatalog.keys.sorted())
    }

    func testEveryPrimitiveAndAliasHasItsActualPropertyContract() async throws {
        for name in GenUIDocument.componentCatalog.keys.sorted() where GenUIReferenceCatalog.components[name] == nil {
            let arguments = String(decoding: try JSONEncoder().encode(["componentName": name]), as: UTF8.self)
            let object = try await lookup(arguments)
            XCTAssertEqual(object["properties"] as? [String], GenUIDocument.componentCatalog[name], name)
            XCTAssertEqual(object["canonicalName"] as? String, GenUIDocument.widgetAliases[name] ?? name)
            XCTAssertNil(object["source"])
        }
    }

    func testInvalidSearchPagesFailInsteadOfExpandingContext() async {
        let registry = LocalToolRegistry(executors: [GenUIReferenceTool()])
        for page in [#""offset":-1"#, #""offset":9223372036854775807"#, #""maxResults":0"#, #""maxResults":65"#] {
            let result = await registry.execute(call: ToolCall(
                id: "invalid", name: GenUIReferenceTool.name,
                argumentsJSON: "{\"componentName\":\"*\",\(page)}"
            ))
            XCTAssertTrue(result.isError)
            XCTAssertTrue(result.content.contains("invalid component search page"))
        }
    }

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
