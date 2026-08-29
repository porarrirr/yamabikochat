import XCTest
import GRDB
@testable import YamabikoChat

private final class PiGatewayCredentialStore: SecureCredentialStore {
    private var values: [String: String] = [:]

    func saveSecret(_ value: String?, key: String) throws {
        values[key] = value
    }

    func readSecret(key: String) throws -> String? {
        values[key]
    }

    func deleteSecret(key: String) throws {
        values.removeValue(forKey: key)
    }
}

private struct PiGatewayHTTPClient: HTTPClientProtocol {
    let data: Data

    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        (
            data,
            HTTPURLResponse(url: request.url, statusCode: 200, httpVersion: nil, headerFields: nil)!
        )
    }
}

private actor ScriptedPiRuntimeHealthClient: PiRuntimeHealthClient {
    private var failuresRemaining: Int
    private let responseDelay: Duration
    private var requestCount = 0

    init(failures: Int = 0, responseDelay: Duration = .zero) {
        failuresRemaining = failures
        self.responseDelay = responseDelay
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requestCount += 1
        if responseDelay != .zero {
            try await Task.sleep(for: responseDelay)
        }
        if failuresRemaining > 0 {
            failuresRemaining -= 1
            throw URLError(.cannotConnectToHost)
        }
        let data = Data(#"{"ok":true,"contractVersion":2}"#.utf8)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: nil,
            headerFields: nil
        )!
        return (data, response)
    }

    func count() -> Int {
        requestCount
    }
}

private final class ThrowingPiStreamSpy: @unchecked Sendable {
    typealias Handler = @Sendable (
        ProviderRequest,
        PiAgentConfiguration
    ) -> AsyncThrowingStream<ProviderStreamEvent, Error>

    private let lock = NSLock()
    private var recordedCalls: [PiStreamSpy.Call] = []
    private let handler: Handler

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    var calls: [PiStreamSpy.Call] {
        lock.withLock { recordedCalls }
    }

    var stream: PiAgentStream {
        { [self] request, configuration, _ in
            lock.withLock {
                recordedCalls.append(.init(request: request, configuration: configuration))
            }
            return handler(request, configuration)
        }
    }
}

final class PiAgentGatewayTests: XCTestCase {
    func testAttachmentFileURLResolvesFilesystemPath() {
        let path = "/tmp/Yamabiko Chat/photo.png"

        let resolved = PiAgentRuntime.attachmentFileURL(from: path)

        XCTAssertEqual(resolved.path, path)
    }

    func testAttachmentFileURLResolvesPersistedFileURL() {
        let fileURL = URL(fileURLWithPath: "/tmp/Yamabiko Chat/photo.png")

        let resolved = PiAgentRuntime.attachmentFileURL(from: fileURL.absoluteString)

        XCTAssertEqual(resolved.path, fileURL.path)
    }

    func testBundledPiRuntimeStarts() async throws {
        try await PiAgentRuntime.shared.verifyReady()
    }

    func testBundledPiRuntimeRemainsReachableThroughForegroundSynchronization() async throws {
        try await PiAgentRuntime.shared.verifyReady()
        try await PiAgentRuntime.shared.prepareForForeground()
        try await PiAgentRuntime.shared.verifyReady()
    }

    func testForegroundAndRequestReadinessShareOneHealthCheck() async throws {
        let healthClient = ScriptedPiRuntimeHealthClient(responseDelay: .milliseconds(100))
        let runtime = PiAgentRuntime(
            endpoint: URL(string: "http://127.0.0.1:54321/")!,
            token: "test-token",
            readiness: PiRuntimeReadinessConfiguration(
                startupTimeout: .seconds(1),
                resumeTimeout: .seconds(1),
                retryDelay: .zero,
                requestTimeout: 1
            ),
            healthClient: healthClient
        )

        async let foreground: Void = runtime.prepareForForeground()
        async let request: Void = runtime.verifyReady()
        _ = try await (foreground, request)

        let requestCount = await healthClient.count()
        XCTAssertEqual(requestCount, 1)
    }

