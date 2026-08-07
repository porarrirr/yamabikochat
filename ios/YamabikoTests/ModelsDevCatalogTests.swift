import XCTest
@testable import YamabikoChat

final class ModelsDevCatalogTests: XCTestCase {
    func testParserExcludesOpenRouterDeprecatedAndNonTextModels() throws {
        let providers = try ModelsDevCatalogRepository.parseCatalog(Data(Self.fixture.utf8))
        XCTAssertEqual(providers.map(\.id), ["example"])
        XCTAssertEqual(providers[0].models.map(\.id), ["chat"])
        XCTAssertTrue(providers[0].models[0].toolCall)
    }

    func testAllCurrentNpmKindsHaveVerifiedMappings() {
        for npm in Self.currentNpmKinds {
            let provider = CatalogProvider(
                id: "fixture", name: "Fixture", npm: npm, api: "https://example.com/v1",
                env: ["EXAMPLE_API_KEY"], models: []
            )
            XCTAssertTrue(ModelsDevProviderAdapterRegistry.profile(for: provider).isVerifiedMapping, npm)
        }
        let future = CatalogProvider(id: "future", name: "Future", npm: "future-sdk", api: "https://example.com/v1", env: [], models: [])
        XCTAssertFalse(ModelsDevProviderAdapterRegistry.profile(for: future).isVerifiedMapping)
    }

    func testProviderReferenceRoundTripsWithoutGeminiNormalization() {
        let reference = ProviderReference.modelsDev("Acme")
        XCTAssertEqual(reference.persistedID, "MODELS_DEV:acme")
        XCTAssertEqual(ProviderReference(persistedID: reference.persistedID).modelsDevID, "acme")
        XCTAssertFalse(ProviderReference(persistedID: "UNKNOWN_PROVIDER").isModelsDev)
    }

    func testOpenCodeGoDoesNotUseOpenCodeZenCatalog() {
        XCTAssertNil(ModelsDevMergedProvider.catalogID(for: "OPENCODE_GO"))
        XCTAssertEqual(ModelsDevMergedProvider.catalogID(for: "MODELS_DEV:opencode"), "opencode")
    }

    func testBuiltInProvidersDoNotMergeWithDifferentProtocolCatalogs() {
        XCTAssertNil(ModelsDevMergedProvider.catalogID(for: "ALIBABA_CODING_PLAN"))
        XCTAssertNil(ModelsDevMergedProvider.catalogID(for: "MINIMAX"))
        XCTAssertNil(ModelsDevMergedProvider.catalogID(for: "ZAI"))
        XCTAssertEqual(ModelsDevMergedProvider.catalogID(for: "MODELS_DEV:alibaba-coding-plan"), "alibaba-coding-plan")
        XCTAssertEqual(ModelsDevMergedProvider.catalogID(for: "MODELS_DEV:minimax"), "minimax")
        XCTAssertEqual(ModelsDevMergedProvider.catalogID(for: "MODELS_DEV:zai"), "zai")
    }

    private static let currentNpmKinds = [
        "@ai-sdk/amazon-bedrock", "@ai-sdk/anthropic", "@ai-sdk/azure", "@ai-sdk/cerebras",
        "@ai-sdk/cohere", "@ai-sdk/deepinfra", "@ai-sdk/gateway", "@ai-sdk/google",
        "@ai-sdk/google-vertex", "@ai-sdk/google-vertex/anthropic", "@ai-sdk/groq", "@ai-sdk/mistral",
        "@ai-sdk/openai", "@ai-sdk/openai-compatible", "@ai-sdk/perplexity", "@ai-sdk/togetherai",
        "@ai-sdk/vercel", "@ai-sdk/xai", "@aihubmix/ai-sdk-provider", "@jerome-benoit/sap-ai-provider-v2",
        "@qvac/ai-sdk-provider", "ai-gateway-provider", "gitlab-ai-provider",
        "merge-gateway-ai-sdk-provider", "venice-ai-sdk-provider"
    ]

    private static let fixture = #"""
    {"providers":{
      "openrouter":{"name":"OpenRouter","npm":"@ai-sdk/openai-compatible","models":{"or":{"name":"OR","modalities":{"output":["text"]}}}},
      "example":{"name":"Example","npm":"@ai-sdk/openai-compatible","env":["EXAMPLE_API_KEY"],"models":{
        "chat":{"name":"Chat","tool_call":true,"modalities":{"input":["text"],"output":["text"]}},
        "old":{"name":"Old","status":"deprecated","modalities":{"output":["text"]}},
        "image":{"name":"Image","modalities":{"output":["image"]}}
      }}
    }}
    """#
}
