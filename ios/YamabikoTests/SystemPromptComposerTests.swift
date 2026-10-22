import XCTest
@testable import YamabikoChat

final class SystemPromptComposerTests: XCTestCase {
    func testGenUIInstructionsAreIncludedOnlyWhenToolIsProvided() {
        let enabled = SystemPromptComposer.composeForAPI(nil, enablesGenUIInstructions: true)
        let disabled = SystemPromptComposer.composeForAPI(nil)
        let runtimeGuidance = GenUITool.definition.description
        XCTAssertTrue(enabled?.contains("Use genui to supplement text answers") == true)
        XCTAssertTrue(enabled?.contains("genui_reference with componentName:\"*\"") == true)
        XCTAssertTrue(enabled?.contains("Reuse retrieved guidance from conversation history") == true)
        XCTAssertFalse(enabled?.contains("tool definition lists supported component names") == true)
        XCTAssertTrue(enabled?.contains("Inputs update locally") == true)
        XCTAssertTrue(enabled?.contains("Prefer code for interactive calculations") == true)
        XCTAssertTrue(runtimeGuidance.contains("Math.min/Math.max/Math.abs/Math.round/Math.pow"))
        XCTAssertTrue(enabled?.contains("legacy formula language applies only to components") == true)
        XCTAssertTrue(enabled?.contains("Actual capacity depends on device memory") == true)
        XCTAssertTrue(runtimeGuidance.contains("defaults to a line chart"))
        XCTAssertTrue(runtimeGuidance.contains("chartType:\"pie\""))
        XCTAssertTrue(runtimeGuidance.contains("match data keys explicitly"))
        XCTAssertFalse(disabled?.contains("Use genui to supplement text answers") == true)
    }

    func testExplanationsKeepEssentialContentVisibleWithoutMandatoryWidgets() throws {
        let prompt = try XCTUnwrap(SystemPromptComposer.composeForAPI(nil, enablesGenUIInstructions: true))
        for guidance in [
            "A simple definition, explanation, or worked example can be answered directly in Markdown",
            "visible without extra taps",
            "Do not turn every section into an accordion",
            "Use tabs or segmented controls only for meaningful alternative views or modes",
            "Use ui or code for explanatory layouts",
            "convey the key answer and important facts in text as well"
        ] {
            XCTAssertTrue(prompt.contains(guidance), guidance)
        }
        XCTAssertFalse(prompt.contains("put secondary tables, explanations, and code behind user-opened details"))
        XCTAssertFalse(prompt.contains("For rich documents use segmented-control"))
        XCTAssertFalse(GenUITool.definition.description.contains("After success, briefly explain the UI"))
        XCTAssertTrue(GenUITool.definition.description.contains("Use basic elements directly for ordinary layouts"))
    }

    func testGenUICategoryPolicyIncludesRequiredSearchFallbackAndRestrainedPresentation() throws {
        let prompt = try XCTUnwrap(SystemPromptComposer.composeForAPI(nil, enablesGenUIInstructions: true))
        for guidance in [
            "Weather (current conditions or forecasts), currency/unit conversions, and current time in any region",
            "Sports (scores, standings, or player information): widget search is required",
            "recommending three or more places in the same region or showing a route",
            "Product comparisons: GenUI is recommended",
            "Data analysis: use charts",
            "GenUI is normally unnecessary",
            "Search on each relevant request, but reuse exact contracts",
            "If no suitable widget is available",
            "required verified data or supported functionality is unavailable, answer normally in text",
            "Never invent data or backend actions to satisfy a required category",
            "Do not set a usage percentage or call-count target",
            "one best widget per purpose",
            "Use forms only when multiple required pieces of information must be collected together",
            "use cards only when they help organize information",
            "images when visual information helps answer the question",
            "convey the key answer and important facts in text as well"
        ] {
            XCTAssertTrue(prompt.contains(guidance), guidance)
        }
        XCTAssertTrue(GenUITool.definition.description.contains("Follow the system category rules"))
        XCTAssertTrue(GenUIReferenceTool.definition.description.contains("Search widget names for required GenUI categories"))
        XCTAssertFalse(prompt.contains("add only useful context that the UI does not already convey"))
        XCTAssertFalse(GenUITool.definition.description.contains("Do not repeat UI."))
    }

    func testExplicitGenUIRequestsRequireRenderedUIAndErrorRecovery() throws {
        let prompt = try XCTUnwrap(SystemPromptComposer.composeForAPI(nil, enablesGenUIInstructions: true))
        XCTAssertTrue(prompt.contains("requires an actual genui tool call, even for a simple explanation"))
        XCTAssertTrue(prompt.contains("Do not put a text-art diagram inside a Markdown/text component"))
        XCTAssertTrue(prompt.contains("correct the arguments using the supplied component/property contracts, and call genui again"))
        XCTAssertTrue(prompt.contains("do not silently substitute ASCII"))
        XCTAssertTrue(GenUITool.definition.description.contains(GenUITool.interactiveDiagramExample))
    }

