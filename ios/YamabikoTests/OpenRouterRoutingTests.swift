import XCTest
import GRDB
@testable import YamabikoChat

private final class OpenRouterRoutingHTTPClient: HTTPClientProtocol {
    private let failingEndpointPathFragments: [String]

    init(failingEndpointPathFragments: [String] = []) {
        self.failingEndpointPathFragments = failingEndpointPathFragments
    }

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        if request.url.path.hasSuffix("/endpoints") {
            if failingEndpointPathFragments.contains(where: { request.url.path.contains($0) }) {
                let data = #"{"error":"endpoint catalog unavailable"}"#.data(using: .utf8)!
                return (data, Self.httpResponse(url: request.url, statusCode: 503))
            }
            let data = #"""
            {
              "data": {
                "endpoints": [
                  { "name": "Liquid FP8", "provider_name": "Liquid", "tag": "liquid/fp8", "quantization": "fp8" },
                  { "name": "Google AI Studio", "provider_name": "Google AI Studio", "tag": "google-ai-studio", "quantization": "fp16" },
                  { "name": "Open Inference", "provider_name": "Open Inference", "tag": "open-inference", "quantization": "fp16" },
                  { "name": "Novita FP8", "provider_name": "Novita", "tag": "novita/fp8", "quantization": "fp8" },
                  { "name": "Z.AI FP8", "provider_name": "Z.AI", "tag": "z-ai/fp8", "quantization": "fp8" }
                ]
              }
            }
            """#.data(using: .utf8)!
            return (data, Self.httpResponse(url: request.url, statusCode: 200))
        }
        let data = #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!
        return (data, Self.httpResponse(url: request.url, statusCode: 200))
    }

    private static func httpResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
    }
}

private actor OpenRouterEndpointGenerationHTTPClient: HTTPClientProtocol {
    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url.path
        let data: Data
        if path == "/api/v1/models" {
            data = #"""
            {"data":[
              {"id":"example/old","name":"Old","pricing":{"prompt":"0","completion":"0"}},
              {"id":"example/new","name":"New","pricing":{"prompt":"0","completion":"0"}}
            ]}
            """#.data(using: .utf8)!
        } else if path.hasSuffix("/example/old/endpoints") {
            await delayIgnoringCancellation(nanoseconds: 200_000_000)
            data = endpointPayload(tag: "old/fp8", provider: "Old")
        } else if path.hasSuffix("/example/new/endpoints") {
            await delayIgnoringCancellation(nanoseconds: 20_000_000)
            data = endpointPayload(tag: "new/fp8", provider: "New")
        } else {
            data = #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!
        }
        return (data, HTTPURLResponse(url: request.url, statusCode: 200, httpVersion: nil, headerFields: nil)!)
    }

    private func endpointPayload(tag: String, provider: String) -> Data {
        #"{"data":{"endpoints":[{"name":"\#(provider)","provider_name":"\#(provider)","tag":"\#(tag)","quantization":"fp8"}]}}"#
            .data(using: .utf8)!
    }

    private func delayIgnoringCancellation(nanoseconds: UInt64) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + .nanoseconds(Int(nanoseconds))) {
                continuation.resume()
            }
        }
    }
}

private final class TestCredentialStore: SecureCredentialStore {
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

final class OpenRouterRoutingTests: XCTestCase {
    private let liquidModel = SimpleModel(
        id: "liquid/lfm-2.5-1.2b-thinking:free",
        name: "LFM 2.5 Thinking (free)",
        provider: "liquid",
        topProvider: "liquid",
        contextLength: 32_768,
        promptPricePerMillion: 0,
        completionPricePerMillion: 0,
        isFree: true,
        availableProviders: ["liquid"],
        availableQuantizations: []
    )

    private let unknownAvailabilityModel = SimpleModel(
        id: "openrouter/free",
        name: "Free Models Router",
        provider: "openrouter",
        topProvider: nil,
        contextLength: 32_768,
        promptPricePerMillion: 0,
        completionPricePerMillion: 0,
        isFree: true,
        availableProviders: [],
        availableQuantizations: []
    )

    private let gemmaModel = SimpleModel(
        id: "google/gemma-4-31b-it:free",
        name: "Gemma 4 31B",
        provider: "google",
        topProvider: "google-ai-studio",
        contextLength: 32_768,
        promptPricePerMillion: 0,
        completionPricePerMillion: 0,
        isFree: true,
        availableProviders: ["google-ai-studio", "open-inference"],
        availableQuantizations: []
    )

    func testSendMessageFailsWhenPreferredEndpointTagDoesNotExist() async throws {
        let model = liquidModel
        let httpClient = OpenRouterRoutingHTTPClient()
        let fixture = try makeFixture(httpClient: httpClient) { settings in
            settings.apiProvider = "OPENROUTER"
            settings.defaultModel = model.id
            settings.preferredProvidersJSON = #"["deepseek"]"#
            settings.isStreamingEnabled = true
        }
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)
        fixture.modelService.replaceCachedModels([model])

        let conversationID = try fixture.repository.createConversation(title: "Routing")
        do {
            _ = try await fixture.repository.sendMessage(
                conversationId: conversationID,
                text: "hello",
                attachments: []
            )
            XCTFail("Expected unavailable endpoint tag to fail explicitly")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("deepseek"))
        }
        XCTAssertTrue(fixture.runtime.calls.isEmpty)
    }

    func testSendMessageFailsForLegacyBaseProviderSlug() async throws {
        let model = SimpleModel(
            id: "google/gemma-4-26b-a4b-it:free",
            name: "Gemma 4 26B",
            provider: "google",
            topProvider: "google-ai-studio",
            contextLength: 32_768,
            promptPricePerMillion: 0,
            completionPricePerMillion: 0,
            isFree: true,
            availableProviders: ["google-ai-studio"],
            availableQuantizations: []
        )
        let httpClient = OpenRouterRoutingHTTPClient()
        let fixture = try makeFixture(httpClient: httpClient) { settings in
            settings.apiProvider = "OPENROUTER"
            settings.defaultModel = model.id
            settings.preferredProvidersJSON = #"["google"]"#
            settings.allowFallbacks = false
            settings.isStreamingEnabled = true
        }
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)
        fixture.modelService.replaceCachedModels([model])

        let conversationID = try fixture.repository.createConversation(title: "Routing")
        do {
            _ = try await fixture.repository.sendMessage(
                conversationId: conversationID,
                text: "hello",
                attachments: []
            )
            XCTFail("Expected legacy base provider slug to fail explicitly")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("google"))
        }
        XCTAssertTrue(fixture.runtime.calls.isEmpty)
    }

    func testSendMessageFailsForStaleGoogleSlugWhenFallbacksDisabled() async throws {
        let model = gemmaModel
        let httpClient = OpenRouterRoutingHTTPClient()
        let fixture = try makeFixture(httpClient: httpClient) { settings in
            settings.apiProvider = "OPENROUTER"
            settings.defaultModel = model.id
            settings.preferredProvidersJSON = #"["google"]"#
            settings.allowFallbacks = false
            settings.isStreamingEnabled = true
        }
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)
        fixture.modelService.replaceCachedModels([model])

        let conversationID = try fixture.repository.createConversation(title: "Routing")
        do {
            _ = try await fixture.repository.sendMessage(
                conversationId: conversationID,
                text: "hello",
                attachments: []
            )
            XCTFail("Expected stale provider slug to fail explicitly")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("google"))
        }
        XCTAssertTrue(fixture.runtime.calls.isEmpty)
    }

    func testSendMessageOmitsProviderRoutingWhenPreferredProvidersEmpty() async throws {
        let model = gemmaModel
        let httpClient = OpenRouterRoutingHTTPClient()
        let fixture = try makeFixture(httpClient: httpClient) { settings in
            settings.apiProvider = "OPENROUTER"
            settings.defaultModel = model.id
            settings.preferredProvidersJSON = "[]"
            settings.allowFallbacks = false
            settings.isStreamingEnabled = true
        }
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)
        fixture.modelService.replaceCachedModels([model])

        let conversationID = try fixture.repository.createConversation(title: "Routing")
        _ = try await fixture.repository.sendMessage(
            conversationId: conversationID,
            text: "hello",
            attachments: []
        )

        XCTAssertNil(fixture.runtime.calls.first?.request.provider)
    }

    func testSendMessageUsesOnlyWhenExplicitCompatibleProviderSelected() async throws {
        let model = gemmaModel
        let httpClient = OpenRouterRoutingHTTPClient()
        let fixture = try makeFixture(httpClient: httpClient) { settings in
            settings.apiProvider = "OPENROUTER"
            settings.defaultModel = model.id
            settings.preferredProvidersJSON = #"["google-ai-studio"]"#
            settings.allowFallbacks = false
            settings.isStreamingEnabled = true
        }
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)
        fixture.modelService.replaceCachedModels([model])

        let conversationID = try fixture.repository.createConversation(title: "Routing")
        _ = try await fixture.repository.sendMessage(
            conversationId: conversationID,
            text: "hello",
            attachments: []
        )

        let provider = try XCTUnwrap(fixture.runtime.calls.first?.request.provider)
        XCTAssertEqual(provider.only, ["google-ai-studio"])
        XCTAssertNil(provider.order)
        XCTAssertEqual(provider.allowFallbacks, false)
    }

    func testSendMessageKeepsCompatiblePreferredProviderInRoutingOrder() async throws {
        let model = liquidModel
        let httpClient = OpenRouterRoutingHTTPClient()
        let fixture = try makeFixture(httpClient: httpClient) { settings in
            settings.apiProvider = "OPENROUTER"
            settings.defaultModel = model.id
            settings.preferredProvidersJSON = #"["liquid/fp8"]"#
            settings.allowFallbacks = true
            settings.isStreamingEnabled = true
        }
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)
        fixture.modelService.replaceCachedModels([model])

        let conversationID = try fixture.repository.createConversation(title: "Routing")
        _ = try await fixture.repository.sendMessage(
            conversationId: conversationID,
            text: "hello",
            attachments: []
        )

        let provider = try XCTUnwrap(fixture.runtime.calls.first?.request.provider)
        XCTAssertEqual(provider.order, ["liquid/fp8"])
        XCTAssertNil(provider.only)
    }

    func testSendMessageFailsWhenEndpointCapabilitiesCannotBeFetched() async throws {
        let model = unknownAvailabilityModel
        let httpClient = OpenRouterRoutingHTTPClient(
            failingEndpointPathFragments: ["/models/openrouter/free/endpoints"]
        )
        let fixture = try makeFixture(httpClient: httpClient) { settings in
            settings.apiProvider = "OPENROUTER"
            settings.defaultModel = model.id
            settings.preferredProvidersJSON = #"["deepseek"]"#
            settings.allowFallbacks = false
            settings.isStreamingEnabled = true
        }
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)
        fixture.modelService.replaceCachedModels([model])

        let conversationID = try fixture.repository.createConversation(title: "Routing")
        do {
            _ = try await fixture.repository.sendMessage(
                conversationId: conversationID,
                text: "hello",
                attachments: []
            )
            XCTFail("Expected endpoint capability acquisition failure")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("could not be validated"))
        }
        XCTAssertTrue(fixture.runtime.calls.isEmpty)
    }

    func testSendMessageUsesOnlyProviderWhenFallbacksDisabledAndSingleMatch() async throws {
        let model = liquidModel
        let httpClient = OpenRouterRoutingHTTPClient()
        let fixture = try makeFixture(httpClient: httpClient) { settings in
            settings.apiProvider = "OPENROUTER"
            settings.defaultModel = model.id
            settings.preferredProvidersJSON = #"["liquid/fp8"]"#
            settings.allowFallbacks = false
            settings.isStreamingEnabled = true
        }
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)
        fixture.modelService.replaceCachedModels([model])

        let conversationID = try fixture.repository.createConversation(title: "Routing")
        _ = try await fixture.repository.sendMessage(
            conversationId: conversationID,
            text: "hello",
            attachments: []
        )

        let provider = try XCTUnwrap(fixture.runtime.calls.first?.request.provider)
        XCTAssertEqual(provider.only, ["liquid/fp8"])
        XCTAssertNil(provider.order)
    }

    func testSendMessagePreservesExactEndpointTagAndXHighEffort() async throws {
        let model = SimpleModel(
            id: "z-ai/glm-5.2",
            name: "GLM 5.2",
            provider: "z-ai",
            topProvider: nil,
            contextLength: 131_072,
            promptPricePerMillion: 1,
            completionPricePerMillion: 2,
            isFree: false,
            availableProviders: [],
            availableQuantizations: [],
            reasoning: OpenRouterReasoningCapabilities(
                supportedEfforts: ["xhigh", "high"],
                exposesEffortSelection: true,
                defaultEffort: "high",
                defaultEnabled: true,
                supportsMaxTokens: true,
                mandatory: false
            )
        )
        let httpClient = OpenRouterRoutingHTTPClient()
        let fixture = try makeFixture(httpClient: httpClient) { settings in
            settings.apiProvider = "OPENROUTER"
            settings.defaultModel = model.id
            settings.openRouterThinkingEnabled = true
            settings.openRouterReasoningMode = "effort"
            settings.openRouterReasoningEffort = "xhigh"
            settings.preferredProvidersJSON = #"["novita/fp8"]"#
            settings.allowFallbacks = true
            settings.isStreamingEnabled = true
        }
        try fixture.credentials.setCredential("openrouter-key", for: .openRouter)
        fixture.modelService.replaceCachedModels([model])

        let conversationID = try fixture.repository.createConversation(title: "Routing")
        _ = try await fixture.repository.sendMessage(
            conversationId: conversationID,
            text: "hello",
            attachments: []
        )

        let request = try XCTUnwrap(fixture.runtime.calls.first?.request)
        XCTAssertEqual(request.provider?.order, ["novita/fp8"])
        XCTAssertEqual(request.thinking?.effort, "xhigh")
    }

    @MainActor
    func testReconcileOpenRouterPreferredProvidersClearsIncompatibleSlugWithoutAutoSelecting() throws {
        let fixture = try makeFixture()
        let viewModel = SettingsViewModel()
        viewModel.bind(repository: fixture.repository, credentialStore: fixture.credentials)

        viewModel.openRouterModels = [liquidModel]
        viewModel.settings.apiProvider = "OPENROUTER"
        viewModel.settings.setPreferredProvidersList(["deepseek"])
        viewModel.openRouterEndpointModelId = liquidModel.id
        viewModel.openRouterEndpointOptions = [
            OpenRouterEndpointOption(
                tag: "liquid/fp8",
                providerName: "Liquid",
                quantization: "fp8",
                supportedParameters: [],
                status: 0
            )
        ]

        viewModel.reconcileOpenRouterPreferredProviders(forModelId: liquidModel.id)

        XCTAssertEqual(viewModel.settings.preferredProvidersList(), [])
    }

    @MainActor
    func testReconcileGLMReasoningEffortUsesModelDefault() {
        let model = SimpleModel(
            id: "z-ai/glm-5.2",
            name: "GLM 5.2",
            provider: "z-ai",
            topProvider: nil,
            contextLength: 131_072,
            promptPricePerMillion: 1,
            completionPricePerMillion: 2,
            isFree: false,
            availableProviders: [],
            availableQuantizations: [],
            reasoning: OpenRouterReasoningCapabilities(
                supportedEfforts: ["xhigh", "high"],
                exposesEffortSelection: true,
                defaultEffort: "high",
                defaultEnabled: true,
                supportsMaxTokens: true,
                mandatory: false
            )
        )
        let viewModel = SettingsViewModel()
        viewModel.settings.apiProvider = "OPENROUTER"
        viewModel.settings.defaultModel = model.id
        viewModel.settings.openRouterThinkingEnabled = true
        viewModel.settings.openRouterReasoningMode = "effort"
        viewModel.settings.openRouterReasoningEffort = "medium"
        viewModel.openRouterModels = [model]

        viewModel.reconcileOpenRouterReasoning(forModelId: model.id)

        XCTAssertEqual(viewModel.openRouterReasoningEfforts(forModelId: model.id), ["xhigh", "high"])
        XCTAssertEqual(viewModel.openRouterReasoningModes(forModelId: model.id), ["auto", "effort", "budget"])
        XCTAssertEqual(viewModel.settings.openRouterReasoningEffort, "high")
    }

    @MainActor
    func testStaleEndpointResponseCannotOverwriteLatestModelOptions() async throws {
        let httpClient = OpenRouterEndpointGenerationHTTPClient()
        let fixture = try makeFixture(httpClient: httpClient) { settings in
            settings.apiProvider = "OPENAI"
            settings.defaultModel = "gpt-4.1-mini"
        }
        let viewModel = SettingsViewModel()
        viewModel.bind(repository: fixture.repository, credentialStore: fixture.credentials)

        await viewModel.refreshOpenRouterModels(force: true)
        XCTAssertEqual(viewModel.openRouterModels.count, 2)

        viewModel.settings.apiProvider = "OPENROUTER"
        viewModel.settings.defaultModel = "example/old"
        let oldRequest = Task {
            await viewModel.refreshOpenRouterEndpointOptions(forModelId: "example/old", force: true)
        }
        try? await Task.sleep(nanoseconds: 30_000_000)
        viewModel.settings.defaultModel = "example/new"
        let latestRequest = Task {
            await viewModel.refreshOpenRouterEndpointOptions(forModelId: "example/new", force: true)
        }

        await latestRequest.value
        await oldRequest.value

        XCTAssertEqual(viewModel.openRouterEndpointModelId, "example/new")
        XCTAssertEqual(viewModel.openRouterEndpointOptions.map(\.tag), ["new/fp8"])
        XCTAssertNil(viewModel.openRouterEndpointsError)
        XCTAssertFalse(viewModel.openRouterEndpointsLoading)
    }

    private func makeFixture(
        httpClient: HTTPClientProtocol = OpenRouterRoutingHTTPClient(),
        configureSettings: ((inout AppSettings) -> Void)? = nil
    ) throws -> (
        repository: ChatRepository,
        modelService: OpenRouterModelService,
        credentials: TestCredentialStore,
        runtime: PiStreamSpy
    ) {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)

        let settings = SettingsRepository(dbQueue: dbQueue)
        let conversations = ConversationRepository(dbQueue: dbQueue)
        let credentials = TestCredentialStore()
        let runtime = PiStreamSpy()
        let modelService = OpenRouterModelService(credentialStore: credentials, httpClient: httpClient)

        if configureSettings != nil {
            var current = try settings.load()
            configureSettings?(&current)
            try settings.save(current)
        }

        let repository = ChatRepositoryTestSupport.makeRepository(
            dbQueue: dbQueue,
            settings: settings,
            conversations: conversations,
            credentials: credentials,
            piStream: runtime.stream,
            modelService: modelService,
            pricingRepository: NoopPricingRepository()
        )
        return (repository, modelService, credentials, runtime)
    }
}

private struct NoopPricingRepository: LiteLlmPricingEstimating {
    func estimateCostUsd(
        provider: String,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cachedInputTokens: Int?,
        cacheCreationInputTokens: Int?,
        reasoningTokens: Int?
    ) async -> Double? {
        nil
    }

    func modelSupportsVision(provider: String, model: String) async -> Bool {
        false
    }
}
