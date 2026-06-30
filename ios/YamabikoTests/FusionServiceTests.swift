import GRDB
import XCTest
@testable import YamabikoChat

final class FusionServiceTests: XCTestCase {
    private func makeService() -> FusionService {
        let dbQueue = try! DatabaseQueue()
        try! AppDatabase.migrator.migrate(dbQueue)
        let settings = SettingsRepository(dbQueue: dbQueue)
        let gateway = ProviderGateway(
            settingsRepository: settings,
            credentialStore: InMemoryCredentialStore(),
            httpClient: NoopHTTPClient()
        )
        return FusionService(
            settingsRepository: settings,
            providerGateway: gateway,
            pricingRepository: FusionNoopPricingRepository(),
            traceStore: FusionTraceStore(dbQueue: dbQueue)
        )
    }

    func testPanelMessagesDoesNotDuplicateMatchingUserTurn() {
        let service = makeService()
        let history = [
            ProviderRequestMessage(role: "user", content: "Hello", attachments: ["file:///img.png"])
        ]
        let request = service.buildProviderRequest(
            model: PanelModelConfig(modelId: "m1", provider: "OPENAI"),
            systemPrompt: "panel",
            phase: .panel,
            allowTools: false,
            maxTokens: 512,
            settings: AppSettings(),
            fusionDepth: 0,
            userPrompt: "Hello",
            conversationHistory: history,
            userAttachments: ["file:///img.png"],
            supportsVision: true
        )

        XCTAssertEqual(request.messages.count, 1)
        XCTAssertEqual(request.messages[0].content, "Hello")
        XCTAssertEqual(request.messages[0].attachments, ["file:///img.png"])
        XCTAssertEqual(request.metadata["supportsVision"], "true")
    }

    func testPanelMessagesAppendsWhenHistoryDoesNotIncludeCurrentTurn() {
        let service = makeService()
        let history = [
            ProviderRequestMessage(role: "user", content: "Earlier")
        ]
        let request = service.buildProviderRequest(
            model: PanelModelConfig(modelId: "m1", provider: "OPENAI"),
            systemPrompt: "panel",
            phase: .panel,
            allowTools: false,
            maxTokens: 512,
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

    func testGenerationMetadataIncludesMaxTokensAndTemperature() {
        let service = makeService()
        let request = service.buildProviderRequest(
            model: PanelModelConfig(
                modelId: "m1",
                provider: "OPENAI",
                temperature: 0.2,
                maxTokens: 1234
            ),
            systemPrompt: "judge",
            phase: .judge,
            allowTools: false,
            maxTokens: 4096,
            settings: AppSettings(),
            fusionDepth: 0,
            userPrompt: "test",
            conversationHistory: []
        )

        XCTAssertEqual(request.metadata["max_output_tokens"], "1234")
        XCTAssertEqual(request.metadata["temperature"], "0.2")
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