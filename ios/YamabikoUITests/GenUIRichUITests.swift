import XCTest

final class GenUIRichUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    func testPowerSlidersUpdateThroughoutRepeatedDrags() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshotDemo", "-GenUIRichFixture", "-GenUIPowersFixture", "-ScreenshotScene", "chat", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        let base = app.sliders["底"].firstMatch
        let exponent = app.sliders["指数"].firstMatch
        XCTAssertTrue(base.waitForExistence(timeout: 20))
        reveal(base, in: app)
        for index in 0..<3 {
            base.coordinate(withNormalizedOffset: CGVector(dx: index == 0 ? 0.25 : 0.05, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: base.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)))
            XCTAssertTrue(app.staticTexts["pow(5, 3) = 125"].firstMatch.waitForExistence(timeout: 5))
            base.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
                .press(forDuration: 0.05, thenDragTo: base.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)))
            XCTAssertTrue(app.staticTexts["pow(1, 3) = 1"].firstMatch.waitForExistence(timeout: 5))
        }
        reveal(exponent, in: app)
        exponent.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: exponent.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5)))
        XCTAssertTrue(app.staticTexts["pow(1, 0) = 1"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(base.exists && exponent.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "GenUI error")).firstMatch.exists)
        capture("genui-powers-after-repeated-drags")
    }

    func testExplanatoryDiagramsAndSavedLineBreaks() {
        let app = XCUIApplication()
        let base = ["-AppStoreScreenshotDemo", "-GenUIRichFixture", "-ScreenshotScene", "chat", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launchArguments = base + ["-GenUIAuthenticationFixture"]
        app.launch()
        let next = app.buttons["次のステップ"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 20))
        reveal(next, in: app)
        next.tap()
        XCTAssertTrue(app.staticTexts["現在：本人確認を行う"].firstMatch.waitForExistence(timeout: 5))
        capture("genui-authentication-explanation")
        app.terminate()
        app.launchArguments = base + ["-GenUIPowersFixture"]
        app.launch()
        XCTAssertTrue(app.staticTexts["pow(2, 3) = 8"].firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(app.sliders["底"].firstMatch.exists)
        XCTAssertTrue(app.sliders["指数"].firstMatch.exists)
        capture("genui-powers-explanation")
        app.terminate()
        app.launchArguments = base + ["-GenUILineBreakFixture"]
        app.launch()
        let flow = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "① ユーザー")).firstMatch
        XCTAssertTrue(flow.waitForExistence(timeout: 20))
        // Nine authored lines use 24pt line boxes; accessibility reports slightly shorter glyph bounds.
        XCTAssertGreaterThanOrEqual(flow.frame.height, 9 * 24 - 4)
        capture("genui-saved-flow-line-breaks")
    }

    func testOriginalComponentsRunInConversation() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshotDemo", "-GenUIRichFixture", "-GenUIOriginalFixture", "-ScreenshotScene", "chat", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        XCTAssertTrue(app.staticTexts["1:30"].firstMatch.waitForExistence(timeout: 20))
        for _ in 0..<4 where !app.staticTexts["36"].firstMatch.exists { app.collectionViews["chat-timeline"].swipeDown() }
        capture("genui-original-initial")
        XCTAssertTrue(app.staticTexts["36"].firstMatch.exists, app.debugDescription)
        let play = app.buttons["▶"].firstMatch
        reveal(play, in: app)
        play.tap()
        XCTAssertTrue(app.buttons["⏸︎"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["⏸︎"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["09:00"].firstMatch.exists)
        capture("genui-original-components")
        let more = app.buttons["Show 2 more"].firstMatch
        reveal(more, in: app)
        more.tap()
        XCTAssertTrue(app.staticTexts["現地の連絡先"].firstMatch.waitForExistence(timeout: 5))
        capture("genui-original-checklist")
        app.terminate()
        app.launchArguments.append("-GenUIDarkFixture")
        app.launch()
        XCTAssertTrue(app.staticTexts["1:30"].firstMatch.waitForExistence(timeout: 20))
        capture("genui-original-dark")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "could not be rendered")).firstMatch.exists)
    }

    func testReferenceCompositionUpdatesAndFlipsLearningCard() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshotDemo", "-GenUIRichFixture", "-GenUIReferenceFixture", "-ScreenshotScene", "chat", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        XCTAssertTrue(app.webViews["genui-rich-canvas"].firstMatch.waitForExistence(timeout: 20))
        let canvas = app.webViews["genui-rich-canvas"].firstMatch
        let cell = app.collectionViews["chat-timeline"].cells.firstMatch
        let income = app.sliders["手取り収入"].firstMatch
        reveal(income, in: app)
        XCTAssertTrue(app.staticTexts["125,000円"].firstMatch.exists)
        XCTAssertGreaterThanOrEqual(cell.frame.height, canvas.frame.height)
        capture("genui-reference-controls")
        income.coordinate(withNormalizedOffset: CGVector(dx: 0.4, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: income.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)))
        XCTAssertFalse(app.staticTexts["125,000円"].firstMatch.exists)
        let learn = app.descendants(matching: .any).matching(identifier: "考え方").firstMatch
        reveal(learn, in: app)
        learn.tap()
        let question = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "貯蓄に回せる金額は？")).firstMatch
        reveal(question, in: app)
        question.tap()
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "収入 − 住居費 − その他の支出")).firstMatch.waitForExistence(timeout: 5))
        capture("genui-reference-learning")
        app.terminate()
        app.launchArguments.append("-GenUIDarkFixture")
        app.launch()
        XCTAssertTrue(app.webViews["genui-rich-canvas"].firstMatch.waitForExistence(timeout: 20))
        let darkLearn = app.descendants(matching: .any).matching(identifier: "考え方").firstMatch
        reveal(darkLearn, in: app)
        darkLearn.tap()
        let darkCard = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "貯蓄に回せる金額は？")).firstMatch
        reveal(darkCard, in: app)
        capture("genui-reference-dark")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "GenUI error")).firstMatch.exists)
    }

    func testSavedTextMarkdownRendersHeadingsAndCode() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshotDemo", "-GenUIRichFixture", "-GenUIMarkdownFixture", "-ScreenshotScene", "chat", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        XCTAssertTrue(app.webViews["genui-rich-canvas"].firstMatch.waitForExistence(timeout: 20))
        let heading = app.staticTexts["使い方"].firstMatch
        reveal(heading, in: app)
        XCTAssertTrue(heading.exists, app.debugDescription)
        let commands = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "git worktree add")).firstMatch
        reveal(commands, in: app)
        XCTAssertTrue(commands.exists, app.debugDescription)
        XCTAssertTrue(commands.label.contains("\ncd ../repo-feature\n"))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "```bash")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "### 使い方")).firstMatch.exists)
        capture("genui-markdown-text")
    }

    func testWorktreeDiagramSelectionAndEdits() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshotDemo", "-GenUIRichFixture", "-GenUIWorktreeFixture", "-ScreenshotScene", "chat", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        XCTAssertTrue(app.webViews["genui-rich-canvas"].firstMatch.waitForExistence(timeout: 20))
        let edit = app.buttons["ファイルを編集（デモ）"].firstMatch
        reveal(edit, in: app)
        edit.tap()
        let main = app.buttons["project/ · main · 変更あり"].firstMatch
        reveal(main, in: app)
        XCTAssertTrue(main.exists)
        let feature = app.buttons["project-feature/ · feature/login · 変更なし"].firstMatch
        reveal(feature, in: app)
        feature.tap()
        reveal(edit, in: app)
        edit.tap()
        let editedFeature = app.buttons["project-feature/ · feature/login · 変更あり"].firstMatch
        reveal(editedFeature, in: app)
        XCTAssertTrue(editedFeature.exists)
        XCTAssertTrue(main.exists)
        capture("genui-worktree-interactive")
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "GenUI error")).firstMatch.exists)
    }

    func testFlowDiagramAndSimulator() {
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshotDemo", "-GenUIRichFixture", "-GenUIFlowFixture", "-ScreenshotScene", "chat", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        XCTAssertTrue(app.webViews["genui-rich-canvas"].firstMatch.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["取引データを収集"].firstMatch.waitForExistence(timeout: 10))
        let no = app.staticTexts["いいえ"].firstMatch
        let yes = app.staticTexts["はい"].firstMatch
        XCTAssertTrue(no.exists && yes.exists)
        XCTAssertLessThan(abs(no.frame.minY - yes.frame.minY), 8)
        XCTAssertLessThan(no.frame.maxX, yes.frame.minX)
        app.swipeDown()
        app.swipeDown()
        capture("genui-flow-diagram")

        // Test the same simulator code in a short document so WebKit's offscreen
        // accessibility coordinates cannot redirect a drag to the chat drawer.
        app.terminate()
        app.launchArguments.append("-GenUISimulatorFixture")
        app.launch()
        let slider = app.sliders["難易度"].firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 20))
        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.33, dy: 0.5))
            .press(forDuration: 0.05, thenDragTo: slider.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        XCTAssertTrue(app.staticTexts["平均試行回数"].firstMatch.exists)
        XCTAssertFalse(app.staticTexts["16回"].exists)
        app.swipeUp()
        let reset = app.buttons["初期値に戻す"].firstMatch
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reveal(reset, in: app)
        reset.tap()
        XCTAssertTrue(app.staticTexts["16回"].waitForExistence(timeout: 5))
        capture("genui-flow-simulator")
    }

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
        first.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        first.typeText(XCUIKeyboardKey.delete.rawValue + "12")
        app.swipeDown()
        XCTAssertTrue(app.staticTexts["合計 12枚"].waitForExistence(timeout: 5))
        app.swipeDown() // Dismiss keyboard before capturing the content-sized card.
        let reference = app.buttons["日本銀行「通貨流通高」"].firstMatch
        reveal(reference, in: app)
        let description = app.staticTexts["日本銀行のページで硬貨の種類別データを確認できます。"].firstMatch
        XCTAssertLessThan(reference.frame.minY - description.frame.maxY, 30)
        // Content-measured documents are not limited to a fixed canvas height.
        // Their full drawing and hit area must belong to the collection cell.
        XCTAssertGreaterThanOrEqual(app.collectionViews["chat-timeline"].cells.firstMatch.frame.height, canvas.frame.height)
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
            // A content-sized web view can extend beyond the screen. Swipe only
            // within its visible intersection, away from horizontal controls.
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let x = min(app.frame.maxX - 24, canvas.frame.maxX - 24) - app.frame.minX
            let startY = top + (bottom - top) * (movingDown ? 0.3 : 0.75)
            let endY = top + (bottom - top) * (movingDown ? 0.75 : 0.3)
            origin.withOffset(CGVector(dx: x, dy: startY - app.frame.minY))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: x, dy: endY - app.frame.minY)))
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
