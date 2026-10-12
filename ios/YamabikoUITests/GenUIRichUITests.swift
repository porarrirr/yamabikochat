import XCTest

final class GenUIRichUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testSharedJavaScriptStateResetCopyAndMap() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshotDemo", "-GenUIRichFixture", "-ScreenshotScene", "chat", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        let slider = app.sliders.firstMatch
        reveal(slider, in: app)
        XCTAssertTrue(slider.waitForExistence(timeout: 10))
        let initialSliderValue = slider.value as? String
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        XCTAssertNotEqual(slider.value as? String, initialSliderValue)
        let adjusted = app.staticTexts.matching(NSPredicate(format: "label MATCHES %@ AND label != %@", "^[0-9]+%$", "65%")).firstMatch
        reveal(adjusted, in: app)
        XCTAssertTrue(adjusted.waitForExistence(timeout: 5))
        capture("genui-rich-state")

        let reset = app.buttons["初期値に戻す"].firstMatch
        reveal(reset, in: app)
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.tap()
        let original = app.staticTexts["65%"].firstMatch
        reveal(original, in: app)
        XCTAssertTrue(original.waitForExistence(timeout: 5))

        let map = app.buttons["Open map"].firstMatch
        reveal(map, in: app)
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        map.tap()
        let mapNavigation = app.navigationBars["東京の地点"]
        XCTAssertTrue(mapNavigation.waitForExistence(timeout: 10))
        capture("genui-rich-map")
        app.buttons["閉じる"].firstMatch.tap()
        let copy = app.buttons["状態をコピー"].firstMatch
        reveal(copy, in: app)
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
        let status = app.staticTexts["コピーしました"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))


        reveal(map, in: app)
        map.tap()
        XCTAssertTrue(mapNavigation.waitForExistence(timeout: 10))
        app.buttons["閉じる"].firstMatch.tap()

    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        guard element.waitForExistence(timeout: 10) else {
            XCTFail("Expected GenUI element did not appear")
            return
        }
        let canvas = app.webViews["genui-rich-canvas"].firstMatch
        for _ in 0..<18 {
            let top = max(app.frame.minY + 150, canvas.frame.minY + 30)
            let bottom = min(app.frame.maxY - 150, canvas.frame.maxY - 40)
            let frame = element.frame
            if element.isHittable, frame.midY > top, frame.midY < bottom {
                Thread.sleep(forTimeInterval: 1)
                return
            }
            if element.exists, frame.midY <= top { canvas.swipeDown() } else { canvas.swipeUp() }
        }
        XCTAssertTrue(element.isHittable, "GenUI element must be hittable after scrolling")
        Thread.sleep(forTimeInterval: 1)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
