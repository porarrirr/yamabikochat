import XCTest
@testable import YamabikoChat

final class GenUIToolTests: XCTestCase {
    func testNativeEnvelopeRequiresOnlyOneStringAndPreservesNestedDocumentValues() throws {
        for arguments in [#"{"document":null}"#, #"{"document":true}"#, #"{"document":12}"#,
                          #"{"document":{}}"#, #"{"document":[]}"#,
                          #"{"document":"{}","extra":null}"#] {
            XCTAssertThrowsError(try GenUITool.document(from: arguments))
            XCTAssertThrowsError(try GenUITool.previewDocument(from: arguments))
        }
        let json = #"{"title":"日本語","code":"return state;","state":{"text":"1","number":1,"bool":true,"empty":null,"nested":[{"value":"👨‍👩‍👧‍👦"}]}}"#
        let envelope = String(decoding: try JSONEncoder().encode(["document": json]), as: UTF8.self)
        let direct = try GenUITool.document(from: json)
        XCTAssertEqual(try GenUITool.document(from: envelope), direct)
        XCTAssertEqual(try GenUITool.previewDocument(from: envelope), direct)
        XCTAssertEqual(try GenUITool.previewDocument(from: json), direct)
        XCTAssertEqual(direct.state?["text"], .string("1"))
        XCTAssertEqual(direct.state?["number"], .number(1))
        XCTAssertEqual(direct.state?["bool"], .bool(true))
        XCTAssertEqual(direct.state?["empty"], .null)
    }

    func testCodePreviewStillEnforcesCompleteDocumentValidation() throws {
        for arguments in [
            #"{"title":" ","code":"return 60;"}"#,
            #"{"title":"Demo","code":"return 60;","ui":{"type":"text"}}"#,
            #"{"title":"Demo","code":"return 60;","resources":{"bad":{"url":"http://example.com"}}}"#,
            #"{"title":"Demo","code":"return ("}"#
        ] {
            XCTAssertThrowsError(try GenUITool.document(from: arguments))
            XCTAssertThrowsError(try GenUITool.previewDocument(from: arguments))
        }
    }

    func testCodeValidationOnlyCompilesAndDoesNotLeakExceptionsOrGlobals() throws {
        // Executing either body would hang or poison the next validation.
        try GenUICodeValidator.validate("while (true) {}")
        try GenUICodeValidator.validate("globalThis.Function = null; throw new Error('must not run');")
        try GenUICodeValidator.validate("return DIL.h('text', {}, '\"日本語\\n👨‍👩‍👧‍👦');")
        for _ in 0..<10 {
            XCTAssertThrowsError(try GenUICodeValidator.validate("return DIL.h("))
            XCTAssertNoThrow(try GenUICodeValidator.validate("return 60;"))
        }
        // Source containing script delimiters must remain a function body value.
        XCTAssertThrowsError(try GenUICodeValidator.validate("}); globalThis.Function = null; //"))
        XCTAssertNoThrow(try GenUICodeValidator.validate("return state;"))
    }

    func testConcurrentCodeValidationKeepsEachCallsExceptionIsolated() async {
        let failures = await withTaskGroup(of: Bool.self, returning: [Bool].self) { group in
            for index in 0..<100 {
                group.addTask {
                    do {
                        try GenUICodeValidator.validate(index.isMultiple(of: 2) ? "return \(index);" : "return (")
                        return !index.isMultiple(of: 2)
                    } catch {
                        return index.isMultiple(of: 2)
                    }
                }
            }
            var failures: [Bool] = []
            for await failed in group { failures.append(failed) }
            return failures
        }
        XCTAssertFalse(failures.contains(true))
    }

