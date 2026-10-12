import XCTest
import WebKit
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

    func testTreesBeyondPreviousDepthAndNodeLimits() throws {
        var node = GenUINode(type: "text", children: [.string("leaf")])
        for _ in 0..<64 { node = GenUINode(type: "col", children: [.node(node)]) }
        for document in [
            GenUIDocument(title: "Deep", ui: node),
            GenUIDocument(title: "Wide", ui: GenUINode(type: "col", children: Array(repeating: .node(GenUINode(type: "text")), count: 1024))),
            GenUIDocument(title: "AppBlock", ui: GenUINode(type: "AppBlock", props: ["content": try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(node))]))
        ] {
            XCTAssertEqual(try validated(document), document)
        }
    }

    func testDeepAndWideTreesStillRejectInvalidDescendants() throws {
        for leaf in [
            GenUINode(type: "script"),
            GenUINode(type: "text", props: ["innerHTML": .string("unsafe")]),
            GenUINode(type: "Link", props: ["url": .string("javascript:alert(1)")]),
            GenUINode(type: "path", props: ["d": .string("M0 0L1 1")])
        ] {
            var node = leaf
            for _ in 0..<64 { node = GenUINode(type: "col", children: [.node(node)]) }
            let children = Array(repeating: GenUIChild.node(GenUINode(type: "text")), count: 1024) + [.node(node)]
            XCTAssertThrowsError(try validated(GenUIDocument(title: "Invalid", ui: GenUINode(type: "col", children: children))))
        }
    }

    @MainActor
    func testWebKitExecutesLargeCodeAndPreservesLargeHookState() async throws {
        let text = String(repeating: "資料", count: 100_000)
        let code = """
        const [value] = DIL.useState(resources.source.text);
        const [principal, setPrincipal] = DIL.useState(300000);
        const monthly = DIL.useMemo(() => {
            const rate = 5 / 1200;
            return principal * rate / (1 - (1 + rate) ** -360);
        }, [principal]);
        return DIL.h('col', {},
            DIL.h('text', {}, String(Math.round(monthly))),
            DIL.h('button', {label:'Double', onClick:() => setPrincipal(p => p * 2)}));
        """ + String(repeating: " ", count: 65_537)
        let document = try validated(GenUIDocument(title: "WebKit", code: code, resources: ["source": GenUIResource(text: text)]))
        let html = try XCTUnwrap(GenUIRichWebView.Coordinator.html(document: document, snapshot: nil, dark: false))
        let rendered = expectation(description: "GenUI rendered in WebKit")
        let recorder = GenUIRenderRecorder(expectation: rendered)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(recorder, name: "genui")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 800), configuration: configuration)
        defer { configuration.userContentController.removeScriptMessageHandler(forName: "genui") }
        webView.loadHTMLString(html, baseURL: nil)
        await fulfillment(of: [rendered], timeout: 15)
        XCTAssertNil(recorder.error)
        let snapshot = try XCTUnwrap(recorder.snapshot)
        XCTAssertEqual(snapshot["hooks"], .array([.string(text), .number(300000)]))
        let result = try await webView.evaluateJavaScript("document.querySelector('.genui-text').textContent")
        XCTAssertEqual(result as? String, "1610")
        let updated = expectation(description: "GenUI recalculated locally")
        recorder.expectation = updated
        _ = try await webView.evaluateJavaScript("document.querySelector('button').click()")
        await fulfillment(of: [updated], timeout: 15)
        let doubled = try await webView.evaluateJavaScript("document.querySelector('.genui-text').textContent")
        XCTAssertEqual(doubled as? String, "3221")
        XCTAssertEqual(recorder.snapshot?["hooks"], .array([.string(text), .number(600000)]))
    }

    func testCodeAndDocumentsBeyondPreviousByteLimits() throws {
        let code = "return DIL.h('text', {}, '計算');" + String(repeating: " ", count: 65_537)
        let document = GenUIDocument(title: String(repeating: "題", count: 4097), subtitle: String(repeating: "説明", count: 4097), code: code,
                                     resources: ["source": GenUIResource(text: String(repeating: "資料", count: 50_000))])
        XCTAssertGreaterThan(try JSONEncoder().encode(document).count, 262_144)
        XCTAssertEqual(try validated(document), document)
        XCTAssertThrowsError(try validated(GenUIDocument(title: "Invalid", code: code + "return (")))
    }

    func testInitialDataBeyondPreviousCollectionAndNestingLimits() throws {
        var nested = JSONValue.number(1)
        for _ in 0..<64 { nested = .array([nested]) }
        var state = Dictionary(uniqueKeysWithValues: (0..<129).map { ("key\($0)", JSONValue.number(Double($0))) })
        state["nested"] = nested
        state["points"] = .array(Array(repeating: .number(1), count: 1024))
        state["object"] = .object(Dictionary(uniqueKeysWithValues: (0..<129).map { ("key\($0)", JSONValue.number(1)) }))
        let resources = Dictionary(uniqueKeysWithValues: (0..<65).map { ("ref\($0)", GenUIResource(text: "source")) })
        let document = GenUIDocument(title: "Data", ui: GenUINode(type: "Chart", props: ["content": .object(["data": state["points"]!])]), state: state, resources: resources)
        XCTAssertEqual(try validated(document), document)
    }

    func testRichSchemaDoesNotAdvertiseFixedSizeLimits() throws {
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(GenUITool.definition.parametersJSON.utf8)) as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        for key in ["title", "code", "state", "resources"] {
            let property = try XCTUnwrap(properties[key] as? [String: Any])
            XCTAssertNil(property["maxLength"], key)
            XCTAssertNil(property["maxProperties"], key)
        }
        let definitions = try XCTUnwrap(schema["$defs"] as? [String: Any])
        let node = try XCTUnwrap(definitions["node"] as? [String: Any])
        let nodeProperties = try XCTUnwrap(node["properties"] as? [String: Any])
        XCTAssertNil((nodeProperties["children"] as? [String: Any])?["maxItems"])
        XCTAssertFalse(GenUITool.definition.description.contains("Maximum 256 KiB"))
        XCTAssertTrue(GenUITool.definition.description.contains("Math.pow"))
    }

    private func validated(_ document: GenUIDocument) throws -> GenUIDocument {
        try GenUIDocument.validated(from: String(decoding: JSONEncoder().encode(document), as: UTF8.self))
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

@MainActor
private final class GenUIRenderRecorder: NSObject, WKScriptMessageHandler {
    var expectation: XCTestExpectation?
    var snapshot: [String: JSONValue]?
    var error: String?

    init(expectation: XCTestExpectation) { self.expectation = expectation }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any] else { return }
        switch body["type"] as? String {
        case "state": snapshot = body["state"].flatMap(GenUIHostPolicy.snapshot)
        case "error": error = body["message"] as? String
        default: return
        }
        expectation?.fulfill()
        expectation = nil
    }
}
