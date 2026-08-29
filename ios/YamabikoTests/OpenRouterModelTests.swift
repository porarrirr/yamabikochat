import XCTest
import Combine
@testable import YamabikoChat

private final class OpenRouterTestCredentialStore: SecureCredentialStore {
    private var storage: [String: String] = [:]

    func saveSecret(_ value: String?, key: String) throws {
        if let value {
            storage[key] = value
        } else {
            storage.removeValue(forKey: key)
        }
    }

    func readSecret(key: String) throws -> String? {
        storage[key]
    }

    func deleteSecret(key: String) throws {
        storage.removeValue(forKey: key)
    }
}

private final class OpenRouterRecordingHTTPClient: HTTPClientProtocol {
    private(set) var sentURLs: [URL] = []
    let data: Data

    init(data: Data) {
        self.data = data
    }

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        sentURLs.append(request.url)
        let response = HTTPURLResponse(
            url: request.url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

}

private struct OpenRouterStubHTTPClient: HTTPClientProtocol {
    var data: Data
    var statusCode: Int

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

}

private actor SupersedingOpenRouterModelsHTTPClient: HTTPClientProtocol {
    private var requestCount = 0

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        let requestNumber = requestCount
        await delayIgnoringCancellation(nanoseconds: requestNumber == 1 ? 200_000_000 : 20_000_000)
        let id = requestNumber == 1 ? "example/old" : "example/new"
        let data = #"{"data":[{"id":"\#(id)","name":"\#(id)","pricing":{"prompt":"0","completion":"0"}}]}"#
            .data(using: .utf8)!
        let response = HTTPURLResponse(
            url: request.url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }


    private func delayIgnoringCancellation(nanoseconds: UInt64) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + .nanoseconds(Int(nanoseconds))) {
                continuation.resume()
            }
        }
    }
}

private actor SupersedingOpenRouterEndpointsHTTPClient: HTTPClientProtocol {
    private var requestCount = 0

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        requestCount += 1
        let requestNumber = requestCount
        await delayIgnoringCancellation(nanoseconds: requestNumber == 1 ? 200_000_000 : 20_000_000)
        let tag = requestNumber == 1 ? "old/fp8" : "new/fp8"
        let data = #"{"data":{"endpoints":[{"name":"Endpoint","provider_name":"Provider","tag":"\#(tag)","quantization":"fp8"}]}}"#
            .data(using: .utf8)!
        let response = HTTPURLResponse(
            url: request.url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

    func numberOfRequests() -> Int {
        requestCount
    }

    private func delayIgnoringCancellation(nanoseconds: UInt64) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + .nanoseconds(Int(nanoseconds))) {
                continuation.resume()
            }
        }
    }
}

final class OpenRouterModelTests: XCTestCase {
    func testSimpleModelConversionMarksFreeModel() {
        let model = OpenRouterModel(
            id: "meta-llama/llama-3.1-8b-instruct:free",
            name: "Llama",
            description: nil,
            pricing: .init(prompt: "0", completion: "0", request: nil),
            contextLength: 131072,
            topProvider: .init(availableProviders: ["meta"], availableQuantizations: ["fp16"])
        )

        let simple = SimpleModel.fromOpenRouterModel(model)

        XCTAssertTrue(simple.isFree)
        XCTAssertEqual(simple.provider, "meta-llama")
        XCTAssertEqual(simple.contextLength, 131072)
    }

    func testProviderDirectorySlugLookup() {
        let providers = [
            ProviderInfo(name: "OpenAI", slug: "openai"),
            ProviderInfo(name: "Anthropic", slug: "anthropic")
        ]

        let directory = ProviderDirectory.fromList(providers)
        XCTAssertEqual(directory.slugForName("OpenAI"), "openai")
        XCTAssertEqual(directory.nameForSlug("anthropic"), "Anthropic")
    }

    func testServiceParsesMixedOpenRouterModelShapes() async {
        let payload = """
        {
          "data": [
            {
              "id": "openai/gpt-5",
              "name": "GPT-5",
              "pricing": {
                "prompt": 0.00001,
                "completion": "0.00002"
              },
              "context_length": "128000",
              "top_provider": {
                "available_providers": ["openai"],
                "available_quantizations": ["fp16"]
              }
            },
            {
              "id": "meta-llama/llama-3.1-8b-instruct:free",
              "pricing": {
                "prompt": "0",
                "completion": 0
              },
              "context_length": 131072
            },
            {
              "id": "",
              "name": "broken",
              "pricing": {}
            }
          ]
        }
        """.data(using: .utf8)!

        let service = OpenRouterModelService(
            credentialStore: OpenRouterTestCredentialStore(),
            httpClient: OpenRouterStubHTTPClient(data: payload, statusCode: 200)
        )

        let models = await service.getAvailableModels(forceRefresh: true)
        XCTAssertEqual(models.count, 2)

        let first = models.first { $0.id == "openai/gpt-5" }
        XCTAssertEqual(first?.name, "GPT-5")
        XCTAssertEqual(first?.contextLength, 128000)
        XCTAssertEqual(first?.availableProviders, ["openai"])
        XCTAssertEqual(first?.availableQuantizations, ["fp16"])

        let free = models.first { $0.id == "meta-llama/llama-3.1-8b-instruct:free" }
        XCTAssertEqual(free?.name, "meta-llama/llama-3.1-8b-instruct:free")
        XCTAssertTrue(free?.isFree ?? false)
    }