    func testExplanationsDescribeVisualStructureAndMeaningfulControls() throws {
        let prompt = try XCTUnwrap(SystemPromptComposer.composeForAPI(nil, enablesGenUIInstructions: true))
        for guidance in ["Do not concatenate numbered stages and Unicode arrows", "recompute the result", "Keep the entire flow visible", "minChildWidth:160"] {
            XCTAssertTrue(prompt.contains(guidance), guidance)
        }
        XCTAssertTrue(GenUITool.definition.description.contains("list-item {label,description}"))
        XCTAssertTrue(GenUITool.usageGuide.contains("Text sizes use sm/md/lg/xl"))
    }

    func testResearchAndClarificationAllowUsefulProgress() throws {
        let prompt = try XCTUnwrap(SystemPromptComposer.composeForAPI(
            nil, enablesAgenticWebSearch: true, enablesUserQuestionInstructions: true
        ))
        XCTAssertTrue(prompt.contains("After a transient error, retry only when there is a reasonable prospect of success"))
        XCTAssertTrue(prompt.contains("For minor ambiguities, state a reasonable assumption and proceed"))
        XCTAssertTrue(prompt.contains("do not invent an answer or treat cancellation as authorization"))
        XCTAssertTrue(prompt.contains("Continue work that does not depend on that answer"))
        XCTAssertFalse(prompt.contains("including after errors"))
        XCTAssertFalse(prompt.contains("append \"(Recommended)\""))
    }

    func testAllToolCombinationsPreserveCustomPromptAndOnlyIncludeAvailableToolGuidance() throws {
        let instructions = [
            SystemPromptComposer.agenticWebSearchInstructions,
            SystemPromptComposer.editorToolInstructions,
            SystemPromptComposer.pythonToolInstructions,
            SystemPromptComposer.userQuestionToolInstructions,
            SystemPromptComposer.genUIToolInstructions
        ]
        for mask in 0..<32 {
            let enabled = (0..<5).map { mask & (1 << $0) != 0 }
            let prompt = try XCTUnwrap(SystemPromptComposer.composeForAPI(
                "  Answer in Japanese with detailed examples.  ",
                enablesAgenticWebSearch: enabled[0],
                enablesEditorInstructions: enabled[1],
                enablesPythonInstructions: enabled[2],
                enablesUserQuestionInstructions: enabled[3],
                enablesGenUIInstructions: enabled[4],
                now: makeDate(year: 2026, month: 10, day: 14)
            ))
            XCTAssertTrue(prompt.hasPrefix("Answer in Japanese with detailed examples.\n\n"), "mask=\(mask)")
            XCTAssertTrue(prompt.hasSuffix("Today's date: 2026/10/14"), "mask=\(mask)")
            for (index, instruction) in instructions.enumerated() {
                XCTAssertEqual(prompt.components(separatedBy: instruction).count - 1, enabled[index] ? 1 : 0,
                               "mask=\(mask), instruction=\(index)")
            }
        }
    }

