import XCTest
@testable import YamabikoChat

final class ModelsDevCatalogTests: XCTestCase {
    func testParserExcludesOpenRouterDeprecatedAndNonTextModels() throws {
        let providers = try ModelsDevCatalogRepository.parseCatalog(Data(Self.fixture.utf8))
        XCTAssertEqual(providers.map(\.id), ["example"])
        XCTAssertEqual(providers[0].models.map(\.id), ["chat"])
        XCTAssertEqual(providers[0].models[0].toolCall, true)
        XCTAssertEqual(providers[0].models[0].providerContract?.npm, "@ai-sdk/openai")
        XCTAssertEqual(providers[0].models[0].providerContract?.shape, "responses")
        XCTAssertEqual(providers[0].models[0].supportedReasoningEfforts, ["low", "high"])
    }

    func testProviderReferenceRoundTripsWithoutGeminiNormalization() {
        let reference = ProviderReference.modelsDev("Acme")
        XCTAssertEqual(reference.persistedID, "MODELS_DEV:acme")
        XCTAssertEqual(ProviderReference(persistedID: reference.persistedID).modelsDevID, "acme")
        XCTAssertFalse(ProviderReference(persistedID: "UNKNOWN_PROVIDER").isModelsDev)
    }

    func testSavedReasoningEffortKeepsPreferenceVisibleWhenCatalogOptionsDisappear() {
        let model = CatalogModel(
            id: "reasoner",
            name: "Reasoner",
            attachment: false,
            reasoning: true,
            reasoningOptions: [],
            toolCall: false,
            structuredOutput: false,
            temperature: true,
            inputModalities: ["text"],
            outputModalities: ["text"],
            limits: CatalogLimits(context: nil, input: nil, output: nil),
            cost: CatalogCost(
                inputPerMillion: nil,
                outputPerMillion: nil,
                reasoningPerMillion: nil,
                cacheReadPerMillion: nil,
                cacheWritePerMillion: nil
            )
        )

        XCTAssertTrue(model.shouldShowReasoningEffortPreference(savedEffort: "high"))
        XCTAssertFalse(model.shouldShowReasoningEffortPreference(savedEffort: ""))
    }

    func testOpenCodeGoDoesNotUseOpenCodeZenCatalog() {
        XCTAssertNil(ModelsDevMergedProvider.catalogID(for: "OPENCODE_GO"))
        XCTAssertEqual(ModelsDevMergedProvider.catalogID(for: "MODELS_DEV:opencode"), "opencode")
    }

    func testBuiltInProvidersDoNotMergeWithDifferentProtocolCatalogs() {
        XCTAssertNil(ModelsDevMergedProvider.catalogID(for: "ALIBABA_CODING_PLAN"))
        XCTAssertNil(ModelsDevMergedProvider.catalogID(for: "MINIMAX"))
        XCTAssertNil(ModelsDevMergedProvider.catalogID(for: "ZAI"))
        XCTAssertNil(ModelsDevMergedProvider.catalogID(for: "OPENAI"))
        XCTAssertEqual(ModelsDevMergedProvider.catalogID(for: "MODELS_DEV:alibaba-coding-plan"), "alibaba-coding-plan")
        XCTAssertEqual(ModelsDevMergedProvider.catalogID(for: "MODELS_DEV:minimax"), "minimax")
        XCTAssertEqual(ModelsDevMergedProvider.catalogID(for: "MODELS_DEV:zai"), "zai")
        XCTAssertEqual(ModelsDevMergedProvider.catalogID(for: "MODELS_DEV:openai"), "openai")
    }

    func testOnlyDedicatedProvidersRemainBuiltIn() {
        XCTAssertEqual(
            ProviderCatalog.options.map(\.key),
            ["GEMINI", "OPENROUTER", "CODEX_AUTH", "SUPERGROK", "APPLE_INTELLIGENCE"]
        )
        XCTAssertEqual(ProviderCatalog.displayName(for: "MODELS_DEV:openai"), "openai")
    }

    func testFormerBuiltInProvidersAreSelectableFromModelsDev() {
        let providerIDs = [
            "openai", "opencode-go", "cline-pass", "alibaba-coding-plan",
            "zai-coding-plan", "minimax"
        ]
        XCTAssertTrue(providerIDs.allSatisfy(ModelsDevMergedProvider.isSelectableCatalogProvider))
        XCTAssertFalse(ModelsDevMergedProvider.isSelectableCatalogProvider("google"))
        XCTAssertFalse(ModelsDevMergedProvider.isSelectableCatalogProvider("openrouter"))
    }

    private static let fixture = #"""
    {"providers":{
      "openrouter":{"name":"OpenRouter","npm":"@ai-sdk/openai-compatible","models":{"or":{"name":"OR","modalities":{"output":["text"]}}}},
      "example":{"name":"Example","npm":"@ai-sdk/openai-compatible","env":["EXAMPLE_API_KEY"],"models":{
        "chat":{"name":"Chat","tool_call":true,"reasoning":true,"reasoning_options":[{"type":"effort","values":["low","high"]}],"provider":{"npm":"@ai-sdk/openai","shape":"responses"},"modalities":{"input":["text"],"output":["text"]}},
        "old":{"name":"Old","status":"deprecated","modalities":{"output":["text"]}},
        "image":{"name":"Image","modalities":{"output":["image"]}}
      }}
    }}
    """#
}
