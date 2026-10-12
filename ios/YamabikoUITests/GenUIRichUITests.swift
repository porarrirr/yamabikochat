import XCTest

final class GenUIRichUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testCompactCoinInputsAndReferenceHaveNoOversizedWhitespace() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshotDemo", "-GenUIRichFixture", "-GenUICompactFixture", "-ScreenshotScene", "chat", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        let canvas = app.webViews["genui-rich-canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 20))
        let first = app.textFields["coin-1"].firstMatch
        let second = app.textFields["coin-2"].firstMatch
        reveal(first, in: app)
        XCTAssertTrue(second.waitForExistence(timeout: 5))
        XCTAssertLessThan(abs(second.frame.minY - first.frame.minY), 70)
        XCTAssertGreaterThanOrEqual(first.frame.height, 44)
        first.tap()
        first.typeText("12")
        XCTAssertTrue(app.staticTexts["合計 12枚"].waitForExistence(timeout: 5))
        app.swipeDown() // Dismiss keyboard before capturing the content-sized card.
        let reference = app.buttons["日本銀行「通貨流通高」"].firstMatch
        reveal(reference, in: app)
        let description = app.staticTexts["日本銀行のページで硬貨の種類別データを確認できます。"].firstMatch
        XCTAssertLessThan(reference.frame.minY - description.frame.maxY, 30)
        XCTAssertLessThanOrEqual(canvas.frame.height, 560)
        capture("genui-compact-inputs-and-reference")
    }

    func testInlineMapIsVisibleWithoutOpeningAnotherScreen() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshotDemo", "-GenUIRichFixture", "-GenUIInlineMapFixture", "-ScreenshotScene", "chat", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        let map = app.maps.firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["Open map"].exists)
        XCTAssertFalse(app.navigationBars["徒歩ルート（大手門）"].exists)
        let canvas = app.webViews["genui-rich-canvas"].firstMatch
        XCTAssertTrue(canvas.frame.intersects(map.frame))
        XCTAssertTrue(map.isHittable)
        capture("genui-inline-map")
        let hide = app.buttons["地図を隠す"].firstMatch
        reveal(hide, in: app)
        hide.tap()
        XCTAssertTrue(map.waitForNonExistence(timeout: 5))
        let show = app.buttons["地図を表示"].firstMatch
        reveal(show, in: app)
        show.tap()
        XCTAssertTrue(map.waitForExistence(timeout: 10))
    }

    func testSharedJavaScriptStateResetCopyAndMap() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshotDemo", "-GenUIRichFixture", "-GenUIRichStateFixture", "-ScreenshotScene", "chat", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
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

        let map = app.maps.firstMatch
        reveal(map, in: app)
        XCTAssertTrue(map.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Open map"].exists)
        capture("genui-rich-map")
        let copy = app.buttons["状態をコピー"].firstMatch
        reveal(copy, in: app)
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
        let status = app.staticTexts["コピーしました"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))


        reveal(map, in: app)
        XCTAssertTrue(map.isHittable)

    }

    func testCaptureCatalogScreensForSpec() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshotDemo", "-GenUIRichFixture", "-ScreenshotScene", "chat", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        let canvas = app.webViews["genui-rich-canvas"].firstMatch
        XCTAssertTrue(canvas.waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 3)
        capture("00_GenUI_実画面")

        let sections = ["文字・装飾", "レイアウト", "入力・操作", "表・リスト", "複合表示", "メディア・アイコン", "グラフ", "地図", "参照・遷移", "埋め込み・コード", "SVG図形"]
        for (index, name) in sections.enumerated() {
            let heading = app.staticTexts[name].firstMatch
            reveal(heading, in: app)
            capture(String(format: "%02d_%@", index + 1, name))
            if name == "地図" {
                let map = app.maps.firstMatch
                reveal(map, in: app)
                XCTAssertTrue(map.waitForExistence(timeout: 5))
                XCTAssertFalse(app.buttons["Open map"].exists)
                capture("08_MapKit_実画面")
            }
        }
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        guard element.waitForExistence(timeout: 10) else {
            XCTFail("Expected GenUI element did not appear")
            return
        }
        let canvas = app.webViews["genui-rich-canvas"].firstMatch
        for _ in 0..<18 {
            let top = max(app.frame.minY + 150, canvas.frame.minY + 12)
            let bottom = min(app.frame.maxY - 150, canvas.frame.maxY - 12)
            let frame = element.frame
            if element.isHittable, frame.midY > top, frame.midY < bottom {
                Thread.sleep(forTimeInterval: 1)
                return
            }
            let movingDown = element.exists && frame.midY <= top
            canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: movingDown ? 0.4 : 0.7))
                .press(forDuration: 0.05, thenDragTo: canvas.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: movingDown ? 0.7 : 0.4)))
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