    func testReadinessRetriesTransientConnectionFailures() async throws {
        let healthClient = ScriptedPiRuntimeHealthClient(failures: 3)
        let runtime = PiAgentRuntime(
            endpoint: URL(string: "http://127.0.0.1:54321/")!,
            token: "test-token",
            readiness: PiRuntimeReadinessConfiguration(
                startupTimeout: .seconds(1),
                resumeTimeout: .seconds(1),
                retryDelay: .zero,
                requestTimeout: 1
            ),
            healthClient: healthClient
        )

        try await runtime.verifyReady()

        let requestCount = await healthClient.count()
        XCTAssertEqual(requestCount, 4)
    }

    func testResumeReadinessUsesElapsedTimeInsteadOfAFragileAttemptLimit() async throws {
        let healthClient = ScriptedPiRuntimeHealthClient(failures: 25)
        let runtime = PiAgentRuntime(
            endpoint: URL(string: "http://127.0.0.1:54321/")!,
            token: "test-token",
            readiness: PiRuntimeReadinessConfiguration(
                startupTimeout: .seconds(1),
                resumeTimeout: .seconds(1),
                retryDelay: .milliseconds(1),
                requestTimeout: 1
            ),
            healthClient: healthClient
        )

        try await runtime.prepareForForeground()

        let requestCount = await healthClient.count()
        XCTAssertEqual(requestCount, 26)
    }

    func testBundledPiRuntimeResolvesCurrentOpenCodeAndOpenRouterModels() async throws {
        let resolutions = try await PiAgentRuntime.shared.resolveModels([
            PiAgentConfiguration(
                provider: "opencode",
                model: "nemotron-3.5-lightning-free"
            ),
            PiAgentConfiguration(
                provider: "opencode",
                model: "muse-spark-1.2-contributor-free",
                catalogContract: PiCatalogModelContract(
                    npm: "@ai-sdk/openai",
                    api: "https://opencode.ai/zen/v1",
                    toolCall: true,
                    provenance: "model",
                    name: "Muse Spark 1.2 Free",
                    reasoning: true,
                    input: ["text", "image", "video", "pdf", "audio"],
                    contextWindow: 1_048_576,
                    maxTokens: 131_072
                )
            ),
            PiAgentConfiguration(
                provider: "openrouter",
                model: "stealth/ox-alpha",
                catalogContract: PiCatalogModelContract(
                    npm: "@openrouter/ai-sdk-provider",
                    api: "https://openrouter.ai/api/v1",
                    toolCall: true,
                    provenance: "official_provider_catalog",
                    name: "Ox Alpha",
                    reasoning: true,
                    input: ["text", "image", "video"],
                    contextWindow: 1_048_576,
                    maxTokens: 131_072
                )
            )
        ])

        XCTAssertEqual(resolutions.map(\.supported), [true, true, true])
        XCTAssertEqual(resolutions.map(\.api), ["openai-completions", "openai-responses", "openai-completions"])
        XCTAssertEqual(resolutions.map(\.source), ["pi_builtin", "model", "official_provider_catalog"])
    }

    func testBundledPiResolvesFreshCodexCredential() async throws {
        let credential = JSONValue.object([
            "type": .string("oauth"),
            "access": .string("pi-access-token"),
            "refresh": .string("pi-refresh-token"),
            "expires": .number(4_102_444_800_000),
            "accountId": .string("acc_pi")
        ])
        let resolution = try await PiAgentRuntime.shared.resolveOAuth(
            provider: .codex,
            credentialJSON: try PiAgentRuntime.credentialJSONString(credential),
            force: false
        )

        XCTAssertEqual(resolution.accessToken, "pi-access-token")
        XCTAssertEqual(resolution.accountId, "acc_pi")
    }

