import XCTest
@testable import YamabikoChat

final class GenUIIntegrationTests: XCTestCase {
    func testNativePCCUsesThePublicSDKCompatibleDocumentEnvelope() async throws {
        let resolved = try await makeResolver().resolve(settings: settings(), provider: LLMProvider.appleIntelligence.rawValue, model: AppleIntelligenceModelCatalog.pccModel)
        let tool = try XCTUnwrap(resolved.tools.first { $0.payload["name"] == GenUITool.name })
        XCTAssertEqual(tool.payload["parameters"], GenUITool.nativeDefinition.parametersJSON)
        if #available(iOS 27.0, *) {
            let parameters = try JSONDecoder().decode(JSONValue.self, from: Data(GenUITool.nativeDefinition.parametersJSON.utf8))
            XCTAssertNoThrow(try PCCNativeToolSchema.make(parameters, name: GenUITool.name))
        }
    }

    func testGenUIIsAdvertisedForEveryBuiltInClientToolProvider() async throws {
        let resolver = makeResolver()
        for provider in LLMProvider.allCases {
            let model = provider == .appleIntelligence ? "on-device" : "test-model"
            let resolved = try await resolver.resolve(settings: settings(), provider: provider.rawValue, model: model)
            var disabled = settings()
            disabled.genUIToolEnabled = false
            let withoutGenUI = try await resolver.resolve(settings: disabled, provider: provider.rawValue, model: model)
            assertNoGenUI(withoutGenUI)
            let expected = provider != .appleIntelligence
            XCTAssertEqual(containsGenUI(resolved.tools), expected, provider.rawValue)
            XCTAssertEqual(resolved.metadata["supportsClientTools"], expected ? "true" : "false", provider.rawValue)
        }
        let pcc = try await resolver.resolve(
            settings: settings(), provider: LLMProvider.appleIntelligence.rawValue,
            model: AppleIntelligenceModelCatalog.pccModel
        )
        XCTAssertTrue(containsGenUI(pcc.tools))
        var disabled = settings()
        disabled.genUIToolEnabled = false
        let withoutGenUI = try await resolver.resolve(
            settings: disabled, provider: LLMProvider.appleIntelligence.rawValue,
            model: AppleIntelligenceModelCatalog.pccModel
        )
        assertNoGenUI(withoutGenUI)
    }

    func testGenUIRespectsConversationContextsAndToolScopes() async throws {
        let resolver = makeResolver()
        for context: AppSettings.ReasoningContext in [.default, .dualA, .dualB, .autoA, .autoB] {
            let resolved = try await resolver.resolve(
                settings: settings(), provider: "OPENAI", model: "gpt-5.6", context: context
            )
            XCTAssertEqual(containsGenUI(resolved.tools), context == .default || context == .dualA || context == .dualB)
        }
        for scope: ProviderRequestToolScope in [.none, .providerOnly] {
            let resolved = try await resolver.resolve(
                settings: settings(), provider: "OPENAI", model: "gpt-5.6", toolScope: scope
            )
            XCTAssertFalse(containsGenUI(resolved.tools))
        }
    }

    func testGeminiNativeToolsSuppressGenUIFunctionTool() async throws {
        let resolver = makeResolver()
        for nativeTool in ["search", "code", "url", "maps"] {
            var value = settings()
            value.geminiGoogleSearchEnabled = nativeTool == "search"
            value.geminiCodeExecutionEnabled = nativeTool == "code"
            value.geminiURLContextEnabled = nativeTool == "url"
            value.geminiGoogleMapsEnabled = nativeTool == "maps"
            let resolved = try await resolver.resolve(settings: value, provider: "GEMINI", model: "gemini-2.5-flash")
            XCTAssertFalse(containsGenUI(resolved.tools), nativeTool)
        }
    }

    func testModelsDevCapabilitiesGateGenUIAcrossProviderProtocolPackages() async throws {
        let cacheURL = FileManager.default.temporaryDirectory.appendingPathComponent("genui-catalog-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let packages = ["@ai-sdk/openai", "@ai-sdk/openai-compatible", "@ai-sdk/anthropic", "@ai-sdk/google"]
        let providers = packages.enumerated().map { index, package in
            CatalogProvider(
                id: "genui-provider-\(index)", name: package, npm: package,
                api: "https://example.com", env: [],
                models: [catalogModel(id: "enabled", toolCall: true), catalogModel(id: "disabled", toolCall: false), catalogModel(id: "missing", toolCall: nil)]
            )
        }
        try JSONEncoder().encode(providers).write(to: cacheURL)
        let resolver = ProviderRequestSettingsResolver(
            modelService: OpenRouterModelService(credentialStore: GenUIIntegrationCredentialStore()),
            modelsDevCatalogRepository: ModelsDevCatalogRepository(cacheURL: cacheURL)
        )
        for provider in providers {
            for model in provider.models {
                let resolved = try await resolver.resolve(settings: settings(), provider: "MODELS_DEV:\(provider.id)", model: model.id)
                XCTAssertEqual(containsGenUI(resolved.tools), model.toolCall == true, "\(provider.npm)/\(model.id)")
                XCTAssertEqual(resolved.metadata["supportsClientTools"], model.toolCall == true ? "true" : "false")
                var disabled = settings()
                disabled.genUIToolEnabled = false
                let withoutGenUI = try await resolver.resolve(
                    settings: disabled, provider: "MODELS_DEV:\(provider.id)", model: model.id
                )
                assertNoGenUI(withoutGenUI)
            }
        }
    }

    func testSuccessfulGenUIDocumentsSurvivePayloadAndRecordReloadInExecutionOrder() throws {
        var payload = ToolActivityPayload()
        for id in ["first", "second"] {
            let call = ToolCall(id: id, name: GenUITool.name, argumentsJSON: "{}")
            let content = #"{"title":"Demo","components":[{"id":"summary","kind":"text","text":"Hello"}]}"#
            payload.apply(ToolActivityEvent(
                phase: .finished, call: call,
                result: ToolResult(callId: id, name: GenUITool.name, content: content), createdAtMs: 1
            ))
        }
        XCTAssertEqual(payload.steps.map(\.id), ["first", "second"])
        XCTAssertTrue(payload.steps.allSatisfy { $0.genUIDocument != nil })
        let restored = try JSONDecoder().decode(ToolActivityPayload.self, from: JSONEncoder().encode(payload))
        XCTAssertEqual(restored.steps, payload.steps)
        // Transcript messages regenerate their in-memory UUID when decoded.
        XCTAssertEqual(restored.providerTranscript.map(\.content), payload.providerTranscript.map(\.content))
        XCTAssertEqual(restored.providerTranscript.map(\.toolCallId), payload.providerTranscript.map(\.toolCallId))
        let stepsJSON = try XCTUnwrap(String(data: JSONEncoder().encode(payload.steps), encoding: .utf8))
        let record = ChatMessageToolActivity(messageId: 42, stepsJSON: stepsJSON)
        XCTAssertEqual(record.payload.steps, payload.steps)
        XCTAssertEqual(record.payload.steps.compactMap(\.genUIDocument).count, 2)
    }

    func testPiArgumentPreviewsRetainTheLatestValidDocumentUntilCompletion() {
        var payload = ToolActivityPayload()
        let initial = ToolCall(id: "live", name: GenUITool.name, argumentsJSON: #"{"title":"Preview","ui":{"type":"text","children":["First"]}}"#)
        payload.apply(ToolActivityEvent(phase: .generating, call: initial, createdAtMs: 1))
        XCTAssertEqual(payload.steps[0].status, .running)
        XCTAssertNotNil(payload.steps[0].genUIDocument)
        let incomplete = ToolCall(id: "live", name: GenUITool.name, argumentsJSON: #"{"title":"Preview","code":"return DIL.h("}"#)
        payload.apply(ToolActivityEvent(phase: .generating, call: incomplete, createdAtMs: 2))
        XCTAssertEqual(payload.steps.count, 1)
        XCTAssertNotNil(payload.steps[0].genUIDocument)
        payload.apply(ToolActivityEvent(phase: .started, call: initial, createdAtMs: 3))
        XCTAssertNotNil(payload.steps[0].genUIDocument)
        let result = ToolResult(callId: "live", name: GenUITool.name, content: initial.argumentsJSON)
        payload.apply(ToolActivityEvent(phase: .finished, call: initial, result: result, createdAtMs: 4))
        XCTAssertEqual(payload.steps[0].status, .completed)
        XCTAssertEqual(payload.providerTranscript.count, 2)
    }

    func testFailedAndInvalidGenUIResultsDoNotBecomeRenderableDocuments() {
        var payload = ToolActivityPayload()
        let validContent = #"{"title":"Demo","components":[{"id":"summary","kind":"text","text":"Hello"}]}"#
        for (id, content, isError) in [("failed", validContent, true), ("malformed", "not-json", false)] {
            let call = ToolCall(id: id, name: GenUITool.name, argumentsJSON: "{}")
            payload.apply(ToolActivityEvent(
                phase: .finished, call: call,
                result: ToolResult(callId: id, name: GenUITool.name, content: content, isError: isError), createdAtMs: 1
            ))
        }
        XCTAssertTrue(payload.steps.allSatisfy { $0.genUIDocument == nil })
        XCTAssertEqual(payload.steps.first?.status, .failed)
    }

    func testPiBridgeReportsGenUIActivityAlongsideExistingLocalTools() {
        for name in [GenUITool.name, WebSearchTool.name, FetchUrlTool.name,
                     PythonExecuteTool.name, StrReplaceEditorTool.name] {
            XCTAssertTrue(ToolActivityEvent.reportsActivity(for: name), name)
        }
        XCTAssertFalse(ToolActivityEvent.reportsActivity(for: "unknown"))
    }

    func testTranscriptOnlyGenUIIsRestoredForNormalVariantsAndDualMessages() throws {
        let richJSON = String(decoding: try JSONEncoder().encode(GenUIDocument(
            title: "Rich demo", code: GenUIRichDemoFixture.code
        )), as: UTF8.self)
        let transcript = genUITranscript(id: "saved", content: GenUIDemoFixture.documentJSON)
            + genUITranscript(id: "rich", content: richJSON)
        let transcriptData = try JSONEncoder().encode(transcript)
        let record = ChatMessageToolActivity(
            messageId: 42, stepsJSON: "[]",
            providerTranscriptJSON: String(decoding: transcriptData, as: UTF8.self)
        )
        XCTAssertEqual(record.steps.map(\.id), ["saved", "rich"])
        XCTAssertTrue(record.steps.allSatisfy { $0.genUIDocument != nil })
        XCTAssertEqual(record.steps.map(\.round), [1, 2])
        let variant = ChatMessageToolActivity(
            variantId: 43, stepsJSON: "[]", providerTranscriptJSON: record.providerTranscriptJSON
        )
        XCTAssertEqual(variant.steps, record.steps)
        let rawPayload = #"{"steps":[],"providerTranscript":\#(String(decoding: transcriptData, as: UTF8.self))}"#
        let restored = try JSONDecoder().decode(ToolActivityPayload.self, from: Data(rawPayload.utf8))
        XCTAssertEqual(restored.steps, record.steps)
        let reloaded = try JSONDecoder().decode(ToolActivityPayload.self, from: JSONEncoder().encode(restored))
        XCTAssertEqual(reloaded.steps, restored.steps)
        XCTAssertEqual(reloaded.providerTranscript.map(\.content), transcript.map(\.content))
    }

    func testTranscriptRecoveryRequiresSuccessfulValidatedResultAndMatchingCall() throws {
        var transcript = genUITranscript(id: "failed", content: GenUIDemoFixture.documentJSON)
        transcript[1].toolResultIsError = true
        transcript += genUITranscript(id: "invalid", content: "not-json")
        transcript += [ProviderRequestMessage(role: "tool", content: GenUIDemoFixture.documentJSON,
                                              toolCallId: "orphan", toolName: GenUITool.name, toolResultIsError: false)]
        transcript += [ProviderRequestMessage(role: "assistant", content: "", toolCalls: [
            ToolCall(id: "unfinished", name: GenUITool.name, argumentsJSON: GenUIDemoFixture.documentJSON)
        ])]
        XCTAssertTrue(ToolActivityPayload(providerTranscript: transcript).steps.isEmpty)
    }

    func testTranscriptRecoveryPreservesExistingStepsAndDoesNotDuplicateResults() throws {
        var payload = ToolActivityPayload()
        let call = ToolCall(id: "existing", name: GenUITool.name, argumentsJSON: GenUIDemoFixture.documentJSON)
        payload.apply(ToolActivityEvent(phase: .finished, call: call, result: ToolResult(
            callId: call.id, name: call.name, content: GenUIDemoFixture.documentJSON
        ), createdAtMs: 123))
        let transcript = payload.providerTranscript + genUITranscript(id: "missing", content: GenUIDemoFixture.documentJSON)
        let restored = ToolActivityPayload(steps: payload.steps, providerTranscript: transcript + transcript)
        XCTAssertEqual(restored.steps.map(\.id), ["existing", "missing"])
        XCTAssertEqual(restored.steps.first, payload.steps.first)
    }

    private func genUITranscript(id: String, content: String) -> [ProviderRequestMessage] {
        [ProviderRequestMessage(role: "assistant", content: "", toolCalls: [
            ToolCall(id: id, name: GenUITool.name, argumentsJSON: content)
        ]), ProviderRequestMessage(role: "tool", content: content,
                                   toolCallId: id, toolName: GenUITool.name, toolResultIsError: false)]
    }

    func testLegacyToolActivityWithoutGenUIDocumentStillDecodes() throws {
        let json = #"{"id":"legacy","round":1,"toolName":"web_search","title":"Web","detail":"query","status":"completed","sources":[],"createdAtMs":1}"#
        let step = try JSONDecoder().decode(ToolActivityStep.self, from: Data(json.utf8))
        XCTAssertNil(step.genUIDocument)
        XCTAssertEqual(step.status, .completed)
    }

    @MainActor
    func testGenUIHeightInvalidatesTheOwningRowAndSurvivesReuse() {
        let row = makeTimelineRow()
        let state = row.genUIState(id: "reference", document: GenUIReferenceFixture.document)
        let revision = row.contentLayoutRevision
        state.richHeight = 1100
        XCTAssertEqual(row.contentLayoutRevision, revision + 1)
        state.richHeight = 1100
        XCTAssertEqual(row.contentLayoutRevision, revision + 1)
        XCTAssertEqual(row.genUIState(id: "reference", document: GenUIReferenceFixture.document).richHeight, 1100)
    }

    @MainActor
    func testTimelineRowRetainsInputStateForTheSameToolDocument() throws {
        let row = makeTimelineRow()
        let document = try GenUIDocument.validated(from: GenUIDemoFixture.documentJSON)
        let state = row.genUIState(id: "loan", document: document)
        state.values["principal"] = 45_000_000
        state.numberDrafts["principal"] = "45000000"
        state.showsInputs = true
        let reused = row.genUIState(id: "loan", document: document)
        XCTAssertTrue(state === reused)
        XCTAssertEqual(reused.values["principal"], 45_000_000)
        XCTAssertEqual(reused.numberDrafts["principal"], "45000000")
        XCTAssertTrue(reused.showsInputs)
    }

    @MainActor
    func testTimelineRowResetsStateWhenDocumentChanges() throws {
        let row = makeTimelineRow()
        var document = try GenUIDocument.validated(from: GenUIDemoFixture.documentJSON)
        let original = row.genUIState(id: "loan", document: document)
        original.values["principal"] = 45_000_000
        document.title = "Updated loan comparison"
        let replaced = row.genUIState(id: "loan", document: document)
        XCTAssertFalse(original === replaced)
        XCTAssertEqual(replaced.values["principal"], 30_000_000)
        XCTAssertEqual(replaced.document, document)
    }

    @MainActor
    func testTimelineRowIsolatesStateForDifferentToolCallsAndRows() throws {
        let row = makeTimelineRow()
        let document = try GenUIDocument.validated(from: GenUIDemoFixture.documentJSON)
        let first = row.genUIState(id: "first", document: document)
        let second = row.genUIState(id: "second", document: document)
        let otherRow = makeTimelineRow().genUIState(id: "first", document: document)
        first.values["principal"] = 45_000_000
        XCTAssertFalse(first === second)
        XCTAssertFalse(first === otherRow)
        XCTAssertEqual(second.values["principal"], 30_000_000)
        XCTAssertEqual(otherRow.values["principal"], 30_000_000)
    }

    @MainActor
    private func makeTimelineRow() -> ChatTimelineRowStore {
        ChatTimelineRowStore(item: .message(FullChatMessage(
            id: 1, message: ChatMessage(id: 1, conversationId: 1, role: "assistant", text: "Loan"),
            thinkingStream: nil, variants: []
        )))
    }

    func testGenUIToggleControlsDefinitionsAndPromptIndependentlyOfOtherTools() async throws {
        let resolver = makeResolver()
        for enabled in [false, true] {
            for search in [false, true] {
                for python in [false, true] {
                    var value = settings()
                    value.genUIToolEnabled = enabled
                    value.clientWebSearchToolEnabled = search
                    value.pythonToolEnabled = python
                    let resolved = try await resolver.resolve(settings: value, provider: "OPENAI", model: "gpt-5.6")
                    XCTAssertEqual(resolved.tools.containsGenUITool, enabled)
                    XCTAssertEqual(resolved.tools.contains { $0.payload["name"] == GenUIReferenceTool.name }, enabled)
                    XCTAssertEqual(resolved.tools.containsWebSearchTool, search)
                    XCTAssertEqual(resolved.tools.containsPythonTool, python)
                    let prompt = try XCTUnwrap(SystemPromptComposer.composeForAPI(
                        "Custom instructions",
                        enablesAgenticWebSearch: resolved.tools.containsWebSearchTool,
                        enablesPythonInstructions: resolved.tools.containsPythonTool,
                        enablesGenUIInstructions: resolved.tools.containsGenUITool
                    ))
                    XCTAssertTrue(prompt.hasPrefix("Custom instructions"))
                    XCTAssertEqual(prompt.contains(SystemPromptComposer.genUIToolInstructions), enabled)
                    XCTAssertEqual(prompt.contains(SystemPromptComposer.agenticWebSearchInstructions), search)
                    XCTAssertEqual(prompt.contains(SystemPromptComposer.pythonToolInstructions), python)
                    if !enabled { XCTAssertFalse(prompt.contains("genui")) }
                }
            }
        }
    }

    private func assertNoGenUI(
        _ resolved: ProviderRequestResolvedSettings,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertFalse(resolved.tools.containsGenUITool, file: file, line: line)
        XCTAssertFalse(resolved.tools.contains { $0.payload["name"] == GenUIReferenceTool.name }, file: file, line: line)
        let prompt = SystemPromptComposer.composeForAPI(nil, enablesGenUIInstructions: resolved.tools.containsGenUITool)
        XCTAssertFalse(prompt?.contains("genui") == true, file: file, line: line)
    }

    private func settings() -> AppSettings {
        var value = AppSettings()
        value.pythonToolEnabled = false
        value.geminiGoogleSearchEnabled = false
        value.geminiCodeExecutionEnabled = false
        value.geminiURLContextEnabled = false
        value.geminiGoogleMapsEnabled = false
        return value
    }

    private func containsGenUI(_ tools: [ProviderTool]) -> Bool {
        tools.contains { $0.type == "function" && $0.payload["name"] == GenUITool.name }
    }

    private func makeResolver() -> ProviderRequestSettingsResolver {
        ProviderRequestSettingsResolver(modelService: OpenRouterModelService(credentialStore: GenUIIntegrationCredentialStore()))
    }

    private func catalogModel(id: String, toolCall: Bool?) -> CatalogModel {
        CatalogModel(
            id: id, name: id, reasoningOptions: [], toolCall: toolCall,
            inputModalities: ["text"], outputModalities: ["text"],
            limits: CatalogLimits(context: nil, input: nil, output: nil),
            cost: CatalogCost(inputPerMillion: nil, outputPerMillion: nil, reasoningPerMillion: nil,
                              cacheReadPerMillion: nil, cacheWritePerMillion: nil)
        )
    }
}

private struct GenUIIntegrationCredentialStore: SecureCredentialStore {
    func saveSecret(_ value: String?, key: String) throws {}
    func readSecret(key: String) throws -> String? { nil }
    func deleteSecret(key: String) throws {}
}
