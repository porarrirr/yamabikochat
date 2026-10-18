import XCTest

final class AppInteractionPerformanceTests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSettingsNavigationAndScrollingCPU() throws {
        guard ProcessInfo.processInfo.environment["YAMABIKO_RENDER_BENCHMARK"] == "1" else {
            throw XCTSkip("Explicit application benchmark only")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshotDemo", "-ScreenshotScene", "list",
            "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        let settings = app.buttons["open-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 30))
        settings.tap()
        XCTAssertTrue(app.navigationBars["設定"].waitForExistence(timeout: 10))
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTCPUMetric(application: app), XCTMemoryMetric(application: app), XCTClockMetric()], options: options) {
            for (title, subtitle) in [("会話", "プロンプト・モード"), ("表示", "テーマ・プリセット・数式")] {
                let link = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", subtitle)).firstMatch
                XCTAssertTrue(link.waitForExistence(timeout: 5))
                XCTAssertTrue(link.isHittable)
                link.tap()
                let bar = app.navigationBars[title]
                XCTAssertTrue(bar.waitForExistence(timeout: 5))
                app.swipeUp(velocity: .fast)
                app.swipeDown(velocity: .fast)
                bar.buttons.firstMatch.tap()
            }
        }
        app.buttons["閉じる"].tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
    }

    func testScrollDrawerAndComposerCPU() throws {
        guard ProcessInfo.processInfo.environment["YAMABIKO_RENDER_BENCHMARK"] == "1" else {
            throw XCTSkip("Explicit application benchmark only")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshotDemo", "-ChatTimelinePerformanceFixture", "-ScreenshotScene", "performance",
            "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        let timeline = app.collectionViews["chat-timeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 30))
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTCPUMetric(application: app), XCTMemoryMetric(application: app), XCTClockMetric()], options: options) {
            for _ in 0..<3 { timeline.swipeDown(velocity: .fast) }
            for _ in 0..<3 { timeline.swipeUp(velocity: .fast) }
            for _ in 0..<2 {
                app.buttons["chat-history-button"].tap()
                let dismiss = app.buttons["conversation-drawer-dismiss"]
                XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
                dismiss.tap()
            }
            let composer = app.descendants(matching: .any).matching(identifier: "chat-composer").firstMatch
            composer.tap()
            composer.typeText("performance draft")
            composer.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 17))
            timeline.tap()
        }
        XCTAssertTrue(app.buttons["chat-history-button"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Interaction benchmark final screen"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
