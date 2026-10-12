import XCTest
@testable import YamabikoChat

final class GenUIRichDocumentTests: XCTestCase {
    func testRichRoundTripAndDefaults() throws {
        let document = try GenUIDocument.validated(from: #"{"title":"Rich","ui":{"type":"col","children":["hello",2,{"type":"text","props":{"color":null},"children":["world"]}]},"state":{"empty":null}}"#)
        XCTAssertTrue(document.components.isEmpty)
        XCTAssertTrue(document.inputs.isEmpty)
        XCTAssertEqual(document.ui?.children?.count, 3)
        XCTAssertEqual(document.state?["empty"], .null)
        let data = try JSONEncoder().encode(document)
        XCTAssertEqual(try JSONDecoder().decode(GenUIDocument.self, from: data), document)
    }

    func testCodeDocumentAndExplicitResource() throws {
        let document = try GenUIDocument.validated(from: #"{"title":"Counter","code":"const [n,setN]=DIL.useState(0); return DIL.h('text',{},String(n));","resources":{"source":{"title":"Source","url":"https://example.com"}}}"#)
        XCTAssertNotNil(document.code)
        XCTAssertNil(document.ui)
        XCTAssertEqual(document.resources?["source"]?.url, "https://example.com")
    }

    func testUnsupportedTypesPropertiesURLsAndActionsFail() {
        for ui in [
            #"{"type":"script"}"#,
            #"{"type":"text","props":{"innerHTML":"<script>"}}"#,
            #"{"type":"Link","props":{"url":"javascript:alert(1)"}}"#,
            #"{"type":"AsyncImage","props":{"src":"data:image/svg+xml,abc"}}"#,
            #"{"type":"button","props":{"onClick":{"type":"runModel"}}}"#,
            #"{"type":"button","props":{"onClick":{"type":"openUrl","url":"file:///tmp/a"}}}"#
        ] {
            XCTAssertThrowsError(try GenUIDocument.validated(from: "{\"title\":\"Invalid\",\"ui\":\(ui)}"))
        }
        XCTAssertThrowsError(try GenUIDocument.validated(from: #"{"title":"Invalid","ui":{"type":"text"},"resources":{"bad":{"src":"http://example.com"}}}"#))
    }

    func testRendererModesAreExclusive() {
        XCTAssertThrowsError(try GenUIDocument.validated(from: #"{"title":"Invalid","ui":{"type":"text"},"code":"return null"}"#))
        XCTAssertThrowsError(try GenUIDocument.validated(from: #"{"title":"Invalid","ui":{"type":"text"},"components":[{"id":"a","kind":"text","text":"text"}]}"#))
        XCTAssertThrowsError(try GenUIDocument.validated(from: #"{"title":"Invalid"}"#))
    }

    func testBoundedDepthAndCount() throws {
        var node = GenUINode(type: "text", children: [.string("leaf")])
        for _ in 0..<32 { node = GenUINode(type: "col", children: [.node(node)]) }
        let deep = GenUIDocument(title: "Deep", ui: node)
        XCTAssertThrowsError(try GenUIDocument.validated(from: String(decoding: JSONEncoder().encode(deep), as: UTF8.self)))
        let wide = GenUIDocument(title: "Wide", ui: GenUINode(type: "col", children: Array(repeating: .node(GenUINode(type: "text")), count: 512)))
        XCTAssertThrowsError(try GenUIDocument.validated(from: String(decoding: JSONEncoder().encode(wide), as: UTF8.self)))
        let largeCode = GenUIDocument(title: "Large", code: String(repeating: "x", count: 65_537))
        XCTAssertThrowsError(try GenUIDocument.validated(from: String(decoding: JSONEncoder().encode(largeCode), as: UTF8.self)))
    }

    func testBindingAndHostAction() throws {
        _ = try GenUIDocument.validated(from: #"{"title":"State","state":{"name":""},"ui":{"type":"input","props":{"bind":"name","value":"{{name}}","onChange":{"type":"setState","key":"name","value":"$value"}}}}"#)
        _ = try GenUIDocument.validated(from: #"{"title":"Host","ui":{"type":"button","props":{"onClick":{"type":"issueNewTurn","query":"Explain this"}},"children":["Explain"]}}"#)
    }

    func testLegacyDocumentRemainsValid() throws {
        let document = try GenUIDocument.validated(from: #"{"title":"Legacy","components":[{"id":"text","kind":"text","text":"Hello"}]}"#)
        XCTAssertEqual(document.components.count, 1)
        XCTAssertNil(document.ui)
        XCTAssertNil(document.code)
    }

    func testSVGPrimitivesAndLocalReferences() throws {
        _ = try GenUIDocument.validated(from: #"{"title":"SVG","ui":{"type":"svg","props":{"viewBox":"0 0 100 100"},"children":[{"type":"defs","children":[{"type":"linearGradient","props":{"id":"paint"},"children":[{"type":"stop","props":{"offset":"0%","stopColor":"red"}}]}]},{"type":"g","children":[{"type":"circle","props":{"cx":50,"cy":50,"r":20,"fill":"url(#paint)"}},{"type":"text","props":{"x":10,"y":10},"children":["SVG label"]}]}]}}"#)
        for node in [#"{"type":"path","props":{"d":"M0 0L1 1"}}"#, #"{"type":"svg","children":[{"type":"script"}]}"#, #"{"type":"svg","children":[{"type":"rect","props":{"href":"https://example.com"}}]}"#, #"{"type":"svg","children":[{"type":"circle","props":{"fill":"url(https://example.com)"}}]}"#] {
            XCTAssertThrowsError(try GenUIDocument.validated(from: "{\"title\":\"Bad SVG\",\"ui\":\(node)}"))
        }
    }

    func testInlineAppBlockNodesAreValidated() throws {
        for key in ["content", "entrypoint"] {
            _ = try GenUIDocument.validated(from: "{\"title\":\"Inline\",\"ui\":{\"type\":\"AppBlock\",\"props\":{\"\(key)\":{\"type\":\"text\",\"children\":[\"Inline node\"]}}}}")
            XCTAssertThrowsError(try GenUIDocument.validated(from: "{\"title\":\"Inline\",\"ui\":{\"type\":\"AppBlock\",\"props\":{\"\(key)\":{\"type\":\"script\"}}}}"))
        }
    }

    func testRichEncodingContainsOnlyItsRendererMode() throws {
        let document = GenUIDocument(title: "Rich", ui: GenUINode(type: "text"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(document)) as? [String: Any])
        XCTAssertNotNil(json["ui"])
        XCTAssertNil(json["components"])
        XCTAssertNil(json["inputs"])
        XCTAssertNil(json["code"])
    }

    func testToolSchemaContainsEveryComponent() throws {
        let data = Data(GenUITool.definition.parametersJSON.utf8)
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let definitions = try XCTUnwrap(schema["$defs"] as? [String: Any])
        let node = try XCTUnwrap(definitions["node"] as? [String: Any])
        let props = try XCTUnwrap(node["properties"] as? [String: Any])
        let type = try XCTUnwrap(props["type"] as? [String: Any])
        XCTAssertEqual(Set(try XCTUnwrap(type["enum"] as? [String])), Set(GenUIDocument.componentCatalog.keys))
    }
}