    func testNetworkProvidersFailBeforeStartingPiWhenCredentialIsMissing() async throws {
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database)
        let gateway = ProviderGateway(
            settingsRepository: SettingsRepository(dbQueue: database),
            credentialStore: PiGatewayCredentialStore()
        )

        for provider in [LLMProvider.gemini, .openRouter, .openAI, .miniMax, .zai, .alibabaCodingPlan, .openCodeGo] {
            let request = ProviderRequest(
                model: provider == .openCodeGo ? OpenCodeGoModelCatalog.defaultModel : "test-model",
                messages: [ProviderRequestMessage(role: "user", content: "hello")]
            )
            do {
                _ = try await gateway.stream(request: request, provider: provider)
                XCTFail("Expected missing credential for \(provider.rawValue)")
            } catch let ProviderClientError.missingCredential(value) {
                XCTAssertFalse(value.isEmpty)
            }
        }
    }

    func testProvidersWithoutAnExplicitPiContractAreRejectedBeforeCredentialLookup() async throws {
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database)
        let gateway = ProviderGateway(
            settingsRepository: SettingsRepository(dbQueue: database),
            credentialStore: PiGatewayCredentialStore()
        )

        for provider in [LLMProvider.openAICompat, .clinePass] {
            do {
                _ = try await gateway.stream(
                    request: ProviderRequest(
                        model: "test-model",
                        messages: [ProviderRequestMessage(role: "user", content: "hello")]
                    ),
                    provider: provider
                )
                XCTFail("Expected unsupported model for \(provider.rawValue)")
            } catch let ProviderClientError.unsupportedModel(actualProvider, model) {
                XCTAssertEqual(actualProvider, provider.rawValue)
                XCTAssertEqual(model, "test-model")
            }
        }
    }

    func testUnknownProviderIsRejectedWithoutFallback() async throws {
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database)
        let gateway = ProviderGateway(
            settingsRepository: SettingsRepository(dbQueue: database),
            credentialStore: PiGatewayCredentialStore()
        )

        do {
            _ = try await gateway.stream(
                request: ProviderRequest(
                    model: "test-model",
                    messages: [ProviderRequestMessage(role: "user", content: "hello")]
                ),
                providerID: "NOT_A_PROVIDER"
            )
            XCTFail("Expected an unknown-provider error")
        } catch let ProviderClientError.parseFailure(message) {
            XCTAssertTrue(message.contains("Unknown provider"))
        }
    }

    func testOpenRouterPassesYamabikoAttributionHeadersToPi() async throws {
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database)
        let credentials = PiGatewayCredentialStore()
        try credentials.setCredential("test-openrouter-key", for: .openRouter)
        let pi = PiStreamSpy()
        let gateway = ProviderGateway(
            settingsRepository: SettingsRepository(dbQueue: database),
            credentialStore: credentials,
            piStream: pi.stream
        )

        _ = try await gateway.stream(
            request: ProviderRequest(
                model: "nvidia/nemotron-nano-9b-v2:free",
                messages: [ProviderRequestMessage(role: "user", content: "hello")]
            ),
            provider: .openRouter
        )

        let headers = try XCTUnwrap(pi.calls.first?.configuration.headers)
        XCTAssertEqual(
            headers["HTTP-Referer"],
            "https://apps.apple.com/jp/app/yamabikochat-ai%E3%83%81%E3%83%A3%E3%83%83%E3%83%88/id6771687018"
        )
        XCTAssertEqual(headers["X-OpenRouter-Title"], "YamabikoChat iOS")
        XCTAssertEqual(headers["X-Title"], "YamabikoChat iOS")
    }

    func testOpenRouterPassesOfficialDynamicModelContractToPi() async throws {
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database)
        let credentials = PiGatewayCredentialStore()
        try credentials.setCredential("test-openrouter-key", for: .openRouter)
        let payload = #"""
        {"data":[{
          "id":"stealth/ox-alpha",
          "name":"Ox Alpha",
          "context_length":1048576,
          "architecture":{"input_modalities":["text","image","video"],"output_modalities":["text"]},
          "pricing":{"prompt":"0","completion":"0"},
          "top_provider":{"max_completion_tokens":131072},
          "supported_parameters":["reasoning","tools"],
          "reasoning":{"mandatory":true}
        }]}
        """#.data(using: .utf8)!
        let modelService = OpenRouterModelService(
            credentialStore: credentials,
            httpClient: PiGatewayHTTPClient(data: payload)
        )
        let pi = PiStreamSpy()
        let gateway = ProviderGateway(
            settingsRepository: SettingsRepository(dbQueue: database),
            credentialStore: credentials,
            openRouterModelService: modelService,
            piStream: pi.stream
        )

        _ = try await gateway.stream(
            request: ProviderRequest(
                model: "stealth/ox-alpha",
                messages: [ProviderRequestMessage(role: "user", content: "hello")]
            ),
            provider: .openRouter
        )

        let contract = try XCTUnwrap(pi.calls.first?.configuration.catalogContract)
        XCTAssertEqual(contract.npm, "@openrouter/ai-sdk-provider")
        XCTAssertEqual(contract.provenance, "official_provider_catalog")
        XCTAssertEqual(contract.name, "Ox Alpha")
        XCTAssertEqual(contract.input, ["text", "image", "video"])
        XCTAssertEqual(contract.contextWindow, 1_048_576)
        XCTAssertEqual(contract.maxTokens, 131_072)
        XCTAssertEqual(contract.toolCall, true)
    }

    func testAsynchronousPiStreamFailureIsWrittenToDiagnostics() async throws {
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database)
        let credentials = PiGatewayCredentialStore()
        try credentials.setCredential("test-openai-key", for: .openAI)
        let marker = "async-pi-failure-\(UUID().uuidString)"
        let gateway = ProviderGateway(
            settingsRepository: SettingsRepository(dbQueue: database),
            credentialStore: credentials,
            piStream: { _, _, _ in
                AsyncThrowingStream { continuation in
                    continuation.finish(throwing: ProviderClientError.parseFailure(marker))
                }
            }
        )

        do {
            _ = try await gateway.generate(
                request: ProviderRequest(
                    model: "gpt-4.1-mini",
                    messages: [ProviderRequestMessage(role: "user", content: "hello")]
                ),
                provider: .openAI
            )
            XCTFail("Expected asynchronous Pi failure")
        } catch {
            XCTAssertTrue(DiagnosticsLogger.read().contains(marker))
        }
    }

    func testGeminiThinkingLevelIsPassedThroughPiConfiguration() async throws {
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database)
        let credentials = PiGatewayCredentialStore()
        try credentials.setCredential("test-gemini-key", for: .gemini)
        let pi = PiStreamSpy()
        let gateway = ProviderGateway(
            settingsRepository: SettingsRepository(dbQueue: database),
            credentialStore: credentials,
            piStream: pi.stream
        )

        _ = try await gateway.stream(
            request: ProviderRequest(
                model: "gemini-3.1-pro-preview",
                messages: [ProviderRequestMessage(role: "user", content: "hello")],
                thinking: ProviderThinkingConfig(
                    enabled: nil,
                    budget: nil,
                    effort: nil,
                    includeThoughts: true,
                    exclude: nil
                ),
                metadata: [
                    "geminiThinkingLevel": "high",
                    "contextWindow": "1048576"
                ]
            ),
            provider: .gemini
        )

        let configuration = try XCTUnwrap(pi.calls.first?.configuration)
        XCTAssertEqual(configuration.provider, "google")
        XCTAssertEqual(configuration.thinkingLevel, "high")
        XCTAssertEqual(configuration.contractVersion, 2)
    }

    func testGeminiRotatesToNextModelThroughPiAfterRateLimitBeforeOutput() async throws {
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database)
        let settingsRepository = SettingsRepository(dbQueue: database)
        var settings = try settingsRepository.load()
        settings.setGeminiRotationModelsList(["gemini-2.5-flash-lite"])
        try settingsRepository.save(settings)
        let credentials = PiGatewayCredentialStore()
        try credentials.setCredential("gemini-key", for: .gemini)
        let pi = ThrowingPiStreamSpy { _, configuration in
            AsyncThrowingStream { continuation in
                continuation.yield(.answerStart)
                if configuration.model == "gemini-2.5-flash" {
                    continuation.yield(.executionSnapshot(.object(["failed": .bool(true)])))
                    continuation.finish(throwing: ProviderClientError.providerFailure(
                        statusCode: 429,
                        code: "RESOURCE_EXHAUSTED",
                        message: "quota exhausted"
                    ))
                } else {
                    continuation.yield(.textDelta("rotated"))
                    continuation.yield(.completed(ProviderResponse(text: "rotated")))
                    continuation.finish()
                }
            }
        }
        let gateway = ProviderGateway(
            settingsRepository: settingsRepository,
            credentialStore: credentials,
            piStream: pi.stream
        )

        let stream = try await gateway.stream(
            request: ProviderRequest(
                model: "gemini-2.5-flash",
                messages: [ProviderRequestMessage(role: "user", content: "hello")]
            ),
            provider: .gemini
        )
        var events: [ProviderStreamEvent] = []
        for try await event in stream {
            events.append(event)
        }

        XCTAssertEqual(pi.calls.map(\.configuration.model), ["gemini-2.5-flash", "gemini-2.5-flash-lite"])
        XCTAssertEqual(events.filter { $0 == .answerStart }.count, 1)
        XCTAssertFalse(events.contains(.executionSnapshot(.object(["failed": .bool(true)]))))
        XCTAssertTrue(events.contains(.completed(ProviderResponse(text: "rotated"))))
    }

    func testGeminiAuthFailureSkipsRemainingModelsForBadKeyAndRemembersGoodCandidate() async throws {
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database)
        let settingsRepository = SettingsRepository(dbQueue: database)
        var settings = try settingsRepository.load()
        settings.setGeminiKeyNames(["slot-a"])
        settings.setGeminiRotationModelsList(["gemini-2.5-flash-lite"])
        try settingsRepository.save(settings)
        let credentials = PiGatewayCredentialStore()
        try credentials.setCredential("bad-key", for: .gemini)
        try credentials.setGeminiAPIKey(name: "slot-a", value: "good-key")
        let pi = ThrowingPiStreamSpy { _, configuration in
            AsyncThrowingStream { continuation in
                if configuration.apiKey == "bad-key" {
                    continuation.finish(throwing: ProviderClientError.providerFailure(
                        statusCode: 401,
                        code: "UNAUTHENTICATED",
                        message: "API key not valid"
                    ))
                } else {
                    continuation.yield(.completed(ProviderResponse(text: "ok")))
                    continuation.finish()
                }
            }
        }
        let gateway = ProviderGateway(
            settingsRepository: settingsRepository,
            credentialStore: credentials,
            piStream: pi.stream
        )

        let response = try await gateway.generate(
            request: ProviderRequest(
                model: "gemini-2.5-flash",
                messages: [ProviderRequestMessage(role: "user", content: "hello")]
            ),
            provider: .gemini
        )

        XCTAssertEqual(response.text, "ok")
        XCTAssertEqual(pi.calls.map(\.configuration.apiKey), ["bad-key", "good-key"])
        XCTAssertEqual(pi.calls.map(\.configuration.model), ["gemini-2.5-flash", "gemini-2.5-flash"])

        _ = try await gateway.generate(
            request: ProviderRequest(
                model: "gemini-2.5-flash",
                messages: [ProviderRequestMessage(role: "user", content: "again")]
            ),
            provider: .gemini
        )

        XCTAssertEqual(pi.calls.map(\.configuration.apiKey), ["bad-key", "good-key", "good-key"])
        XCTAssertEqual(pi.calls.map(\.configuration.model), [
            "gemini-2.5-flash",
            "gemini-2.5-flash",
            "gemini-2.5-flash"
        ])
    }

    func testGeminiConfiguredKeyWorksWithoutDefaultCredential() async throws {
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database)
        let settingsRepository = SettingsRepository(dbQueue: database)
        var settings = try settingsRepository.load()
        settings.setGeminiKeyNames(["slot-only"])
        try settingsRepository.save(settings)
        let credentials = PiGatewayCredentialStore()
        try credentials.setGeminiAPIKey(name: "slot-only", value: "rotation-only-key")
        let pi = PiStreamSpy()
        let gateway = ProviderGateway(
            settingsRepository: settingsRepository,
            credentialStore: credentials,
            piStream: pi.stream
        )

        _ = try await gateway.stream(
            request: ProviderRequest(
                model: "gemini-2.5-flash",
                messages: [ProviderRequestMessage(role: "user", content: "hello")]
            ),
            provider: .gemini
        )

        XCTAssertEqual(pi.calls.first?.configuration.apiKey, "rotation-only-key")
    }

    func testGeminiDoesNotRotateAfterProviderOutputWasEmitted() async throws {
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database)
        let settingsRepository = SettingsRepository(dbQueue: database)
        var settings = try settingsRepository.load()
        settings.setGeminiRotationModelsList(["gemini-2.5-flash-lite"])
        try settingsRepository.save(settings)
        let credentials = PiGatewayCredentialStore()
        try credentials.setCredential("gemini-key", for: .gemini)
        let pi = ThrowingPiStreamSpy { _, _ in
            AsyncThrowingStream { continuation in
                continuation.yield(.answerStart)
                continuation.yield(.textDelta("partial"))
                continuation.finish(throwing: ProviderClientError.providerFailure(
                    statusCode: 429,
                    code: "RESOURCE_EXHAUSTED",
                    message: "quota exhausted"
                ))
            }
        }
        let gateway = ProviderGateway(
            settingsRepository: settingsRepository,
            credentialStore: credentials,
            piStream: pi.stream
        )

        let stream = try await gateway.stream(
            request: ProviderRequest(
                model: "gemini-2.5-flash",
                messages: [ProviderRequestMessage(role: "user", content: "hello")]
            ),
            provider: .gemini
        )
        var text = ""
        do {
            for try await event in stream {
                if case let .textDelta(delta) = event { text += delta }
            }
            XCTFail("Expected the committed candidate failure")
        } catch {
            XCTAssertEqual(text, "partial")
        }

        XCTAssertEqual(pi.calls.map(\.configuration.model), ["gemini-2.5-flash"])
    }

    func testGemma4ThinkingLevelIsPassedThroughPiConfiguration() async throws {
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database)
        let credentials = PiGatewayCredentialStore()
        try credentials.setCredential("test-gemini-key", for: .gemini)
        let pi = PiStreamSpy()
        let gateway = ProviderGateway(
            settingsRepository: SettingsRepository(dbQueue: database),
            credentialStore: credentials,
            piStream: pi.stream
        )

        _ = try await gateway.stream(
            request: ProviderRequest(
                model: "gemma-4-31b-it",
                messages: [ProviderRequestMessage(role: "user", content: "hello")],
                thinking: ProviderThinkingConfig(
                    enabled: nil,
                    budget: nil,
                    effort: nil,
                    includeThoughts: true,
                    exclude: nil
                ),
                metadata: ["geminiThinkingLevel": "high"]
            ),
            provider: .gemini
        )

        let configuration = try XCTUnwrap(pi.calls.first?.configuration)
        XCTAssertEqual(configuration.provider, "google")
        XCTAssertEqual(configuration.model, "gemma-4-31b-it")
        XCTAssertEqual(configuration.thinkingLevel, "high")
    }

    func testSuperGrokUsesPiGrokResponsesProvider() async throws {
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database)
        let credentials = PiGatewayCredentialStore()
        try credentials.saveSecret(
            try PiAgentRuntime.credentialJSONString(oauthResolution(accountID: nil).credential),
            key: "pi_oauth_supergrok_v1"
        )
        let auth = SuperGrokAuthRepository(
            credentialStore: credentials,
            loginHandler: { _, _, _ in oauthResolution(accountID: nil) },
            resolveHandler: { _, _, _ in oauthResolution(accountID: nil) }
        )
        let pi = PiStreamSpy()
        let gateway = ProviderGateway(
            settingsRepository: SettingsRepository(dbQueue: database),
            credentialStore: credentials,
            superGrokAuthRepository: auth,
            piStream: pi.stream
        )

        _ = try await gateway.stream(
            request: ProviderRequest(
                model: "grok-4.5",
                messages: [ProviderRequestMessage(role: "user", content: "hello")]
            ),
            provider: .superGrok
        )

        let configuration = try XCTUnwrap(pi.calls.first?.configuration)
        XCTAssertEqual(configuration.provider, "xai-oauth")
    }

    func testOpenCodeGoMuseSparkUsesResponsesAPI() async throws {
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database)
        let credentials = PiGatewayCredentialStore()
        try credentials.setCredential("test-opencode-go-key", for: .openCodeGo)
        let pi = PiStreamSpy()
        let gateway = ProviderGateway(
            settingsRepository: SettingsRepository(dbQueue: database),
            credentialStore: credentials,
            piStream: pi.stream
        )

        _ = try await gateway.stream(
            request: ProviderRequest(
                model: "muse-spark-1.2",
                messages: [ProviderRequestMessage(role: "user", content: "hello")]
            ),
            provider: .openCodeGo
        )

        let configuration = try XCTUnwrap(pi.calls.first?.configuration)
        XCTAssertEqual(configuration.provider, "opencode-go")
        XCTAssertEqual(configuration.model, "muse-spark-1.2-contributor")
    }

    func testModelsDevOpenCodeGoMuseSparkUsesOfficialResponsesRoute() async throws {
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database)
        let credentials = PiGatewayCredentialStore()
        try credentials.saveSecret(
            "test-opencode-go-key",
            key: "models_dev_opencode-go_OPENCODE_API_KEY"
        )
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("models-dev-opencode-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let catalogModel = CatalogModel(
            id: "muse-spark-1.2-contributor",
            name: "Muse Spark 1.2 Contributor",
            attachment: true,
            reasoning: true,
            reasoningOptions: [],
            toolCall: true,
            structuredOutput: true,
            temperature: true,
            inputModalities: ["text", "image"],
            outputModalities: ["text"],
            limits: CatalogLimits(context: 1_048_576, input: nil, output: 32_768),
            cost: CatalogCost(
                inputPerMillion: nil,
                outputPerMillion: nil,
                reasoningPerMillion: nil,
                cacheReadPerMillion: nil,
                cacheWritePerMillion: nil
            ),
            providerContract: CatalogModelProviderContract(
                npm: "@ai-sdk/openai",
                api: nil,
                shape: "responses",
                provenance: "model"
            )
        )
        let catalogProvider = CatalogProvider(
            id: "opencode-go",
            name: "OpenCode Go",
            npm: "@ai-sdk/openai-compatible",
            api: "https://opencode.ai/zen/go/v1",
            env: ["OPENCODE_API_KEY"],
            models: [catalogModel]
        )
        try JSONEncoder().encode([catalogProvider]).write(to: cacheURL)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "PiAgentGatewayTests.\(UUID().uuidString)"))
        let catalog = ModelsDevCatalogRepository(defaults: defaults, cacheURL: cacheURL)
        let pi = PiStreamSpy()
        let gateway = ProviderGateway(
            settingsRepository: SettingsRepository(dbQueue: database),
            credentialStore: credentials,
            modelsDevCatalogRepository: catalog,
            piStream: pi.stream
        )

        _ = try await gateway.stream(
            request: ProviderRequest(
                model: "muse-spark-1.2-contributor",
                messages: [ProviderRequestMessage(role: "user", content: "hello")]
            ),
            providerID: "MODELS_DEV:OPENCODE-GO"
        )

        let configuration = try XCTUnwrap(pi.calls.first?.configuration)
        XCTAssertEqual(configuration.provider, "opencode-go")
        XCTAssertEqual(configuration.model, "muse-spark-1.2-contributor")
        XCTAssertEqual(configuration.catalogContract?.npm, "@ai-sdk/openai")
        XCTAssertNil(configuration.catalogContract?.api)
        XCTAssertEqual(configuration.catalogContract?.shape, "responses")
        XCTAssertEqual(configuration.catalogContract?.toolCall, true)
        XCTAssertEqual(configuration.catalogContract?.provenance, "model")
    }

    func testModelsDevOpenCodeGoMuseSparkPassesReasoningEffortAsThinkingLevel() async throws {
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database)
        let credentials = PiGatewayCredentialStore()
        try credentials.saveSecret(
            "test-opencode-go-key",
            key: "models_dev_opencode-go_OPENCODE_API_KEY"
        )
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("models-dev-opencode-effort-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let catalogModel = CatalogModel(
            id: "muse-spark-1.2-contributor",
            name: "Muse Spark 1.2 Contributor",
            attachment: true,
            reasoning: true,
            reasoningOptions: [
                CatalogReasoningOption(type: "effort", values: ["minimal", "low", "medium", "high", "xhigh"])
            ],
            toolCall: true,
            structuredOutput: true,
            temperature: true,
            inputModalities: ["text", "image"],
            outputModalities: ["text"],
            limits: CatalogLimits(context: 1_048_576, input: nil, output: 32_768),
            cost: CatalogCost(
                inputPerMillion: nil,
                outputPerMillion: nil,
                reasoningPerMillion: nil,
                cacheReadPerMillion: nil,
                cacheWritePerMillion: nil
            ),
            providerContract: CatalogModelProviderContract(
                npm: "@ai-sdk/openai",
                api: nil,
                shape: "responses"
            )
        )
        let catalogProvider = CatalogProvider(
            id: "opencode-go",
            name: "OpenCode Go",
            npm: "@ai-sdk/openai-compatible",
            api: "https://opencode.ai/zen/go/v1",
            env: ["OPENCODE_API_KEY"],
            models: [catalogModel]
        )
        try JSONEncoder().encode([catalogProvider]).write(to: cacheURL)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "PiAgentGatewayTests.\(UUID().uuidString)"))
        let catalog = ModelsDevCatalogRepository(defaults: defaults, cacheURL: cacheURL)
        let pi = PiStreamSpy()
        let gateway = ProviderGateway(
            settingsRepository: SettingsRepository(dbQueue: database),
            credentialStore: credentials,
            modelsDevCatalogRepository: catalog,
            piStream: pi.stream
        )

        _ = try await gateway.stream(
            request: ProviderRequest(
                model: "muse-spark-1.2-contributor",
                messages: [ProviderRequestMessage(role: "user", content: "hello")],
                thinking: ProviderThinkingConfig(
                    enabled: nil,
                    budget: nil,
                    effort: "medium",
                    includeThoughts: true,
                    exclude: nil
                )
            ),
            providerID: "MODELS_DEV:OPENCODE-GO"
        )

        let configuration = try XCTUnwrap(pi.calls.first?.configuration)
        XCTAssertEqual(configuration.provider, "opencode-go")
        XCTAssertEqual(configuration.model, "muse-spark-1.2-contributor")
        XCTAssertEqual(configuration.thinkingLevel, "medium")
    }
}
