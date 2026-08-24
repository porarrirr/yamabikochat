import XCTest
@testable import YamabikoChat

final class ProviderRequestSettingsResolverTests: XCTestCase {
    func testEditorIsPublishedOnlyForNormalAndDualPiToolContexts() async throws {
        let resolver = makeResolver()
        func containsEditor(
            context: AppSettings.ReasoningContext,
            scope: ProviderRequestToolScope = .all,
            provider: String = "GEMINI"
        ) async throws -> Bool {
            let resolved = try await resolver.resolve(
                settings: AppSettings(),
                provider: provider,
                model: "gemini-2.5-flash",
                context: context,
                toolScope: scope
            )
            return resolved.tools.contains { $0.payload["name"] == StrReplaceEditorTool.name }
        }

        let normal = try await containsEditor(context: .default)
        let dualA = try await containsEditor(context: .dualA)
        let dualB = try await containsEditor(context: .dualB)
        let autoA = try await containsEditor(context: .autoA)
        let autoB = try await containsEditor(context: .autoB)
        let fusion = try await containsEditor(context: .default, scope: .fusionPanel(allowWebSearch: true))
        let nonPi = try await containsEditor(context: .default, provider: LLMProvider.appleIntelligence.rawValue)
        XCTAssertTrue(normal)
        XCTAssertTrue(dualA)
        XCTAssertTrue(dualB)
        XCTAssertFalse(autoA)
        XCTAssertFalse(autoB)
        XCTAssertFalse(fusion)
        XCTAssertFalse(nonPi)
    }

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