    func testServiceParsesModelSpecificReasoningCapabilities() async {
        let payload = #"""
        {
          "data": [
            {
              "id": "z-ai/glm-5.2",
              "name": "GLM 5.2",
              "pricing": { "prompt": "0.000001", "completion": "0.000002" },
              "reasoning": {
                "supported_efforts": ["xhigh", "high"],
                "default_effort": "high",
                "default_enabled": true,
                "supports_max_tokens": true,
                "mandatory": false
              }
            },
            {
              "id": "example/gateway-efforts",
              "name": "Gateway efforts",
              "pricing": { "prompt": "0", "completion": "0" },
              "reasoning": { "supported_efforts": null }
            },
            {
              "id": "example/no-effort-key",
              "name": "No effort key",
              "pricing": { "prompt": "0", "completion": "0" },
              "reasoning": { "supports_max_tokens": true, "mandatory": true }
            },
            {
              "id": "example/no-reasoning",
              "name": "No reasoning",
              "pricing": { "prompt": "0", "completion": "0" }
            }
          ]
        }
        """#.data(using: .utf8)!

        let service = OpenRouterModelService(
            credentialStore: OpenRouterTestCredentialStore(),
            httpClient: OpenRouterStubHTTPClient(data: payload, statusCode: 200)
        )

        let models = await service.getAvailableModels(forceRefresh: true)
        let glm = models.first { $0.id == "z-ai/glm-5.2" }?.reasoning
        XCTAssertEqual(glm?.selectableEfforts, ["xhigh", "high"])
        XCTAssertEqual(glm?.defaultEffort, "high")
        XCTAssertEqual(glm?.defaultEnabled, true)
        XCTAssertEqual(glm?.supportsMaxTokens, true)
        XCTAssertEqual(glm?.mandatory, false)

        let gateway = models.first { $0.id == "example/gateway-efforts" }?.reasoning
        XCTAssertEqual(gateway?.exposesEffortSelection, true)
        XCTAssertNil(gateway?.supportedEfforts)
        XCTAssertEqual(gateway?.selectableEfforts, OpenRouterReasoningCapabilities.gatewayEfforts)

        let omitted = models.first { $0.id == "example/no-effort-key" }?.reasoning
        XCTAssertEqual(omitted?.exposesEffortSelection, false)
        XCTAssertEqual(omitted?.selectableEfforts, [])
        XCTAssertEqual(omitted?.supportsMaxTokens, true)
        XCTAssertEqual(omitted?.mandatory, true)
        XCTAssertNil(models.first { $0.id == "example/no-reasoning" }?.reasoning)
    }

    func testConcurrentModelFetchUsesSingleHTTPRequest() async {
        let payload = """
        {
          "data": [
            {
              "id": "openai/gpt-4o",
              "name": "GPT-4o",
              "pricing": { "prompt": "0.00001", "completion": "0.00002" },
              "context_length": 128000
            }
          ]
        }
        """.data(using: .utf8)!

        let httpClient = OpenRouterRecordingHTTPClient(data: payload)
        let service = OpenRouterModelService(
            credentialStore: OpenRouterTestCredentialStore(),
            httpClient: httpClient
        )

        async let first = service.getAvailableModels(forceRefresh: true)
        async let second = service.getAvailableModels(forceRefresh: false)
        let models = await (first, second)

        XCTAssertEqual(models.0.count, 1)
        XCTAssertEqual(models.1.count, 1)
        XCTAssertEqual(httpClient.sentURLs.count, 1)
    }

    func testForcedModelRefreshCancellationCannotOverwriteLatestCatalogOrPublishError() async {
        let httpClient = SupersedingOpenRouterModelsHTTPClient()
        let service = OpenRouterModelService(
            credentialStore: OpenRouterTestCredentialStore(),
            httpClient: httpClient
        )
        var errors: [String] = []
        var cancellables: Set<AnyCancellable> = []
        service.errorPublisher
            .compactMap { $0 }
            .sink { errors.append($0) }
            .store(in: &cancellables)

        let oldRequest = Task { await service.getAvailableModels(forceRefresh: true) }
        try? await Task.sleep(nanoseconds: 30_000_000)
        let latestRequest = Task { await service.getAvailableModels(forceRefresh: true) }
        _ = await latestRequest.value
        _ = await oldRequest.value

        XCTAssertEqual(service.currentModels().map(\.id), ["example/new"])
        XCTAssertTrue(errors.isEmpty)
    }

    func testModelEndpointsRequestKeepsVariantSuffix() async {
        let payload = """
        {
          "data": {
            "endpoints": [
              {
                "name": "Google AI Studio | google/gemma-4-31b-it:free",
                "provider_name": "Google AI Studio"
              }
            ]
          }
        }
        """.data(using: .utf8)!
        let httpClient = OpenRouterRecordingHTTPClient(data: payload)
        let service = OpenRouterModelService(
            credentialStore: OpenRouterTestCredentialStore(),
            httpClient: httpClient
        )

        let endpoints = await service.getModelEndpoints(modelId: "google/gemma-4-31b-it:free")

        XCTAssertEqual(
            httpClient.sentURLs.first?.absoluteString,
            "https://openrouter.ai/api/v1/models/google/gemma-4-31b-it:free/endpoints"
        )
        XCTAssertEqual(endpoints.map(\.providerName), ["Google AI Studio"])
    }

    func testGLMEndpointFixturePreservesAllExactTagsInAPIOrder() async throws {
        let fixtureURL = try XCTUnwrap(
            Bundle(for: Self.self).url(
                forResource: "openrouter-glm-5-2-endpoints",
                withExtension: "json"
            )
        )
        let service = OpenRouterModelService(
            credentialStore: OpenRouterTestCredentialStore(),
            httpClient: OpenRouterStubHTTPClient(data: try Data(contentsOf: fixtureURL), statusCode: 200)
        )

        let options = try await service.getModelEndpointOptions(modelId: "z-ai/glm-5.2")

        XCTAssertEqual(options.endpoints.count, 32)
        XCTAssertEqual(options.providerEndpoints.count, 32)
        XCTAssertEqual(options.providerEndpoints.first?.tag, "novita/fp8")
        XCTAssertEqual(options.providerEndpoints.last?.tag, "alibaba/fast")
        XCTAssertEqual(
            options.providerEndpoints.filter { $0.providerName == "Alibaba" }.map(\.tag),
            ["alibaba/fp8", "alibaba/fast"]
        )
        XCTAssertEqual(options.quantizations, ["fp8", "unknown", "fp4"])
        XCTAssertTrue(options.providerEndpoints[0].supportedParameters.contains("reasoning_effort"))
    }

    func testEndpointOptionsDeduplicateOnlyExactTagAndExcludeMissingTag() async throws {
        let payload = #"""
        {
          "data": {
            "endpoints": [
              {
                "name": "Alibaba FP8",
                "provider_name": "Alibaba",
                "tag": "alibaba/fp8",
                "quantization": "fp8",
                "pricing": {
                  "prompt": "0.00000075",
                  "input_cache_read": "0.00000015",
                  "completion": "0.00000225"
                }
              },
              { "name": "Alibaba FP8 duplicate", "provider_name": "Alibaba", "tag": "alibaba/fp8", "quantization": "fp8" },
              { "name": "Alibaba Fast", "provider_name": "Alibaba", "tag": "alibaba/fast", "quantization": "fp8" },
              { "name": "Missing tag", "provider_name": "Mystery", "quantization": "fp4" }
            ]
          }
        }
        """#.data(using: .utf8)!
        let service = OpenRouterModelService(
            credentialStore: OpenRouterTestCredentialStore(),
            httpClient: OpenRouterStubHTTPClient(data: payload, statusCode: 200)
        )

        let options = try await service.getModelEndpointOptions(modelId: "z-ai/glm-5.2")

        XCTAssertEqual(options.endpoints.count, 4)
        XCTAssertEqual(options.providerEndpoints.map(\.tag), ["alibaba/fp8", "alibaba/fast"])
        XCTAssertEqual(options.quantizations, ["fp8"])
        XCTAssertEqual(options.providerEndpoints.first?.promptPricePerMillion, 0.75)
        XCTAssertEqual(options.providerEndpoints.first?.cachedInputPricePerMillion, 0.15)
        XCTAssertEqual(options.providerEndpoints.first?.completionPricePerMillion, 2.25)
    }

    func testSupersededEndpointResponseCannotOverwriteLatestCache() async throws {
        let httpClient = SupersedingOpenRouterEndpointsHTTPClient()
        let service = OpenRouterModelService(
            credentialStore: OpenRouterTestCredentialStore(),
            httpClient: httpClient
        )

        let oldRequest = Task {
            try await service.getModelEndpointOptions(modelId: "example/model", forceRefresh: true)
        }
        try? await Task.sleep(nanoseconds: 30_000_000)
        let latestRequest = Task {
            try await service.getModelEndpointOptions(modelId: "example/model", forceRefresh: true)
        }
        let latest = try await latestRequest.value
        _ = try await oldRequest.value
        let cached = try await service.getModelEndpointOptions(modelId: "example/model")
        let requestCount = await httpClient.numberOfRequests()

        XCTAssertEqual(latest.providerEndpoints.map(\.tag), ["new/fp8"])
        XCTAssertEqual(cached.providerEndpoints.map(\.tag), ["new/fp8"])
        XCTAssertEqual(requestCount, 2)
    }
}
