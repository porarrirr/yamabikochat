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
    func testBundledPiRuntimeStarts() async throws {
        try await PiAgentRuntime.shared.verifyReady()
    }

    func testNetworkProvidersFailBeforeStartingPiWhenCredentialIsMissing() async throws {
        let database = try DatabaseQueue()
        try AppDatabase.migrator.migrate(database)
        let gateway = ProviderGateway(
            settingsRepository: SettingsRepository(dbQueue: database),
            credentialStore: PiGatewayCredentialStore()
        )

        for provider in [LLMProvider.gemini, .openRouter, .openAI, .miniMax, .zai, .clinePass, .alibabaCodingPlan, .openCodeGo] {
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
}