    func testDefinitionKeepsCoreGuidanceAndDefersTheCatalogWhileValidatingUnknownNodes() throws {
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(GenUITool.definition.parametersJSON.utf8)) as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let ui = try XCTUnwrap(properties["ui"] as? [String: Any])
        XCTAssertEqual(ui["type"] as? String, "object")
        XCTAssertEqual(ui["required"] as? [String], ["type"])
        XCTAssertFalse(GenUITool.definition.description.contains(GenUIDocument.componentGuide))
        XCTAssertFalse(GenUITool.definition.parametersJSON.contains("CurrencyConverterWidget"))
        XCTAssertTrue(GenUITool.definition.description.contains("genui_reference"))
        // Protect on-demand catalog disclosure directly. An arbitrary byte budget
        // would reject useful guidance and is not a provider token/context limit.
        XCTAssertFalse(GenUITool.definition.parametersJSON.contains(GenUIDocument.componentGuide))
        XCTAssertFalse(GenUITool.definition.description.contains("CurrencyConverterWidget"))
        XCTAssertTrue(GenUITool.definition.description.contains(GenUIDocument.coreComponentGuide))
        XCTAssertTrue(GenUITool.definition.description.contains(GenUITool.usageGuide))
        XCTAssertThrowsError(try GenUIDocument.validated(from: #"{"title":"Invalid","ui":{"type":"MissingWidget"}}"#))
    }

    func testAdvertisedInteractiveDiagramPassesToolValidation() async throws {
        for code in [GenUITool.interactiveDiagramExample, GenUITool.powersExample, GenUITool.worktreeDiagramExample] {
            let document = GenUIDocument(title: "Diagram", code: code)
            let arguments = String(decoding: try JSONEncoder().encode(document), as: UTF8.self)
            let result = try await GenUITool().execute(call: ToolCall(id: "diagram", name: "genui", argumentsJSON: arguments))
            XCTAssertFalse(result.isError)
            XCTAssertEqual(try GenUIDocument.validated(from: result.content), document)
        }
    }

    func testLegacySchemaAdvertisesKindSpecificRequiredFields() throws {
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(GenUITool.definition.parametersJSON.utf8)) as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        for (arrayName, expected) in [
            ("inputs", ["slider": ["min", "max"], "select": ["options"]]),
            ("components", ["text": ["text"], "metric": ["value"], "table": ["columns"], "chart": ["series"], "cards": ["items"]])
        ] {
            let array = try XCTUnwrap(properties[arrayName] as? [String: Any])
            let item = try XCTUnwrap(array["items"] as? [String: Any])
            let variants = try XCTUnwrap(item["oneOf"] as? [[String: Any]])
            for (kind, required) in expected {
                let variant = try XCTUnwrap(variants.first { variant in
                    let props = variant["properties"] as? [String: Any]
                    let kindSchema = props?["kind"] as? [String: Any]
                    return (kindSchema?["enum"] as? [String]) == [kind]
                })
                XCTAssertEqual(variant["required"] as? [String], required, kind)
            }
        }
    }

    func testLegacyKindContractsAcceptCompleteInputsAndRejectMissingFields() throws {
        let components = [
            #"{"id":"t","kind":"text","text":"Meaning"}"#,
            #"{"id":"m","kind":"metric","value":"8"}"#,
            #"{"id":"table","kind":"table","columns":["Example"]}"#,
            #"{"id":"chart","kind":"chart","series":[{"name":"Examples","points":[{"label":"2³","value":"8"}]}]}"#,
            #"{"id":"cards","kind":"cards","items":[{"title":"Example","value":"8"}]}"#
        ]
        for component in components {
            XCTAssertNoThrow(try GenUIDocument.validated(from: "{\"title\":\"Contract\",\"components\":[\(component)]}"))
        }
        for kind in ["text", "metric", "table", "chart", "cards"] {
            XCTAssertThrowsError(try GenUIDocument.validated(from: "{\"title\":\"Invalid\",\"components\":[{\"id\":\"missing\",\"kind\":\"\(kind)\"}]}"))
        }
        for input in [
            #"{"id":"x","label":"X","kind":"slider","min":1,"max":10,"value":2}"#,
            #"{"id":"x","label":"X","kind":"select","value":2,"options":[{"label":"Two","value":2}]}"#
        ] {
            XCTAssertNoThrow(try GenUIDocument.validated(from: "{\"title\":\"Input\",\"inputs\":[\(input)],\"components\":[\(components[0])]}"))
        }
        for input in [
            #"{"id":"x","label":"X","kind":"slider"}"#,
            #"{"id":"x","label":"X","kind":"select"}"#,
            #"{"id":"x","label":"X","kind":"select","value":1,"options":[{"label":"Two","value":2}]}"#
        ] {
            XCTAssertThrowsError(try GenUIDocument.validated(from: "{\"title\":\"Input\",\"inputs\":[\(input)],\"components\":[\(components[0])]}"))
        }
    }

    func testReferenceRetrievalPreservesToolPrefixAcrossScopesAndConversations() async throws {
        let registry = LocalToolRegistry(executors: [GenUIReferenceTool(), GenUITool()])
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let prefix = try encoder.encode(registry.definitions.map(\.providerTool))
        for arguments in [#"{"componentName":"@guide"}"#, #"{"componentName":"*","query":"chart"}"#,
                          #"{"componentName":"Slider"}"#, #"{"componentName":"DigitalTimerWidget","maxCharacters":100}"#] {
            let scoped = registry.scopedForExecution()
            let result = await scoped.execute(call: ToolCall(id: "read", name: GenUIReferenceTool.name, argumentsJSON: arguments))
            XCTAssertFalse(result.isError)
            XCTAssertEqual(try encoder.encode(scoped.definitions.map(\.providerTool)), prefix)
            XCTAssertEqual(try encoder.encode(registry.definitions.map(\.providerTool)), prefix)
        }
        let reordered = LocalToolRegistry(executors: [GenUITool(), GenUIReferenceTool()])
        XCTAssertEqual(try encoder.encode(reordered.definitions.map(\.providerTool)), prefix)
    }

