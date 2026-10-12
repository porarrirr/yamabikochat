import XCTest

final class GenUIUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLoanInteractionResetAndPersistedDocumentReload() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshotDemo", "-GenUIFixture", "-ScreenshotScene", "chat", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        let title = app.staticTexts["住宅ローンを比較"]
        let summaryChart = app.descendants(matching: .any).matching(identifier: "genui-component-repayment_chart").firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertTrue(summaryChart.waitForExistence(timeout: 10))
        XCTAssertLessThan(summaryChart.frame.maxY - title.frame.minY, app.frame.height * 0.65)
        capture("genui-mobile-summary")
        let slider = app.sliders["genui-slider-principal"]
        XCTAssertFalse(slider.exists)
        reveal(slider, in: app, section: "条件")
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        let metric = app.staticTexts["genui-metric-monthly"]
        reveal(metric, in: app)
        XCTAssertTrue(metric.waitForExistence(timeout: 5))
        let initialValue = metric.label
        XCTAssertFalse(initialValue.isEmpty)
        capture("genui-loan-initial")

        reveal(slider, in: app, section: "条件")
        slider.adjust(toNormalizedSliderPosition: 0.85)
        reveal(metric, in: app)
        XCTAssertNotEqual(metric.label, initialValue)
        capture("genui-loan-adjusted")

        let reset = app.buttons["genui-reset"]
        reveal(reset, in: app)
        reset.tap()
        reveal(metric, in: app)
        XCTAssertEqual(metric.label, initialValue)

        let chart = app.descendants(matching: .any).matching(identifier: "genui-component-repayment_chart").firstMatch
        reveal(chart, in: app, section: "結果")
        XCTAssertTrue(chart.exists)
        capture("genui-loan-chart")
        let table = app.descendants(matching: .any).matching(identifier: "genui-component-comparison").firstMatch
        reveal(table, in: app, section: "結果", detailLabel: "金利を比較")
        XCTAssertTrue(table.exists)
        capture("genui-loan-table")

        app.terminate()
        app.launch()
        reveal(metric, in: app)
        XCTAssertTrue(metric.waitForExistence(timeout: 10))
        XCTAssertEqual(metric.label, initialValue)
        capture("genui-loan-reloaded")
    }

    func testTranscriptOnlyDocumentRendersAndRemainsInteractiveAfterReload() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppStoreScreenshotDemo", "-GenUIFixture", "-GenUITranscriptOnlyFixture",
            "-ScreenshotScene", "chat", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"
        ]
        app.launch()
        let slider = app.sliders["genui-slider-principal"]
        reveal(slider, in: app, section: "条件")
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        let metric = app.staticTexts["genui-metric-monthly"]
        reveal(metric, in: app)
        XCTAssertTrue(metric.waitForExistence(timeout: 5))
        let initialValue = metric.label
        reveal(slider, in: app, section: "条件")
        slider.adjust(toNormalizedSliderPosition: 0.85)
        reveal(metric, in: app)
        XCTAssertNotEqual(metric.label, initialValue)
        capture("genui-transcript-recovered")

        app.terminate()
        app.launch()
        reveal(metric, in: app)
        XCTAssertTrue(metric.waitForExistence(timeout: 10))
        XCTAssertEqual(metric.label, initialValue)
    }

    func testLoanDarkAppearanceScreenshot() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppStoreScreenshotDemo", "-GenUIFixture", "-GenUIDarkFixture",
            "-ScreenshotScene", "chat", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"
        ]
        app.launch()
        let metric = app.staticTexts["genui-metric-monthly"]
        reveal(metric, in: app)
        XCTAssertTrue(metric.waitForExistence(timeout: 10))
        capture("genui-loan-dark")
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication, section: String? = nil, detailLabel: String? = nil) {
        if let section {
            let sections = app.segmentedControls["genui-section-picker"]
            XCTAssertTrue(sections.waitForExistence(timeout: 10))
            revealSection(section, sections: sections, in: app)
        }
        if let detailLabel, !element.exists {
            let detail = app.buttons[detailLabel]
            XCTAssertTrue(detail.waitForExistence(timeout: 5))
            revealOnTimeline(detail, in: app)
            detail.tap()
        }
        XCTAssertTrue(element.waitForExistence(timeout: 10))
        revealOnTimeline(element, in: app)
    }

    private func revealSection(_ title: String, sections: XCUIElement, in app: XCUIApplication) {
        let button = sections.buttons[title]
        if button.exists && !button.isSelected {
            revealOnTimeline(button, in: app)
            button.tap()
        }
    }

    private func revealOnTimeline(_ element: XCUIElement, in app: XCUIApplication) {
        if element.isHittable { return }
        for _ in 0..<6 {
            app.swipeDown()
            if element.isHittable { return }
        }
        for _ in 0..<12 {
            app.swipeUp()
            if element.isHittable { return }
        }
    }

    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        guard let output = ProcessInfo.processInfo.environment["SCREENSHOT_OUTPUT_DIR"] else { return }
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        XCTAssertNoThrow(try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true))
        XCTAssertNoThrow(try screenshot.pngRepresentation.write(to: directory.appendingPathComponent("\(name).png")))
    }
}