    private var tokyoTimeZone: TimeZone {
        TimeZone(identifier: "Asia/Tokyo")!
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tokyoTimeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    override func setUp() {
        super.setUp()
        NSTimeZone.default = tokyoTimeZone
    }

    override func tearDown() {
        NSTimeZone.default = .current
        super.tearDown()
    }

    func testComposeForAPI_appendsDateSuffixAfterPromptBody() {
        let composed = SystemPromptComposer.composeForAPI(
            "  Be helpful.  ",
            now: makeDate(year: 2026, month: 6, day: 27)
        )

        XCTAssertEqual(composed, "Be helpful.\n\nToday's date: 2026/06/27")
    }

    func testComposeForAPI_returnsDateOnlyWhenPromptIsNil() {
        let composed = SystemPromptComposer.composeForAPI(
            nil,
            now: makeDate(year: 2026, month: 6, day: 27)
        )

        XCTAssertEqual(composed, "Today's date: 2026/06/27")
    }

    func testComposeForAPI_returnsDateOnlyWhenPromptIsBlank() {
        let composed = SystemPromptComposer.composeForAPI(
            "   \n\t  ",
            now: makeDate(year: 2026, month: 6, day: 27)
        )

        XCTAssertEqual(composed, "Today's date: 2026/06/27")
    }

    func testComposeForAPI_keepsStaticPromptAsPrefixForCacheFriendliness() {
        let composed = SystemPromptComposer.composeForAPI(
            "Stable instructions",
            now: makeDate(year: 2026, month: 6, day: 27)
        )

        XCTAssertTrue(composed?.hasPrefix("Stable instructions") == true)
        XCTAssertFalse(composed?.hasPrefix("Today's date:") == true)
    }

    func testComposeForAPI_appendsAgenticWebSearchInstructionsWhenEnabled() {
        let composed = SystemPromptComposer.composeForAPI(
            "Be helpful.",
            enablesAgenticWebSearch: true,
            now: makeDate(year: 2026, month: 6, day: 27)
        )

        XCTAssertTrue(composed?.contains("You have access to web_search and fetch_url.") == true)
        XCTAssertTrue(composed?.contains("Work from evidence toward an answer:") == true)
        XCTAssertTrue(composed?.contains("Start with a focused search") == true)
        XCTAssertTrue(composed?.contains("Supply goal to web_search together with read_sources=true") == true)
        XCTAssertTrue(composed?.contains("goal alone does not read pages") == true)
        XCTAssertTrue(composed?.contains("Table rows include column labels") == true)
        XCTAssertTrue(composed?.contains("Read research_progress and research_status") == true)
        XCTAssertTrue(composed?.contains("Cite only sources actually used with a descriptive Markdown link") == true)
        XCTAssertTrue(composed?.contains("provide a raw URL when the user requests it") == true)
        XCTAssertTrue(composed?.hasSuffix("Today's date: 2026/06/27") == true)
    }

    func testComposeForAPI_omitsAgenticWebSearchInstructionsWhenDisabled() {
        let composed = SystemPromptComposer.composeForAPI(
            "Be helpful.",
            enablesAgenticWebSearch: false,
            now: makeDate(year: 2026, month: 6, day: 27)
        )

        XCTAssertFalse(composed?.contains("web_search") == true)
        XCTAssertEqual(composed, "Be helpful.\n\nToday's date: 2026/06/27")
    }

    func testComposeForAPI_appendsEditorInstructionsWhenEnabled() {
        let composed = SystemPromptComposer.composeForAPI(
            "Be helpful.",
            enablesEditorInstructions: true,
            now: makeDate(year: 2026, month: 6, day: 27)
        )

        XCTAssertTrue(composed?.contains("Use only the tools that are actually provided.") == true)
        XCTAssertTrue(composed?.contains("do not invent tool names or parameters") == true)
        XCTAssertTrue(composed?.contains("When using str_replace_editor:") == true)
        XCTAssertTrue(composed?.contains("view_format=jsonl") == true)
        XCTAssertTrue(composed?.contains("Inspect the relevant file before modifying it.") == true)
        XCTAssertTrue(composed?.contains("Preserve unrelated content.") == true)
        XCTAssertTrue(composed?.hasSuffix("Today's date: 2026/06/27") == true)
    }

    func testComposeForAPI_omitsEditorInstructionsWhenDisabled() {
        let composed = SystemPromptComposer.composeForAPI(
            "Be helpful.",
            enablesEditorInstructions: false,
            now: makeDate(year: 2026, month: 6, day: 27)
        )

        XCTAssertFalse(composed?.contains("str_replace_editor") == true)
        XCTAssertEqual(composed, "Be helpful.\n\nToday's date: 2026/06/27")
    }

    func testComposeForAPI_requiresRealPythonExecutionWhenEnabled() {
        let composed = SystemPromptComposer.composeForAPI(
            "Be helpful.",
            enablesPythonInstructions: true,
            now: makeDate(year: 2026, month: 6, day: 27)
        )

        XCTAssertTrue(composed?.contains("use python_execute") == true)
        XCTAssertTrue(composed?.contains("does not execute it") == true)
        XCTAssertTrue(composed?.contains("Do not infer or fabricate execution results") == true)
    }

    func testComposeForAPI_appendsUserQuestionInstructionsWhenEnabled() {
        let composed = SystemPromptComposer.composeForAPI(
            "Be helpful.",
            enablesUserQuestionInstructions: true,
            now: makeDate(year: 2026, month: 6, day: 27)
        )

        XCTAssertTrue(composed?.contains("Use ask_user_question only when") == true)
        XCTAssertTrue(AskUserQuestionTool.definition.description.contains("stable id"))
        XCTAssertTrue(composed?.contains("only when there is a justified recommendation") == true)
        XCTAssertTrue(composed?.contains("If the user cancels") == true)
        XCTAssertTrue(composed?.hasSuffix("Today's date: 2026/06/27") == true)
    }
}