    func testNativeJSONEnvelopeUsesTheSameExecutorAndValidation() async throws {
        let registry = LocalToolRegistry(executors: [GenUITool()])
        let arguments = String(decoding: try JSONEncoder().encode(["document": minimal]), as: UTF8.self)
        let result = await registry.execute(call: ToolCall(id: "native", name: GenUITool.name, argumentsJSON: arguments))
        XCTAssertFalse(result.isError)
        XCTAssertEqual(try GenUIDocument.validated(from: result.content).title, "Demo")
        let invalid = await registry.execute(call: ToolCall(id: "invalid", name: GenUITool.name, argumentsJSON: #"{"document":"{}","title":"Extra"}"#))
        XCTAssertTrue(invalid.isError)
    }

    func testLargeDocumentsUseDirectAndNativeEnvelopePaths() async throws {
        let document = GenUIDocument(title: "Large", code: "return DIL.h('text', {}, resources.source.text);",
                                     resources: ["source": GenUIResource(text: String(repeating: "資料", count: 100_000))])
        let json = String(decoding: try JSONEncoder().encode(document), as: UTF8.self)
        let envelope = String(decoding: try JSONEncoder().encode(["document": json]), as: UTF8.self)
        for arguments in [json, envelope] {
            XCTAssertGreaterThan(arguments.utf8.count, 524_288)
            let result = try await GenUITool().execute(call: ToolCall(id: "large", name: GenUITool.name, argumentsJSON: arguments))
            XCTAssertEqual(try GenUIDocument.validated(from: result.content), document)
        }
    }

    private let minimal = #"{"title":"Demo","components":[{"id":"text","kind":"text","text":"Hello"}]}"#

    func testChartTypeSchemaIsExplicit() throws {
        let schema = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(GenUITool.definition.parametersJSON.utf8)) as? [String: Any])
        let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
        let components = try XCTUnwrap(properties["components"] as? [String: Any])
        let items = try XCTUnwrap(components["items"] as? [String: Any])
        let fields = try XCTUnwrap(items["properties"] as? [String: Any])
        let chartType = try XCTUnwrap(fields["chartType"] as? [String: Any])
        XCTAssertEqual(chartType["enum"] as? [String], ["line", "pie"])
        XCTAssertTrue(GenUITool.definition.description.contains("Do not infer chart type from IDs/titles"))
    }

    func testExplicitPieChartAndLegacyLineDefault() async throws {
        // Regression: coin_pie in the diagnostics had no chartType and was a line chart.
        let legacy = #"{"title":"Coins","components":[{"id":"coin_pie","kind":"chart","series":[{"name":"割合","points":[{"label":"1円","value":"8"},{"label":"100円","value":"40"}]}]}]}"#
        XCTAssertEqual(try GenUIDocument.validated(from: legacy).components[0].resolvedChartType, "line")
        let pie = legacy.replacingOccurrences(of: "\"kind\":\"chart\"", with: "\"kind\":\"chart\",\"chartType\":\"pie\"")
        let result = try await GenUITool().execute(call: ToolCall(id: "pie", name: "genui", argumentsJSON: pie))
        let document = try GenUIDocument.validated(from: result.content)
        XCTAssertEqual(document.components[0].chartType, "pie")
        XCTAssertEqual(document.components[0].pieValues(values: [:]), [8, 40])
        XCTAssertEqual(try JSONDecoder().decode(GenUIDocument.self, from: JSONEncoder().encode(document)), document)
    }

    func testPieRejectsInvalidValuesAndSeries() throws {
        func chart(_ series: String, type: String = "pie") -> String {
            "{\"title\":\"Pie\",\"components\":[{\"id\":\"pie\",\"kind\":\"chart\",\"chartType\":\"\(type)\",\"series\":\(series)}]}"
        }
        func series(_ value: String) -> String {
            "{\"name\":\"Share\",\"points\":[{\"label\":\"A\",\"value\":\"\(value)\"}]}"
        }
        for value in ["-1", "0", "=1/0", "nan"] {
            XCTAssertThrowsError(try GenUIDocument.validated(from: chart("[\(series(value))]")))
        }
        XCTAssertThrowsError(try GenUIDocument.validated(from: chart("[\(series("1")),\(series("2"))]")))
        XCTAssertThrowsError(try GenUIDocument.validated(from: chart("[\(series("1"))]", type: "unknown")))
        let document = try GenUIDocument.validated(from: chart("[\(series("=2*3"))]"))
        XCTAssertEqual(document.components[0].pieValues(values: [:]), [6])
        var dynamic = document.components[0]
        dynamic.series?[0].points[0].value = "=x"
        XCTAssertNil(dynamic.pieValues(values: ["x": -1]))
        XCTAssertNil(dynamic.pieValues(values: ["x": 0]))
        XCTAssertEqual(dynamic.pieValues(values: ["x": 10]), [10])
    }

