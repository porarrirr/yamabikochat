import XCTest

/// Verifies the compact overview and model editing within each mode screen.
final class AutoConversationSettingsUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testAutoConversationExposesPerModelReasoningOverrides() throws {
        let app = launchConversationSettings(auto: true)
        let autoRow = app.buttons["conversation-auto-mode"]
        XCTAssertTrue(autoRow.waitForExistence(timeout: 10))
        XCTAssertTrue(autoRow.isHittable, "Mode settings should be visible without scrolling")
        XCTAssertFalse(app.switches.matching(NSPredicate(format: "label CONTAINS %@", "Thinking")).firstMatch.exists)
        capture("conversation-overview")
        autoRow.tap()
        let enabled = app.switches.matching(NSPredicate(format: "label CONTAINS %@", "自動会話を有効化")).firstMatch
        XCTAssertTrue(enabled.waitForExistence(timeout: 10))
        if (enabled.value as? String) != "1" {
            enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }

        let sides = app.segmentedControls["conversation-model-side"]
        XCTAssertTrue(sides.waitForExistence(timeout: 10))
        capture("auto-conversation-overview")
        let advanced = app.buttons["conversation-model-advanced"]
        for _ in 0..<3 where !advanced.isHittable { app.swipeUp() }
        XCTAssertTrue(advanced.exists)
        advanced.tap()

        let thinkingToggle = app.switches
            .matching(NSPredicate(format: "label CONTAINS %@", "思考を有効化"))
            .firstMatch
        XCTAssertTrue(thinkingToggle.waitForExistence(timeout: 10))
        let budget = app.textFields.matching(NSPredicate(
            format: "label CONTAINS %@ OR placeholderValue CONTAINS %@", "思考予算", "思考予算"
        )).firstMatch
        XCTAssertTrue(budget.exists, "Gemini model A should expose its thinking budget")
        capture("auto-model-a-advanced")

        let originalValue = thinkingToggle.value as? String
        thinkingToggle.switches.firstMatch.exists
            ? thinkingToggle.switches.firstMatch.tap()
            : thinkingToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let changedValue = thinkingToggle.value as? String
        XCTAssertNotEqual(originalValue, changedValue)
        app.swipeDown()
        sides.buttons["モデルB"].tap()
        XCTAssertFalse(thinkingToggle.exists, "Switching sides should collapse advanced controls")
        sides.buttons["モデルA"].tap()
        let restoredAdvanced = app.buttons["conversation-model-advanced"]
        if (restoredAdvanced.value as? String) != "展開中" { restoredAdvanced.tap() }
        XCTAssertTrue(thinkingToggle.waitForExistence(timeout: 10))
        XCTAssertEqual(thinkingToggle.value as? String, changedValue, "Edits must survive switching model sides")
    }

    func testDualModeEditsModelsAndPromptsWithoutAnotherScreen() throws {
        let app = launchConversationSettings(auto: false)
        app.buttons["conversation-dual-mode"].tap()
        let enabled = app.switches.matching(NSPredicate(format: "label CONTAINS %@", "デュアルモードを有効化")).firstMatch
        XCTAssertTrue(enabled.waitForExistence(timeout: 10))
        if (enabled.value as? String) != "1" {
            enabled.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        let sides = app.segmentedControls["conversation-model-side"]
        XCTAssertTrue(sides.waitForExistence(timeout: 10))
        capture("dual-mode-overview")
        sides.buttons["モデルB"].tap()
        let prompt = app.buttons["conversation-model-prompt"]
        for _ in 0..<3 where !prompt.isHittable { app.swipeUp() }
        prompt.tap()
        XCTAssertTrue(app.textViews["conversation-model-prompt-editor"].waitForExistence(timeout: 10)
            || app.textFields["conversation-model-prompt-editor"].exists)

    }

    private func launchConversationSettings(auto: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppStoreScreenshotDemo", "-ScreenshotScene", "list",
            "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"
        ]
        if auto { app.launchArguments.append("-AutoConversationFixture") }
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))
        let settings = app.buttons["open-settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        settings.tap()
        let conversation = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "プロンプト・モード")).firstMatch
        XCTAssertTrue(conversation.waitForExistence(timeout: 10))
        conversation.tap()
        XCTAssertTrue(app.buttons["conversation-auto-mode"].waitForExistence(timeout: 10))
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
