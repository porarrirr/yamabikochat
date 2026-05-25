import XCTest
@testable import YamabikoChat

private final class LiteLlmPricingMockURLProtocol: URLProtocol {
    static var responseData = Data()
    static var statusCode = 200

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let client else { return }
        let response = HTTPURLResponse(
            url: request.url ?? URL(string: "https://example.com")!,
            statusCode: Self.statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client.urlProtocol(self, didLoad: Self.responseData)
        client.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class LiteLlmPricingRepositoryTests: XCTestCase {
    private func makeRepository(withCatalogJSON json: String) -> LiteLlmPricingRepository {
        LiteLlmPricingMockURLProtocol.responseData = Data(json.utf8)
        LiteLlmPricingMockURLProtocol.statusCode = 200
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LiteLlmPricingMockURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return LiteLlmPricingRepository(session: session)
    }

    func testEstimateCostUsesCacheAndReasoningRatesForOpenRouter() async {
        let repository = makeRepository(
            withCatalogJSON: #"""
            {
              "openai/gpt-4o-mini": {
                "input_cost_per_token": 0.000001,
                "output_cost_per_token": 0.000002,
                "output_cost_per_reasoning_token": 0.000004,
                "cache_read_input_token_cost": 0.0000005,
                "cache_creation_input_token_cost": 0.0000015
              }
            }
            """#
        )

        let result = await repository.estimateCostUsd(
            provider: "OPENROUTER",
            model: "openai/gpt-4o-mini",
            inputTokens: 100,
            outputTokens: 50,
            cachedInputTokens: 30,
            cacheCreationInputTokens: 10,
            reasoningTokens: 20
        )

        XCTAssertEqual(result ?? -1, 0.00024, accuracy: 0.0000000001)
    }

    func testEstimateCostKeepsGeminiReasoningOutOfOutputSplit() async {
        let repository = makeRepository(
            withCatalogJSON: #"""
            {
              "gemini-2.5-flash": {
                "input_cost_per_token": 0.000001,
                "output_cost_per_token": 0.000002,
                "output_cost_per_reasoning_token": 0.000004,
                "cache_read_input_token_cost": 0.0000005,
                "cache_creation_input_token_cost": 0.0000015
              }
            }
            """#
        )

        let result = await repository.estimateCostUsd(
            provider: "GEMINI",
            model: "gemini-2.5-flash",
            inputTokens: 100,
            outputTokens: 50,
            cachedInputTokens: 30,
            cacheCreationInputTokens: 10,
            reasoningTokens: 20
        )

        XCTAssertEqual(result ?? -1, 0.00028, accuracy: 0.0000000001)
    }

    func testEstimateCostResolvesAlibabaCodingPlanLikeOtherOpenAICompatibleProviders() async {
        let repository = makeRepository(
            withCatalogJSON: #"""
            {
              "qwen/qwen3.5-plus": {
                "input_cost_per_token": 0.000001,
                "output_cost_per_token": 0.000002
              }
            }
            """#
        )

        let result = await repository.estimateCostUsd(
            provider: "ALIBABA_CODING_PLAN",
            model: "qwen3.5-plus",
            inputTokens: 100,
            outputTokens: 50,
            cachedInputTokens: nil,
            cacheCreationInputTokens: nil,
            reasoningTokens: nil
        )

        XCTAssertEqual(result ?? -1, 0.0002, accuracy: 0.0000000001)
    }

    func testModelSupportsVisionPhase1UsesProviderAwareCatalogEntry() async {
        let repository = makeRepository(
            withCatalogJSON: #"""
            {
              "openai/gpt-4o": {
                "input_cost_per_token": 0.000001,
                "supports_vision": true
              }
            }
            """#
        )

        let supports = await repository.modelSupportsVision(provider: "OPENROUTER", model: "openai/gpt-4o")
        XCTAssertTrue(supports)
    }

    func testModelSupportsVisionPhase1ExplicitFalse() async {
        let repository = makeRepository(
            withCatalogJSON: #"""
            {
              "text-only-model": {
                "supports_vision": false
              }
            }
            """#
        )

        let supports = await repository.modelSupportsVision(provider: "OPENROUTER", model: "text-only-model")
        XCTAssertFalse(supports)
    }

    func testModelSupportsVisionPhase2FallsBackToBasenameAcrossProviders() async {
        let repository = makeRepository(
            withCatalogJSON: #"""
            {
              "openrouter/foo-model": {
                "supports_vision": true
              }
            }
            """#
        )

        let supports = await repository.modelSupportsVision(provider: "OPENCODE_GO", model: "foo-model")
        XCTAssertTrue(supports)
    }

    func testModelSupportsVisionUnknownModelReturnsFalse() async {
        let repository = makeRepository(
            withCatalogJSON: #"""
            {
              "openai/gpt-4o": {
                "supports_vision": true
              }
            }
            """#
        )

        let supports = await repository.modelSupportsVision(provider: "OPENROUTER", model: "totally-unknown-model-xyz")
        XCTAssertFalse(supports)
    }
}
