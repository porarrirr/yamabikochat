import XCTest

final class GenUIUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testLoanInteractionResetAndPersistedDocumentReload() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshotDemo", "-GenUIFixture", "-ScreenshotScene", "chat", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        let slider = app.sliders["genui-slider-principal"]
        reveal(slider, in: app)
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        let metric = app.staticTexts["genui-metric-monthly"]
        reveal(metric, in: app)
        XCTAssertTrue(metric.waitForExistence(timeout: 5))
        let initialValue = metric.label
        XCTAssertFalse(initialValue.isEmpty)
        capture("genui-loan-initial")

        reveal(slider, in: app)
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
        reveal(chart, in: app)
        XCTAssertTrue(chart.exists)
        capture("genui-loan-chart")
        let table = app.descendants(matching: .any).matching(identifier: "genui-component-comparison").firstMatch
        reveal(table, in: app)
        XCTAssertTrue(table.exists)
        capture("genui-loan-table")

        app.terminate()
        app.launch()
        reveal(metric, in: app)
        XCTAssertTrue(metric.waitForExistence(timeout: 10))
        XCTAssertEqual(metric.label, initialValue)
        capture("genui-loan-reloaded")
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

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
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
