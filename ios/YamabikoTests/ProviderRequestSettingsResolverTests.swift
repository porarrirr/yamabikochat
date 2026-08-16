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

    func testClientWebSearchToolsAreAvailableForEveryPiProvider() async throws {
        let resolver = makeResolver()
        var settings = AppSettings()
        settings.clientWebSearchToolEnabled = true

        for provider in LLMProvider.allCases where provider != .appleIntelligence {
            let resolved = try await resolver.resolve(
                settings: settings,
                provider: provider.rawValue,
                model: "test-model"
            )

            XCTAssertTrue(
                resolved.tools.containsWebSearchTool,
                "Expected web_search for \(provider.rawValue)"
            )
            XCTAssertTrue(
                resolved.tools.contains { $0.payload["name"] == FetchUrlTool.name },
                "Expected fetch_url for \(provider.rawValue)"
            )
        }
    }

    func testAppleIntelligenceOmitsClientToolsBecauseItDoesNotUsePiAgent() async throws {
        let resolver = makeResolver()
        var settings = AppSettings()
        settings.clientWebSearchToolEnabled = true

        let resolved = try await resolver.resolve(
            settings: settings,
            provider: LLMProvider.appleIntelligence.rawValue,
            model: "apple-on-device"
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

    func testAgentSkillFunctionToolsAreSentOnlyOnceWhenLocalRegistryAlsoContainsExecutors() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("provider-resolver-skill-tests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: root) }

        let repository = AgentSkillRepository(rootURL: root.appendingPathComponent("installed"))
        let source = root.appendingPathComponent("source", isDirectory: true)
        try fileManager.createDirectory(at: source, withIntermediateDirectories: true)
        let markdown = "---\nname: resolver-skill\ndescription: Test skill\n---\nFollow the resolver test instructions.\n"
        try Data(markdown.utf8).write(to: source.appendingPathComponent("SKILL.md"))
        let preview = try repository.inspect(sourceURL: source)
        _ = try repository.install(preview, trusted: true, allowReplacement: false)

        let localTools = LocalToolRegistry(
            executors: [WebSearchTool(), FetchUrlTool()] + AgentSkillTools.executors(repository: repository)
        )
        let resolver = ProviderRequestSettingsResolver(
            modelService: OpenRouterModelService(credentialStore: ResolverCredentialStore()),
            skillRepository: repository,
            localToolRegistry: localTools
        )
        var settings = AppSettings()
        settings.clientWebSearchToolEnabled = true

        let resolved = try await resolver.resolve(
            settings: settings,
            provider: "OPENAI",
            model: "gpt-5.6"
        )

        let functionNames = resolved.tools.compactMap { tool -> String? in
            guard tool.type == "function" else { return nil }
            return tool.payload["name"]
        }
        XCTAssertEqual(functionNames.count, Set(functionNames).count)
        XCTAssertEqual(functionNames.filter { $0 == AgentSkillTools.activateName }.count, 1)
        XCTAssertEqual(functionNames.filter { $0 == AgentSkillTools.readResourceName }.count, 1)
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
