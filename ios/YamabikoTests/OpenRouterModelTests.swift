import XCTest
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

    func stream(_ request: HTTPRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (AsyncThrowingStream { continuation in continuation.finish() }, response)
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
}
