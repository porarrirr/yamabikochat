import XCTest
@testable import YamabikoChat

final class AutoConversationOverridesTests: XCTestCase {
    func testSideAKeyPathsWriteOnlyTheAutoAFields() {
        var settings = AppSettings()
        let keyPaths = DualModelSide.a.keyPaths

        settings[keyPath: keyPaths.provider] = "OPENROUTER"
        settings[keyPath: keyPaths.model] = "deepseek/deepseek-reasoner"
        settings[keyPath: keyPaths.googleSearch] = true
        settings[keyPath: keyPaths.codeExecution] = false
        settings[keyPath: keyPaths.urlContext] = true
        settings[keyPath: keyPaths.googleMaps] = false
        settings[keyPath: keyPaths.thinkingEnabled] = true
        settings[keyPath: keyPaths.thinkingBudget] = 2048
        settings[keyPath: keyPaths.thinkingLevel] = "high"
        settings[keyPath: keyPaths.codexReasoningEffort] = "minimal"
        settings[keyPath: keyPaths.openRouterThinkingEnabled] = true
        settings[keyPath: keyPaths.openRouterThinkingBudget] = 4096
        settings[keyPath: keyPaths.openRouterReasoningMode] = "effort"
        settings[keyPath: keyPaths.openRouterReasoningEffort] = "low"
        settings[keyPath: keyPaths.openRouterReasoningExclude] = true

        XCTAssertEqual(settings.autoProviderA, "OPENROUTER")
        XCTAssertEqual(settings.autoModelA, "deepseek/deepseek-reasoner")
        XCTAssertEqual(settings.autoGoogleSearchEnabledA, true)
        XCTAssertEqual(settings.autoCodeExecutionEnabledA, false)
        XCTAssertEqual(settings.autoURLContextEnabledA, true)
        XCTAssertEqual(settings.autoGoogleMapsEnabledA, false)
        XCTAssertEqual(settings.autoThinkingEnabledA, true)
        XCTAssertEqual(settings.autoThinkingBudgetA, 2048)
        XCTAssertEqual(settings.autoThinkingLevelA, "high")
        XCTAssertEqual(settings.autoCodexReasoningEffortA, "minimal")
        XCTAssertEqual(settings.autoOpenRouterThinkingEnabledA, true)
        XCTAssertEqual(settings.autoOpenRouterThinkingBudgetA, 4096)
        XCTAssertEqual(settings.autoOpenRouterReasoningModeA, "effort")
        XCTAssertEqual(settings.autoOpenRouterReasoningEffortA, "low")
        XCTAssertEqual(settings.autoOpenRouterReasoningExcludeA, true)

        // The other auto slot stays untouched.
        XCTAssertEqual(settings.autoProviderB, AppSettings().autoProviderB)
        XCTAssertNil(settings.autoThinkingLevelB)
        XCTAssertNil(settings.autoOpenRouterReasoningEffortB)

        let thinking = settings.thinkingOverride(for: .autoA)
        XCTAssertEqual(thinking.enabled, true)
        XCTAssertEqual(thinking.budget, 2048)
        XCTAssertEqual(thinking.level, "high")
        XCTAssertEqual(thinking.codexEffort, "minimal")

        let openRouter = settings.openRouterOverride(for: .autoA)
        XCTAssertEqual(openRouter.mode, "effort")
        XCTAssertEqual(openRouter.effort, "low")
        XCTAssertEqual(openRouter.exclude, true)

        let tools = settings.toolOverride(for: .autoA)
        XCTAssertEqual(tools.googleSearch, true)
        XCTAssertEqual(tools.codeExecution, false)
        XCTAssertEqual(tools.urlContext, true)
        XCTAssertEqual(tools.googleMaps, false)
    }

    func testSideBKeyPathsWriteOnlyTheAutoBFields() {
        var settings = AppSettings()
        let keyPaths = DualModelSide.b.keyPaths

        settings[keyPath: keyPaths.provider] = "CODEX_AUTH"
        settings[keyPath: keyPaths.model] = "gpt-5-codex"
        settings[keyPath: keyPaths.thinkingEnabled] = true
        settings[keyPath: keyPaths.codexReasoningEffort] = "xhigh"
        settings[keyPath: keyPaths.openRouterReasoningMode] = "budget"
        settings[keyPath: keyPaths.openRouterThinkingBudget] = 8192

        XCTAssertEqual(settings.autoProviderB, "CODEX_AUTH")
        XCTAssertEqual(settings.autoModelB, "gpt-5-codex")
        XCTAssertEqual(settings.autoThinkingEnabledB, true)
        XCTAssertEqual(settings.autoCodexReasoningEffortB, "xhigh")
        XCTAssertEqual(settings.autoOpenRouterReasoningModeB, "budget")
        XCTAssertEqual(settings.autoOpenRouterThinkingBudgetB, 8192)

        XCTAssertEqual(settings.autoProviderA, AppSettings().autoProviderA)
        XCTAssertNil(settings.autoThinkingLevelA)
        XCTAssertNil(settings.autoCodexReasoningEffortA)

        let thinking = settings.thinkingOverride(for: .autoB)
        XCTAssertEqual(thinking.enabled, true)
        XCTAssertEqual(thinking.codexEffort, "xhigh")
        XCTAssertNil(settings.thinkingOverride(for: .autoA).codexEffort)

        let openRouter = settings.openRouterOverride(for: .autoB)
        XCTAssertEqual(openRouter.mode, "budget")
        XCTAssertEqual(openRouter.budget, 8192)
    }
}
