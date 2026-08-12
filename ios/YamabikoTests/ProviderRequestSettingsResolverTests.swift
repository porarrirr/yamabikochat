import XCTest
@testable import YamabikoChat

final class ProviderRequestSettingsResolverTests: XCTestCase {
    func testDualContextInheritsProviderGlobalsIncludingClientWebSearch() async throws {
        let resolver = makeResolver()
        var settings = AppSettings()
        settings.clientWebSearchToolEnabled = true
        settings.geminiThinkingEnabled = true
        settings.geminiThinkingBudget = 2048
        settings.geminiGoogleSearchEnabled = true
        settings.geminiCodeExecutionEnabled = true
        settings.dualThinkingEnabledA = nil
        settings.dualThinkingBudgetA = nil
        settings.dualGoogleSearchEnabledA = nil
        settings.dualCodeExecutionEnabledA = nil

        let resolved = try await resolver.resolve(
            settings: settings,
            provider: "GEMINI",
            model: "gemini-2.5-flash",
            context: .dualA
        )

        XCTAssertEqual(resolved.thinking?.budget, 2048)
        XCTAssertTrue(resolved.tools.contains { $0.type == "google_search" })
        XCTAssertTrue(resolved.tools.contains { $0.type == "code_execution" })
        XCTAssertTrue(resolved.tools.contains { $0.payload["name"] == WebSearchTool.name })
        XCTAssertTrue(resolved.tools.contains { $0.payload["name"] == FetchUrlTool.name })
    }

    func testDualOverridesTakePriorityOverProviderGlobals() async throws {
        let resolver = makeResolver()
        var settings = AppSettings()
        settings.geminiThinkingEnabled = true
        settings.geminiThinkingBudget = 2048
        settings.geminiGoogleSearchEnabled = true
        settings.dualThinkingEnabledA = false
        settings.dualThinkingBudgetA = 1024
        settings.dualGoogleSearchEnabledA = false

        let resolved = try await resolver.resolve(
            settings: settings,
            provider: "GEMINI",
            model: "gemini-2.5-flash",
            context: .dualA
        )

        XCTAssertEqual(resolved.thinking?.budget, 0)
        XCTAssertFalse(resolved.tools.contains { $0.type == "google_search" })
    }

    func testClientWebSearchToolsAreOmittedWhenSettingIsDisabled() async throws {
        let resolver = makeResolver()
        var settings = AppSettings()
        settings.clientWebSearchToolEnabled = false

        let resolved = try await resolver.resolve(
            settings: settings,
            provider: "GEMINI",
            model: "gemini-2.5-flash"
        )

        XCTAssertFalse(resolved.tools.containsWebSearchTool)
        XCTAssertFalse(resolved.tools.contains { $0.payload["name"] == FetchUrlTool.name })
    }

    func testOpenRouterGlobalRoutingIsResolvedForEveryMode() async throws {
        let resolver = makeResolver()
        var settings = AppSettings()
        settings.openRouterThinkingEnabled = false
        settings.maxPricePerMillionTokens = 2.5
        settings.requireParameters = true

        let resolved = try await resolver.resolve(
            settings: settings,
            provider: "OPENROUTER",
            model: "example/model",
            context: .dualB
        )

        XCTAssertEqual(resolved.routing?.maxPrice?.prompt, 2.5)
        XCTAssertEqual(resolved.routing?.maxPrice?.completion, 2.5)
        XCTAssertEqual(resolved.routing?.requireParameters, true)
    }

    private func makeResolver() -> ProviderRequestSettingsResolver {
        ProviderRequestSettingsResolver(
            modelService: OpenRouterModelService(credentialStore: ResolverCredentialStore())
        )
    }
}

private struct ResolverCredentialStore: SecureCredentialStore {
    func saveSecret(_ value: String?, key: String) throws {}
    func readSecret(key: String) throws -> String? { nil }
    func deleteSecret(key: String) throws {}
}
