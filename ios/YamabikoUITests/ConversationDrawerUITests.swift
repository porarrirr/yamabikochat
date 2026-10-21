import XCTest

final class ConversationDrawerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testRelaunchOpensNewChatWhileForegroundKeepsCurrentConversation() {
        let app = launchConversation()
        let message = app.textViews.matching(identifier: "selectable-chat-text").firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 10))

        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(message.waitForExistence(timeout: 10))

        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()

        XCTAssertTrue(app.buttons["chat-history-button"].waitForExistence(timeout: 20))
        let composer = app.descendants(matching: .any).matching(identifier: "chat-composer").firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        XCTAssertFalse(message.exists)
        XCTAssertFalse(app.buttons["conversation-drawer-dismiss"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "New chat after relaunch"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["chat-history-button"].tap()
        let previousConversation = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "Text Selection Fixture")
        ).firstMatch
        XCTAssertTrue(previousConversation.waitForExistence(timeout: 5))
        previousConversation.tap()
        XCTAssertTrue(message.waitForExistence(timeout: 10))
    }

    func testHeaderButtonOpensSlidingListAndBackdropClosesItRepeatedly() {
        let app = launchConversation()
        let headerButton = app.buttons["chat-history-button"]
        let initialX = headerButton.frame.minX

        for _ in 0..<2 {
            headerButton.tap()
            let dismiss = app.buttons["conversation-drawer-dismiss"]
            XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["sidebar-new-chat"].isHittable)
            XCTAssertEqual(dismiss.frame.minX, app.windows.firstMatch.frame.width * 0.7, accuracy: 1)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Conversation drawer open"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            dismiss.tap()
            XCTAssertTrue(headerButton.waitForExistence(timeout: 5))
            XCTAssertEqual(headerButton.frame.minX, initialX, accuracy: 1)
        }
    }

    func testHorizontalSwipeOpensAndClosesWhileVerticalAndDiagonalDragsStayInChat() {
        let app = launchConversation()
        let window = app.windows.firstMatch

        drag(window, from: CGVector(dx: 0.15, dy: 0.65), to: CGVector(dx: 0.2, dy: 0.35))
        XCTAssertFalse(app.buttons["conversation-drawer-dismiss"].exists)
        drag(window, from: CGVector(dx: 0.12, dy: 0.6), to: CGVector(dx: 0.4, dy: 0.35))
        XCTAssertFalse(app.buttons["conversation-drawer-dismiss"].exists)

        drag(window, from: CGVector(dx: 0.04, dy: 0.5), to: CGVector(dx: 0.8, dy: 0.5))
        XCTAssertTrue(app.buttons["conversation-drawer-dismiss"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sidebar-new-chat"].isHittable)
        drag(window, from: CGVector(dx: 0.96, dy: 0.5), to: CGVector(dx: 0.15, dy: 0.5))
        XCTAssertTrue(app.buttons["chat-history-button"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["conversation-drawer-dismiss"].exists)
    }

    func testSelectingConversationClosesDrawerAndComposerSwipeDoesNotOpenIt() {
        let app = launchConversation()
        app.buttons["chat-history-button"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Text Selection Fixture")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        XCTAssertTrue(app.buttons["chat-history-button"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["conversation-drawer-dismiss"].exists)

        let composer = app.descendants(matching: .any).matching(identifier: "chat-composer").firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        composer.tap()
        composer.typeText("draft")
        let start = composer.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        let end = composer.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertFalse(app.buttons["conversation-drawer-dismiss"].exists)
        XCTAssertEqual(composer.value as? String, "draft")
    }

    func testSwipeStartingOnMessageTextOpensDrawer() {
        let app = launchConversation()
        let message = app.textViews.matching(identifier: "selectable-chat-text").firstMatch
        XCTAssertTrue(message.waitForExistence(timeout: 5))
        message.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(
            forDuration: 0.05,
            thenDragTo: message.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5))
        )
        XCTAssertTrue(app.buttons["conversation-drawer-dismiss"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["sidebar-new-chat"].isHittable)
    }

    func testLeftSwipeOnConversationRowClosesDrawerInsteadOfRevealingRowActions() {
        let app = launchConversation()
        app.buttons["chat-history-button"].tap()
        let dismiss = app.buttons["conversation-drawer-dismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Text Selection Fixture")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.5)).press(
            forDuration: 0.05,
            thenDragTo: row.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.5))
        )
        XCTAssertTrue(app.buttons["chat-history-button"].waitForExistence(timeout: 5))
        XCTAssertFalse(dismiss.exists)
        app.buttons["chat-history-button"].tap()
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["開く"].exists)
        XCTAssertFalse(app.buttons["削除"].exists)
    }

    func testVerticalSidebarDragStaysOpenAndDeletionRemainsInContextMenu() {
        let app = launchConversation()
        app.buttons["chat-history-button"].tap()
        let dismiss = app.buttons["conversation-drawer-dismiss"]
        XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
        drag(app.windows.firstMatch, from: CGVector(dx: 0.35, dy: 0.45), to: CGVector(dx: 0.36, dy: 0.7))
        XCTAssertTrue(dismiss.exists)
        XCTAssertTrue(app.buttons["sidebar-new-chat"].isHittable)
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Text Selection Fixture")).firstMatch
        XCTAssertTrue(row.isHittable)
        row.press(forDuration: 1)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Conversation drawer context menu"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertTrue(app.buttons["削除"].waitForExistence(timeout: 5), app.debugDescription)
    }

    private func launchConversation() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppStoreScreenshotDemo", "-ChatTextSelectionFixture", "-ScreenshotScene", "list",
            "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"
        ]
        app.launch()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Text Selection Fixture")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        XCTAssertTrue(app.buttons["chat-history-button"].waitForExistence(timeout: 10))
        return app
    }

    private func drag(_ window: XCUIElement, from: CGVector, to: CGVector) {
        window.coordinate(withNormalizedOffset: from).press(
            forDuration: 0.05, thenDragTo: window.coordinate(withNormalizedOffset: to)
        )
    }
}

final class MathRenderingUITests: XCTestCase {
    func testDisplaySettingsHasNoMathRenderingToggle() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshotDemo", "-ScreenshotScene", "settings-appearance", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        XCTAssertTrue(app.navigationBars["表示"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.switches["数式レンダリング"].exists)
        app.swipeUp()
        XCTAssertFalse(app.switches["数式レンダリング"].exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Display settings without math toggle"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testSurfaceAreaMathInChat() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshotDemo", "-ScreenshotScene", "chat", "-MathRenderingFixture", "-MathDarkFixture", "-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"]
        app.launch()
        XCTAssertTrue(app.buttons["chat-history-button"].waitForExistence(timeout: 20))
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 20))
        for _ in 0..<6 { app.swipeDown() }
        let beginning = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "サブエージェント3つに、")
        ).firstMatch
        XCTAssertTrue(beginning.waitForExistence(timeout: 10))
        XCTAssertTrue(beginning.isHittable, "The response beginning must be visible below the user bubble")
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = "Surface area response beginning below user message"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