    func testGemma4UsesThinkingLevelWithoutBudget() async throws {
        let resolver = makeResolver()
        var settings = AppSettings()
        settings.geminiThinkingEnabled = true
        settings.geminiThinkingBudget = 2048
        settings.geminiThinkingLevel = "high"

        let enabled = try await resolver.resolve(
            settings: settings,
            provider: "GEMINI",
            model: "gemma-4-31b-it"
        )
        XCTAssertNil(enabled.thinking?.budget)
        XCTAssertEqual(enabled.metadata["geminiThinkingLevel"], "high")

        settings.geminiThinkingEnabled = false
        let disabled = try await resolver.resolve(
            settings: settings,
            provider: "GEMINI",
            model: "gemma-4-26b-a4b-it"
        )
        XCTAssertNil(disabled.thinking?.budget)
        XCTAssertEqual(disabled.metadata["geminiThinkingLevel"], "minimal")
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

    func testPythonToolIsAdvertisedIndependentlyForToolCallingModels() async throws {
        let resolver = makeResolver()
        var settings = AppSettings()
        settings.clientWebSearchToolEnabled = false
        settings.pythonToolEnabled = true

        let resolved = try await resolver.resolve(
            settings: settings,
            provider: "GEMINI",
            model: "gemini-2.5-flash"
        )

        XCTAssertTrue(resolved.tools.contains { $0.payload["name"] == PythonExecuteTool.name })
        XCTAssertFalse(resolved.tools.containsWebSearchTool)
    }

    func testPythonToolIsOmittedFromFusionPanelScope() async throws {
        let resolver = makeResolver()
        var settings = AppSettings()
        settings.pythonToolEnabled = true

        let resolved = try await resolver.resolve(
            settings: settings,
            provider: "GEMINI",
            model: "gemini-2.5-flash",
            toolScope: .fusionPanel(allowWebSearch: true)
        )

        XCTAssertFalse(resolved.tools.contains { $0.payload["name"] == PythonExecuteTool.name })
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

    func testCodexMetadataContainsOnlySettingsConsumedByPiRuntime() async throws {
        let resolver = makeResolver()
        var settings = AppSettings()
        settings.codexReasoningEnabled = true
        settings.codexReasoningSummary = "detailed"
        settings.codexVerbosity = "high"
        settings.codexPromptCacheEnabled = false

        let resolved = try await resolver.resolve(
            settings: settings,
            provider: "CODEX_AUTH",
            model: "gpt-5.6-sol"
        )

        XCTAssertEqual(resolved.metadata, [
            "codexPromptCacheEnabled": "false",
            "codexReasoningSummary": "detailed",
            "codexVerbosity": "high",
            "supportsClientTools": "true"
        ])
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

    func testModelsDevToolCapabilityIsNotInventedWhenFalseOrMissing() async throws {
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("models-dev-tools-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: cacheURL) }
        let provider = CatalogProvider(
            id: "example",
            name: "Example",
            npm: "example-sdk",
            api: nil,
            env: ["EXAMPLE_API_KEY"],
            models: [
                catalogModel(id: "disabled", toolCall: false),
                catalogModel(id: "missing", toolCall: nil),
                catalogModel(id: "enabled", toolCall: true)
            ]
        )
        try JSONEncoder().encode([provider]).write(to: cacheURL)
        let repository = ModelsDevCatalogRepository(cacheURL: cacheURL)
        let resolver = ProviderRequestSettingsResolver(
            modelService: OpenRouterModelService(credentialStore: ResolverCredentialStore()),
            modelsDevCatalogRepository: repository
        )
        var settings = AppSettings()
        settings.clientWebSearchToolEnabled = true

        for model in ["disabled", "missing"] {
            let resolved = try await resolver.resolve(
                settings: settings,
                provider: "MODELS_DEV:example",
                model: model
            )
            XCTAssertEqual(resolved.metadata["supportsClientTools"], "false")
            XCTAssertFalse(resolved.tools.containsWebSearchTool)
        }
        let enabled = try await resolver.resolve(
            settings: settings,
            provider: "MODELS_DEV:example",
            model: "enabled"
        )
        XCTAssertEqual(enabled.metadata["supportsClientTools"], "true")
        XCTAssertTrue(enabled.tools.containsWebSearchTool)
    }

    func testModelsDevSavedReasoningEffortIsAppliedWhenCatalogSupportsIt() async throws {
        let resolver = try makeOpenCodeGoMuseSparkResolver(savedEffort: "medium")
        let resolved = try await resolver.resolve(
            settings: AppSettings(),
            provider: "MODELS_DEV:opencode-go",
            model: "muse-spark-1.2-contributor"
        )
        XCTAssertEqual(resolved.thinking?.effort, "medium")
    }

    func testModelsDevBlankReasoningEffortDoesNotInventThinkingConfig() async throws {
        let resolver = try makeOpenCodeGoMuseSparkResolver(savedEffort: "")
        let resolved = try await resolver.resolve(
            settings: AppSettings(),
            provider: "MODELS_DEV:opencode-go",
            model: "muse-spark-1.2-contributor"
        )
        XCTAssertNil(resolved.thinking)
    }

    private func catalogModel(id: String, toolCall: Bool?) -> CatalogModel {
        CatalogModel(
            id: id,
            name: id.capitalized,
            reasoningOptions: [],
            toolCall: toolCall,
            inputModalities: ["text"],
            outputModalities: ["text"],
            limits: CatalogLimits(context: nil, input: nil, output: nil),
            cost: CatalogCost(
                inputPerMillion: nil,
                outputPerMillion: nil,
                reasoningPerMillion: nil,
                cacheReadPerMillion: nil,
                cacheWritePerMillion: nil
            )
        )
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

    func testResolvedModelContextWindowIsPassedToPiMetadata() async throws {
        let modelService = OpenRouterModelService(credentialStore: ResolverCredentialStore())
        modelService.replaceCachedModels([
            SimpleModel(
                id: "google/gemini-test",
                name: "Gemini Test",
                provider: "google",
                topProvider: "google",
                contextLength: 1_048_576,
                promptPricePerMillion: 0,
                completionPricePerMillion: 0,
                isFree: true,
                availableProviders: ["google"],
                availableQuantizations: []
            )
        ])
        let resolver = ProviderRequestSettingsResolver(modelService: modelService)

        let resolved = try await resolver.resolve(
            settings: AppSettings(),
            provider: "GEMINI",
            model: "gemini-test"
        )

        XCTAssertEqual(resolved.metadata["contextWindow"], "1048576")
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

    private func makeOpenCodeGoMuseSparkResolver(savedEffort: String) throws -> ProviderRequestSettingsResolver {
        let cacheURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("models-dev-muse-spark-\(UUID().uuidString).json")
        addTeardownBlock { try? FileManager.default.removeItem(at: cacheURL) }
        let provider = CatalogProvider(
            id: "opencode-go",
            name: "OpenCode Go",
            npm: "@ai-sdk/openai-compatible",
            api: "https://opencode.ai/zen/go/v1",
            env: ["OPENCODE_API_KEY"],
            models: [
                CatalogModel(
                    id: "muse-spark-1.2-contributor",
                    name: "Muse Spark 1.2 Contributor",
                    reasoning: true,
                    reasoningOptions: [
                        CatalogReasoningOption(
                            type: "effort",
                            values: ["minimal", "low", "medium", "high", "xhigh"]
                        )
                    ],
                    toolCall: true,
                    inputModalities: ["text", "image"],
                    outputModalities: ["text"],
                    limits: CatalogLimits(context: 1_048_576, input: nil, output: 32_768),
                    cost: CatalogCost(
                        inputPerMillion: nil,
                        outputPerMillion: nil,
                        reasoningPerMillion: nil,
                        cacheReadPerMillion: nil,
                        cacheWritePerMillion: nil
                    )
                )
            ]
        )
        try JSONEncoder().encode([provider]).write(to: cacheURL)
        return ProviderRequestSettingsResolver(
            modelService: OpenRouterModelService(credentialStore: ResolverCredentialStore()),
            modelsDevCatalogRepository: ModelsDevCatalogRepository(cacheURL: cacheURL),
            modelsDevReasoningEffort: { _, _ in savedEffort }
        )
    }
}

private struct ResolverCredentialStore: SecureCredentialStore {
    func saveSecret(_ value: String?, key: String) throws {}
    func readSecret(key: String) throws -> String? { nil }
    func deleteSecret(key: String) throws {}
}
