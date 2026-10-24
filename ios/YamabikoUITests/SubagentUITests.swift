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
        let output = app.textViews.containing(NSPredicate(format: "value CONTAINS %@", "実装確認の途中結果")).firstMatch
        XCTAssertTrue(output.waitForExistence(timeout: 5))
        XCTAssertTrue((output.value as? String)?.contains("実装確認の途中結果") == true)
        XCTAssertFalse((output.value as? String)?.contains("**設定**") == true)
        let heading = app.textViews.containing(NSPredicate(format: "value CONTAINS %@", "実装確認の確認結果")).firstMatch
        XCTAssertTrue(heading.exists)
        XCTAssertFalse((heading.value as? String)?.contains("## ") == true)
        XCTAssertTrue(app.staticTexts["Effort: medium"].exists)
        XCTAssertTrue(app.staticTexts["実装確認を担当してください。確認した根拠と具体的な結果を日本語で報告してください。"].exists)
        XCTAssertFalse(app.buttons["再生成"].isHittable)
        XCTAssertFalse(app.buttons["分岐"].isHittable)
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
        let output = app.textViews.containing(NSPredicate(format: "value CONTAINS %@", "ライブ更新の結果")).firstMatch
        XCTAssertTrue(output.waitForExistence(timeout: 20))
        capture("subagents-detail-live")
    }

    func testModelSettingsExposeProviderModelAndSupportedEffort() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshotDemo", "-SubagentFixture", "-ScreenshotScene", "settings-dual", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        let settings = app.buttons["settings-subagents"]
        XCTAssertTrue(app.navigationBars.firstMatch.waitForExistence(timeout: 15))
        if !app.navigationBars["会話"].exists {
            let conversation = app.staticTexts["会話"]
            XCTAssertTrue(conversation.waitForExistence(timeout: 5))
            conversation.tap()
        }
        XCTAssertTrue(app.navigationBars["会話"].waitForExistence(timeout: 5))
        for _ in 0..<8 where !settings.isHittable { app.swipeUp() }
        XCTAssertTrue(settings.exists)
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
        let delete = app.buttons["subagent-profile-delete"]
        for _ in 0..<5 where !delete.isHittable { app.swipeUp() }
        XCTAssertTrue(delete.exists)
        delete.tap()
        // The confirmation must be a centered alert; anchoring a confirmation
        // dialog to the form itself places it over the delete row.
        let confirmation = app.alerts["このモデル設定を削除しますか？"]
        XCTAssertTrue(confirmation.waitForExistence(timeout: 5))
        XCTAssertEqual(app.popovers.count, 0)
        capture("subagents-model-delete-confirmation")
        confirmation.buttons["削除"].tap()
        XCTAssertTrue(app.buttons["subagent-profile-add"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["モデル設定 1"].exists)
        capture("subagents-model-deleted")
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