    func testPaymentAndArithmetic() throws {
        XCTAssertEqual(try GenUIExpression.evaluate("=payment(principal,rate,years)", values: ["principal":12000,"rate":0,"years":1]), 1000)
        XCTAssertEqual(try GenUIExpression.evaluate("payment(12000,1e-20,1)", values: [:]), 1000, accuracy: 0.00001)
        XCTAssertEqual(try GenUIExpression.evaluate("payment(300000,5,30)", values: [:]), 1610.464869, accuracy: 0.00001)
        XCTAssertEqual(try GenUIExpression.evaluate("-2^2 + max(3,round(4.6))", values: [:]), 1)
        XCTAssertEqual(try GenUIExpression.evaluate("pow(x,2)+abs(-3)", values: ["x":4]), 19)
    }

    func testDynamicFormulasAndInterpolation() throws {
        let document = try GenUIDocument.validated(from: #"{"title":"Demo","inputs":[{"id":"x","label":"X","kind":"number","value":2},{"id":"name","label":"Name","kind":"text"}],"components":[{"id":"value","kind":"metric","value":"=x*3"}]}"#)
        XCTAssertEqual(document.render("=x*3", values: ["x":4], texts: [:]), "12.0")
        XCTAssertEqual(document.render("=x*1000", values: ["x":4], texts: [:]), "4000.0")
        XCTAssertEqual(document.render("{{x}} {{name}}", values: ["x":4], texts: ["x":"", "name":"Ada"]), "4 Ada")
        XCTAssertEqual(document.render("Hello {{name}}", values: [:], texts: ["name":"Ada"]), "Hello Ada")
        XCTAssertEqual(document.render("=1/0", values: [:], texts: [:]), "—")
    }

    func testOptionalDefaultsAndRoundTrip() throws {
        let document = try GenUIDocument.validated(from: minimal)
        XCTAssertEqual(document.inputs, [])
        XCTAssertEqual(try JSONDecoder().decode(GenUIDocument.self, from: JSONEncoder().encode(document)), document)
        let input = try JSONDecoder().decode(GenUIInput.self, from: Data(#"{"id":"x","label":"X","kind":"number"}"#.utf8))
        XCTAssertEqual(input.value, 0)
        XCTAssertEqual(input.text, "")
    }

    func testRejectsMalformedUnsafeAndOversizedDocuments() {
        for json in ["{", String(repeating: " ", count: 131073),
            #"{"title":"Demo","components":[{"id":"x","kind":"html","text":"Hello"}]}"#,
            #"{"title":"Demo","components":[{"id":"x","kind":"metric","value":"=unknown+1"}]}"#,
            #"{"title":"Demo","inputs":[{"id":"x","label":"X","kind":"slider","value":3,"min":0,"max":2}],"components":[{"id":"x","kind":"text","text":"Hello"}]}"#,
            #"{"title":"Demo","inputs":[{"id":"x","label":"X","kind":"slider","value":0,"min":-1e308,"max":1e308}],"components":[{"id":"x","kind":"text","text":"Hello"}]}"#,
            #"{"title":"Demo","inputs":[{"id":"x","label":"X","kind":"number"},{"id":"x","label":"Again","kind":"number"}],"components":[{"id":"x","kind":"text","text":"Hello"}]}"#,
            #"{"title":"Demo","components":[{"id":"x","kind":"text","text":"{{missing}}"}]}"#] {
            XCTAssertThrowsError(try GenUIDocument.validated(from: json))
        }
        for expression in ["1/0", "sqrt(4)", "x.foo", "fetch('url')", "payment(1,0,0)", String(repeating:"(",count:40) + "1" + String(repeating:")",count:40)] {
            XCTAssertThrowsError(try GenUIExpression.evaluate(expression, values: [:]))
        }
    }

    func testRegistryExecutesCanonicalDocumentAndRejectsFailure() async throws {
        let registry = LocalToolRegistry(executors: [GenUITool()])
        let result = await registry.execute(call: ToolCall(id:"call", name:"genui", argumentsJSON:minimal))
        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.callId, "call")
        XCTAssertEqual(try GenUIDocument.validated(from: result.content).title, "Demo")
        let failure = await registry.execute(call: ToolCall(id:"bad", name:"genui", argumentsJSON:"{}"))
        XCTAssertTrue(failure.isError)
    }
}
