import XCTest

final class SubagentUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testThreeChildrenStayCompactAndDetailShowsTaskActionsAndOutput() {
        let app = launch()
        let summary = app.buttons["subagent-fleet-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        XCTAssertLessThan(summary.frame.height, 85)
        XCTAssertFalse(app.buttons["subagent-row-fixture-0"].exists)
        capture("subagents-collapsed")
        summary.tap()
        let row = app.buttons["subagent-row-fixture-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        capture("subagents-expanded")
        row.tap()
        let output = app.staticTexts["subagent-output"]
        XCTAssertTrue(output.waitForExistence(timeout: 5))
        XCTAssertTrue(output.label.contains("実装確認の途中結果"))
        XCTAssertTrue(app.staticTexts["Effort: medium"].exists)
        capture("subagents-detail")
        app.segmentedControls.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "処理履歴")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["fetch_url"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["公式ドキュメントの該当箇所を取得しました。"].exists)
        capture("subagents-actions")
        app.buttons["閉じる"].tap()
        summary.tap()
        XCTAssertFalse(app.buttons["subagent-row-fixture-1"].exists)
    }

    func testOpenDetailReceivesLiveUpdates() {
        let app = launch(live: true)
        let summary = app.buttons["subagent-fleet-summary"]
        XCTAssertTrue(summary.waitForExistence(timeout: 15))
        summary.tap()
        let row = app.buttons["subagent-row-fixture-1"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        let output = app.staticTexts["subagent-output"]
        XCTAssertTrue(output.waitForExistence(timeout: 5))
        let updated = NSPredicate(format: "label CONTAINS %@", "ライブ更新の結果")
        expectation(for: updated, evaluatedWith: output)
        waitForExpectations(timeout: 20)
        capture("subagents-detail-live")
    }

    func testModelSettingsExposeProviderModelAndSupportedEffort() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshotDemo", "-SubagentFixture", "-ScreenshotScene", "settings-dual", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        let settings = app.buttons["settings-subagents"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        for _ in 0..<5 where !settings.isHittable { app.swipeUp() }
        settings.tap()
        XCTAssertTrue(app.switches["subagents-enabled"].waitForExistence(timeout: 5))
        capture("subagents-settings")
        app.buttons["subagent-profile-add"].tap()
        let profile = app.staticTexts["モデル設定 1"]
        XCTAssertTrue(profile.waitForExistence(timeout: 5))
        profile.tap()
        XCTAssertTrue(app.textFields["subagent-profile-name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["provider-picker-field"].exists)
        let effort = app.buttons["subagent-effort-picker"]
        XCTAssertTrue(effort.waitForExistence(timeout: 10))
        expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: effort)
        waitForExpectations(timeout: 15)
        effort.tap()
        XCTAssertTrue(app.buttons["high"].waitForExistence(timeout: 5))
        app.buttons["high"].tap()
        capture("subagents-model-effort")
    }

    private func launch(live: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshotDemo", "-SubagentFixture", "-ScreenshotScene", "chat", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        if live { app.launchArguments.append("-SubagentLiveFixture") }
        app.launch()
        return app
    }

    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        if let output = ProcessInfo.processInfo.environment["SCREENSHOT_OUTPUT_DIR"] {
            let directory = URL(fileURLWithPath: output, isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try? screenshot.pngRepresentation.write(to: directory.appendingPathComponent("\(name).png"))
        }
    }
}
