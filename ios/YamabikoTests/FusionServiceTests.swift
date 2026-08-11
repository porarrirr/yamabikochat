import GRDB
import XCTest
@testable import YamabikoChat

final class FusionServiceTests: XCTestCase {
    private func makeService() -> FusionService {
        let dbQueue = try! DatabaseQueue()
        try! AppDatabase.migrator.migrate(dbQueue)
        let settings = SettingsRepository(dbQueue: dbQueue)
        let credentials = InMemoryCredentialStore()
        let resolver = ProviderRequestSettingsResolver(
            modelService: OpenRouterModelService(credentialStore: credentials)
        )
        let gateway = ProviderGateway(
            settingsRepository: settings,
            credentialStore: credentials,
            httpClient: NoopHTTPClient()
        )
        return FusionService(
            settingsRepository: settings,
            providerGateway: gateway,
            pricingRepository: FusionNoopPricingRepository(),
            traceStore: FusionTraceStore(dbQueue: dbQueue),
            requestSettingsResolver: resolver
        )
    }

    func testPanelMessagesDoesNotDuplicateMatchingUserTurn() async throws {
        let service = makeService()
        let history = [
            ProviderRequestMessage(role: "user", content: "Hello", attachments: ["file:///img.png"])
        ]
        let request = try await service.buildProviderRequest(
            model: PanelModelConfig(modelId: "m1", provider: "OPENAI"),
            systemPrompt: "panel",
            phase: .panel,
            allowTools: false,
            settings: AppSettings(),
            fusionDepth: 0,
            userPrompt: "Hello",
            conversationHistory: history,
            userAttachments: ["file:///img.png"],
            supportsVision: true,
            conversationID: "42"
        )

        XCTAssertEqual(request.messages.count, 1)
        XCTAssertEqual(request.messages[0].content, "Hello")
        XCTAssertEqual(request.messages[0].attachments, ["file:///img.png"])
        XCTAssertEqual(request.metadata["supportsVision"], "true")
        XCTAssertEqual(request.metadata["promptCacheKey"], "fusion-42")
    }

    func testPanelMessagesAppendsWhenHistoryDoesNotIncludeCurrentTurn() async throws {
        let service = makeService()
        let history = [
            ProviderRequestMessage(role: "user", content: "Earlier")
        ]
        let request = try await service.buildProviderRequest(
            model: PanelModelConfig(modelId: "m1", provider: "OPENAI"),
            systemPrompt: "panel",
            phase: .panel,
            allowTools: false,
            settings: AppSettings(),
            fusionDepth: 0,
            userPrompt: "Latest",
            conversationHistory: history,
            userAttachments: [],
            supportsVision: false
        )

        XCTAssertEqual(request.messages.count, 2)
        XCTAssertEqual(request.messages.last?.content, "Latest")
    }

    func testGenerationMetadataIncludesTemperatureWithoutFusionTokenLimit() async throws {
        let service = makeService()
        let request = try await service.buildProviderRequest(
            model: PanelModelConfig(
                modelId: "m1",
                provider: "OPENAI",
                temperature: 0.2
            ),
            systemPrompt: "judge",
            phase: .judge,
            allowTools: false,
            settings: AppSettings(),
            fusionDepth: 0,
            userPrompt: "test",
            conversationHistory: []
        )

        XCTAssertNil(request.metadata["max_output_tokens"])
        XCTAssertEqual(request.metadata["temperature"], "0.2")
    }

    func testFusionRequestDisablesURLSessionTimeout() async throws {
        let service = makeService()
        let request = try await service.buildProviderRequest(
            model: PanelModelConfig(
                modelId: "deepseek-v4-flash",
                provider: "OPENCODE_GO",
                timeoutMs: nil
            ),
            systemPrompt: "panel",
            phase: .panel,
            allowTools: false,
            settings: AppSettings(),
            fusionDepth: 0,
            userPrompt: "test",
            conversationHistory: []
        )

        XCTAssertEqual(request.timeoutInterval, .greatestFiniteMagnitude)
    }

    func testPanelRequestIncludesGeminiGlobalReasoningAndTools() async throws {
        let service = makeService()
        var settings = AppSettings()
        settings.clientWebSearchToolEnabled = true
        settings.geminiThinkingEnabled = true
        settings.geminiThinkingBudget = 1536
        settings.geminiGoogleSearchEnabled = true
        settings.geminiCodeExecutionEnabled = true

        let request = try await service.buildProviderRequest(
            model: PanelModelConfig(modelId: "gemini-2.5-flash", provider: "GEMINI"),
            systemPrompt: "panel",
            phase: .panel,
            allowTools: true,
            settings: settings,
            fusionDepth: 0,
            userPrompt: "Latest",
            conversationHistory: []
        )

        XCTAssertEqual(request.thinking?.budget, 1536)
        XCTAssertTrue(request.tools.contains { $0.type == "google_search" })
        XCTAssertTrue(request.tools.contains { $0.type == "code_execution" })
        XCTAssertTrue(request.tools.contains { $0.payload["name"] == WebSearchTool.name })
        XCTAssertTrue(request.tools.contains { $0.payload["name"] == FetchUrlTool.name })
    }

    func testFusionCodexGlobalReasoningAndNativeWebSearchApplyToAllPhases() async throws {
        let service = makeService()
        var settings = AppSettings()
        settings.codexReasoningEnabled = true
        settings.codexReasoningEffort = "high"
        settings.codexWebSearchEnabled = true
        settings.codexWebSearchContextSize = "high"
        let model = PanelModelConfig(modelId: "gpt-5.6-sol", provider: "CODEX_AUTH")

        let panel = try await service.buildProviderRequest(
            model: model,
            systemPrompt: "panel",
            phase: .panel,
            allowTools: true,
            settings: settings,
            fusionDepth: 0,
            userPrompt: "Latest",
            conversationHistory: []
        )
        let judge = try await service.buildProviderRequest(
            model: model,
            systemPrompt: "judge",
            phase: .judge,
            allowTools: false,
            settings: settings,
            fusionDepth: 0,
            userPrompt: "Latest",
            conversationHistory: []
        )

        XCTAssertEqual(panel.thinking?.effort, "high")
        XCTAssertEqual(judge.thinking?.effort, "high")
        XCTAssertEqual(panel.metadata["codexWebSearchEnabled"], "true")
        XCTAssertEqual(panel.metadata["codexWebSearchContextSize"], "high")
        XCTAssertEqual(judge.metadata["codexWebSearchEnabled"], "true")
        XCTAssertTrue(judge.tools.isEmpty)
    }
}

private struct NoopHTTPClient: HTTPClientProtocol {
    func send(_ request: HTTPRequest) async throws -> (Data, HTTPURLResponse) {
        throw ProviderClientError.parseFailure("noop")
    }

    func stream(_ request: HTTPRequest) async throws -> (AsyncThrowingStream<String, Error>, HTTPURLResponse) {
        throw ProviderClientError.parseFailure("noop")
    }
}

private struct InMemoryCredentialStore: SecureCredentialStore {
    func saveSecret(_ value: String?, key: String) throws {}
    func readSecret(key: String) throws -> String? { nil }
    func deleteSecret(key: String) throws {}
}
