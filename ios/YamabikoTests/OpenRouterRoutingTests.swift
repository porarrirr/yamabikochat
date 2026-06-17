import XCTest
import GRDB
@testable import YamabikoChat

private final class OpenRouterRoutingHTTPClient: HTTPClientProtocol {
    private(set) var streamedRequests: [HTTPRequest] = []

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        let data = #"{"choices":[{"message":{"content":"ok"}}]}"#.data(using: .utf8)!
        return (data, Self.httpResponse(url: request.url, statusCode: 200))
    }

    func stream(_ request: HTTPRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        streamedRequests.append(request)
        let stream = AsyncThrowingStream<String, Error> { continuation in
            continuation.yield(#"data: {"choices":[{"delta":{"content":"ok"}}]}"#)
            continuation.yield("")
            continuation.yield("data: [DONE]")
            continuation.yield("")
            continuation.finish()
        }
        return (stream, Self.httpResponse(url: request.url, statusCode: 200))
    }

    private static func httpResponse(url: URL, statusCode: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
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

    func testSendMessageOmitsProviderRoutingWhenPreferredProvidersMismatchModel() async throws {
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
        _ = try await fixture.repository.sendMessage(
            conversationId: conversationID,
            text: "hello",
            attachments: []
        )

        let request = try XCTUnwrap(httpClient.streamedRequests.first)
        let body = try XCTUnwrap(request.body)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(root["provider"])
    }

    func testSendMessageOmitsProviderRoutingForStalePreferredSlug() async throws {
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
        _ = try await fixture.repository.sendMessage(
            conversationId: conversationID,
            text: "hello",
            attachments: []
        )

        let request = try XCTUnwrap(httpClient.streamedRequests.first)
        let body = try XCTUnwrap(request.body)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(root["provider"])
    }

    func testSendMessageOmitsProviderRoutingForStaleGoogleSlugWhenFallbacksDisabled() async throws {
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
        _ = try await fixture.repository.sendMessage(
            conversationId: conversationID,
            text: "hello",
            attachments: []
        )

        let request = try XCTUnwrap(httpClient.streamedRequests.first)
        let body = try XCTUnwrap(request.body)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(root["provider"])
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

        let request = try XCTUnwrap(httpClient.streamedRequests.first)
        let body = try XCTUnwrap(request.body)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(root["provider"])
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

        let request = try XCTUnwrap(httpClient.streamedRequests.first)
        let body = try XCTUnwrap(request.body)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let provider = try XCTUnwrap(root["provider"] as? [String: Any])
        XCTAssertEqual(provider["only"] as? [String], ["google-ai-studio"])
        XCTAssertNil(provider["order"])
        XCTAssertEqual(provider["allow_fallbacks"] as? Bool, false)
    }

    func testSendMessageKeepsCompatiblePreferredProviderInRoutingOrder() async throws {
        let model = liquidModel
        let httpClient = OpenRouterRoutingHTTPClient()
        let fixture = try makeFixture(httpClient: httpClient) { settings in
            settings.apiProvider = "OPENROUTER"
            settings.defaultModel = model.id
            settings.preferredProvidersJSON = #"["liquid"]"#
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

        let request = try XCTUnwrap(httpClient.streamedRequests.first)
        let body = try XCTUnwrap(request.body)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let provider = try XCTUnwrap(root["provider"] as? [String: Any])
        XCTAssertEqual(provider["order"] as? [String], ["liquid"])
        XCTAssertNil(provider["only"])
    }

    func testSendMessageOmitsStalePreferredProviderWhenModelAvailabilityUnknown() async throws {
        let model = unknownAvailabilityModel
        let httpClient = OpenRouterRoutingHTTPClient()
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
        _ = try await fixture.repository.sendMessage(
            conversationId: conversationID,
            text: "hello",
            attachments: []
        )

        let request = try XCTUnwrap(httpClient.streamedRequests.first)
        let body = try XCTUnwrap(request.body)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertNil(root["provider"])
    }

    func testSendMessageUsesOnlyProviderWhenFallbacksDisabledAndSingleMatch() async throws {
        let model = liquidModel
        let httpClient = OpenRouterRoutingHTTPClient()
        let fixture = try makeFixture(httpClient: httpClient) { settings in
            settings.apiProvider = "OPENROUTER"
            settings.defaultModel = model.id
            settings.preferredProvidersJSON = #"["liquid"]"#
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

        let request = try XCTUnwrap(httpClient.streamedRequests.first)
        let body = try XCTUnwrap(request.body)
        let root = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let provider = try XCTUnwrap(root["provider"] as? [String: Any])
        XCTAssertEqual(provider["only"] as? [String], ["liquid"])
        XCTAssertNil(provider["order"])
    }

    @MainActor
    func testReconcileOpenRouterPreferredProvidersClearsIncompatibleSlugWithoutAutoSelecting() throws {
        let fixture = try makeFixture()
        let viewModel = SettingsViewModel()
        viewModel.bind(repository: fixture.repository, credentialStore: fixture.credentials)

        viewModel.openRouterModels = [liquidModel]
        viewModel.settings.apiProvider = "OPENROUTER"
        viewModel.settings.setPreferredProvidersList(["deepseek"])

        viewModel.reconcileOpenRouterPreferredProviders(forModelId: liquidModel.id)

        XCTAssertEqual(viewModel.settings.preferredProvidersList(), [])
    }

    private func makeFixture(
        httpClient: HTTPClientProtocol = OpenRouterRoutingHTTPClient(),
        configureSettings: ((inout AppSettings) -> Void)? = nil
    ) throws -> (
        repository: ChatRepository,
        modelService: OpenRouterModelService,
        credentials: TestCredentialStore
    ) {
        let dbQueue = try DatabaseQueue()
        try AppDatabase.migrator.migrate(dbQueue)

        let settings = SettingsRepository(dbQueue: dbQueue)
        let conversations = ConversationRepository(dbQueue: dbQueue)
        let credentials = TestCredentialStore()
        let modelService = OpenRouterModelService(credentialStore: credentials, httpClient: httpClient)
        let providers = ProviderGateway(
            settingsRepository: settings,
            credentialStore: credentials,
            httpClient: httpClient
        )
        let codexAuth = CodexAuthRepository(credentialStore: credentials)

        if configureSettings != nil {
            var current = try settings.load()
            configureSettings?(&current)
            try settings.save(current)
        }

        let repository = ChatRepository(
            conversations: conversations,
            settings: settings,
            providers: providers,
            credentialStore: credentials,
            modelService: modelService,
            codexAuthRepository: codexAuth,
            pricingRepository: NoopPricingRepository()
        )
        return (repository, modelService, credentials)
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
