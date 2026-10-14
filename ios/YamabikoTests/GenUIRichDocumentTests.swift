import XCTest
import WebKit
@testable import YamabikoChat

final class GenUIRichDocumentTests: XCTestCase {
    @MainActor
    func testScopedDarkThemeUsesTheRecoveredForegroundPalette() async throws {
        let document = GenUIDocument(title: "Theme", ui: GenUINode(type: "card", props: ["theme": .string("dark")], children: [.node(GenUINode(type: "title", children: [.string("Read")]))]))
        let html = try XCTUnwrap(GenUIRichWebView.Coordinator.html(document: document, snapshot: nil, dark: false))
        let rendered = expectation(description: "Dark render")
        let recorder = GenUIRenderRecorder(expectation: rendered)
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(recorder, name: "genui")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 300), configuration: configuration)
        defer { configuration.userContentController.removeScriptMessageHandler(forName: "genui") }
        webView.loadHTMLString(html, baseURL: nil)
        await fulfillment(of: [rendered], timeout: 15)
        let color = try await webView.callAsyncJavaScript("return getComputedStyle(document.querySelector('.genui-title')).color", arguments: [:], in: nil, contentWorld: .page) as? String
        XCTAssertEqual(color, "rgb(255, 255, 255)")
    }

    @MainActor
    func testWebKitPreservesInputIdentityAndUpdatesCallbacks() async throws {
        let document = GenUIDocument(title: "Stable controls", code: #"""
        const [n,setN] = DIL.useState(0);
        return DIL.h('col', {}, DIL.h('input', {inputType:'number',value:n,onChange:value=>setN(Number(value)||0)}),
          DIL.h('text', {}, 'Result '+n), DIL.h('button', {label:'Reset',onClick:()=>setN(0)}));
        """#)
        let html = try XCTUnwrap(GenUIRichWebView.Coordinator.html(document: document, snapshot: nil, dark: false))
        let rendered = expectation(description: "Initial render")
        let recorder = GenUIRenderRecorder(expectation: rendered)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.add(recorder, name: "genui")
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 600), configuration: configuration)
        defer { configuration.userContentController.removeScriptMessageHandler(forName: "genui") }
        webView.loadHTMLString(html, baseURL: nil)
        await fulfillment(of: [rendered], timeout: 15)
        let result = try await webView.callAsyncJavaScript("""
        const input=document.querySelector('input'); input.focus(); input.value='12';
        input.dispatchEvent(new Event('input',{bubbles:true}));
        await new Promise(resolve=>setTimeout(resolve,0));
        const same=input===document.querySelector('input'), focused=document.activeElement===input;
        const edited=document.querySelector('.genui-text').textContent;
        input.value=''; input.dispatchEvent(new Event('input',{bubbles:true}));
        await new Promise(resolve=>setTimeout(resolve,0)); const draft=input.value;
        input.value='12'; input.dispatchEvent(new Event('input',{bubbles:true}));
        await new Promise(resolve=>setTimeout(resolve,0));
        document.querySelector('button').click();
        await new Promise(resolve=>setTimeout(resolve,0));
        return {same,focused,edited,draft,reset:document.querySelector('.genui-text').textContent};
        """, arguments: [:], in: nil, contentWorld: .page) as? [String: Any]
        XCTAssertEqual(result?["same"] as? Bool, true)
        XCTAssertEqual(result?["focused"] as? Bool, true)
        XCTAssertEqual(result?["edited"] as? String, "Result 12")
        XCTAssertEqual(result?["draft"] as? String, "")
        XCTAssertEqual(result?["reset"] as? String, "Result 0")
        XCTAssertNil(recorder.error)
    }

    func testOriginalComponentCatalogAndFixtureValidate() throws {
        XCTAssertEqual(GenUIReferenceCatalog.components.count, 283)
        XCTAssertEqual(try validated(GenUIOriginalFixture.document), GenUIOriginalFixture.document)
        let document = try GenUIDocument.validated(from: #"{"title":"Timer","ui":{"type":"DigitalTimerWidget","props":{"__state":{"start_time":90,"auto_start":false,"done_label":"Done"}}}}"#)
        XCTAssertEqual(document.ui?.type, "DigitalTimerWidget")
    }

    func testReferenceCompositionValidatesAndRoundTrips() throws {
        XCTAssertEqual(try validated(GenUIReferenceFixture.document), GenUIReferenceFixture.document)
        let data = try JSONEncoder().encode(GenUIReferenceFixture.document)
        XCTAssertEqual(try JSONDecoder().decode(GenUIDocument.self, from: data), GenUIReferenceFixture.document)
    }

    func testReferenceElementsAndWidgetNamesValidate() throws {
        let document = try GenUIDocument.validated(from: #"""
        {"title":"Reference","state":{"ready":true},"ui":{"type":"Col","children":[
            {"type":"Scope","props":{"values":{"heading":"Heading"}},"children":[{"type":"title","children":["{{heading}}"]}]},
            {"type":"Each","props":{"items":[{"id":"a","name":"A"}],"as":"entry","keyField":"id"},"children":[{"type":"text","children":["{{entry.name}}"]}]},
            {"type":"Show","props":{"when":"{{ready}}"},"children":[{"type":"markdown","children":["**Ready**"]},{"type":"Show.Else","children":["Waiting"]}]},
            {"type":"flashcard-flip","props":{"front":{"type":"text","children":["Question"]},"back":{"type":"text","children":["Answer"]}}},
            {"type":"LoadingBlock","props":{"lines":3}},
            {"type":"animate-group","props":{"stagger":60},"children":[{"type":"animate-item","props":{"name":"slide"},"children":[{"type":"Badge","props":{"label":"New"}}]}]}
        ]}}
        """#)
        XCTAssertEqual(document.ui?.children?.count, 6)
        for (alias, type) in GenUIDocument.widgetAliases {
            XCTAssertEqual(GenUIDocument.componentCatalog[alias], GenUIDocument.componentCatalog[type], alias)
        }
    }

    func testEmbeddedReferenceNodesAndUnsafeStateKeysAreRejected() {
        for ui in [
            #"{"type":"flashcard-flip","props":{"front":{"type":"script"}}}"#,
            #"{"type":"component","props":{"content":[{"type":"Link","props":{"url":"javascript:alert(1)"}}]}}"#,
            #"{"type":"input","props":{"bind":"__proto__"}}"#,
            #"{"type":"button","props":{"onClick":{"type":"setState","key":"constructor","value":1}}}"#
        ] {
            XCTAssertThrowsError(try GenUIDocument.validated(from: "{\"title\":\"Invalid\",\"ui\":\(ui)}"))
        }
    }

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
        let node = try XCTUnwrap(properties["ui"] as? [String: Any])
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

    func testToolSchemaDefersNamesWhileTheValidatorKeepsTheCompleteCatalog() throws {
        let data = Data(GenUITool.definition.parametersJSON.utf8)
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let node = try XCTUnwrap(properties["ui"] as? [String: Any])
        let props = try XCTUnwrap(node["properties"] as? [String: Any])
        let type = try XCTUnwrap(props["type"] as? [String: Any])
        XCTAssertEqual(type["type"] as? String, "string")
        XCTAssertNil(type["enum"])
        XCTAssertNil(schema["$defs"])
        for name in GenUIReferenceCatalog.components.keys {
            XCTAssertNotNil(GenUIDocument.componentCatalog[name], name)
        }
        XCTAssertThrowsError(try GenUIDocument.validated(from: #"{"title":"Invalid child","ui":{"type":"col","children":[{"type":"MissingWidget"}]}}"#))
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
