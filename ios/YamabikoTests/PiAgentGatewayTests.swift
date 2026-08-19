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
                messages: [ProviderRequestMessage(role: "user", content: "hello")]
            ),
            providerID: "MODELS_DEV:OPENCODE-GO"
        )

        let configuration = try XCTUnwrap(pi.calls.first?.configuration)
        XCTAssertEqual(configuration.provider, "opencode-go")
        XCTAssertEqual(configuration.model, "muse-spark-1.2-contributor")
        XCTAssertEqual(configuration.catalogContract?.shape, "responses")
        XCTAssertEqual(configuration.catalogContract?.toolCall, true)
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
