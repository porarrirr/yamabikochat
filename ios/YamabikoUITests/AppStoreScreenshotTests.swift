import XCTest

final class AppStoreScreenshotTests: XCTestCase {
    private var outputDirectory: URL {
        let env = ProcessInfo.processInfo.environment["SCREENSHOT_OUTPUT_DIR"] ?? ""
        if env.isEmpty {
            return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("AppStoreScreenshots", isDirectory: true)
        }
        return URL(fileURLWithPath: env, isDirectory: true)
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
    }

    func testCaptureAppStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshotDemo"]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        sleep(3)

        navigateToConversationList(app: app)
        sleep(1)
        capture("01-conversation-list", app: app)

        openConversation(app: app, title: "Markdown 数式", fallbackTitle: "旅行プラン")
        sleep(4)
        capture("02-chat-markdown", app: app)

        XCTAssertTrue(openSettings(app: app))
        XCTAssertTrue(openSettingsCategory(app: app, subtitle: "API・モデル", title: "接続"))
        capture("03-settings-api", app: app)

        XCTAssertTrue(returnToSettingsIndex(app: app))
        XCTAssertTrue(openSettingsCategory(app: app, subtitle: "テーマ・プリセット・数式", title: "表示"))
        capture("04-settings-appearance", app: app)

        XCTAssertTrue(returnToSettingsIndex(app: app))
        XCTAssertTrue(openSettingsCategory(app: app, subtitle: "プロンプト・モード", title: "会話"))
        XCTAssertTrue(scrollToText(app: app, text: "デュアルモード"))
        capture("05-settings-dual", app: app)

        XCTAssertTrue(scrollToText(app: app, text: "自動会話"))
        capture("08-settings-auto", app: app)

        XCTAssertTrue(returnToSettingsIndex(app: app))
        closeSettings(app: app)

        if UIDevice.current.userInterfaceIdiom == .pad {
            capture("06-ipad-split-view", app: app)
            XCUIDevice.shared.orientation = .landscapeLeft
            sleep(2)
            capture("07-ipad-landscape", app: app)
            XCUIDevice.shared.orientation = .portrait
            sleep(1)
        } else {
            navigateToConversationList(app: app)
            if app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "仕事用")).firstMatch.waitForExistence(timeout: 3) {
                app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "仕事用")).firstMatch.tap()
                sleep(1)
                capture("06-project-conversations", app: app)
            }
        }

    }

    func testProviderSelectionChangesProvider() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshotDemo"]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        XCTAssertTrue(openSettings(app: app))
        let connectionRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "API・モデル")
        ).firstMatch
        XCTAssertTrue(connectionRow.waitForExistence(timeout: 5))
        XCTAssertTrue(connectionRow.isHittable)
        connectionRow.tap()
        XCTAssertTrue(app.navigationBars["接続"].waitForExistence(timeout: 5))

        let providerField = app.buttons["provider-picker-field"].firstMatch
        XCTAssertTrue(providerField.waitForExistence(timeout: 5))
        XCTAssertTrue(providerField.isHittable)
        providerField.tap()

        XCTAssertTrue(app.navigationBars["プロバイダー"].waitForExistence(timeout: 5))
        let geminiRow = app.buttons["provider-row-GEMINI"].firstMatch
        XCTAssertTrue(geminiRow.waitForExistence(timeout: 5))
        XCTAssertTrue(geminiRow.isHittable)
        geminiRow.tap()

        XCTAssertTrue(app.navigationBars["接続"].waitForExistence(timeout: 5))
        let updatedProviderField = app.buttons["provider-picker-field"].firstMatch
        XCTAssertTrue(updatedProviderField.waitForExistence(timeout: 5))
        XCTAssertTrue(updatedProviderField.label.contains("Google Gemini"))
    }

    func testSwipingDownProviderPickerReturnsToConnectionSettings() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppStoreScreenshotDemo"]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        XCTAssertTrue(openSettings(app: app))

        let connectionRow = app.buttons.matching(
            NSPredicate(format: "label CONTAINS %@", "API・モデル")
        ).firstMatch
        XCTAssertTrue(connectionRow.waitForExistence(timeout: 5))
        connectionRow.tap()
        XCTAssertTrue(app.navigationBars["接続"].waitForExistence(timeout: 5))

        let providerField = app.buttons["provider-picker-field"].firstMatch
        XCTAssertTrue(providerField.waitForExistence(timeout: 5))
        providerField.tap()

        let providerNavigationBar = app.navigationBars["プロバイダー"].firstMatch
        XCTAssertTrue(providerNavigationBar.waitForExistence(timeout: 5))
        providerNavigationBar.swipeDown()

        XCTAssertTrue(app.navigationBars["接続"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons["provider-picker-field"].firstMatch.waitForExistence(timeout: 5),
            "Dismissing the provider picker must keep the parent settings sheet open"
        )
        XCTAssertFalse(providerNavigationBar.exists)
    }

    func testCaptureTemporaryChatIconStates() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppStoreScreenshotDemo",
            "-ScreenshotScene", "temporary-chat"
        ]
        app.launch()

        let button = app.buttons["chat-primary-action-button"].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 20))
        XCTAssertEqual(button.label, "シークレットチャットに切り替え")
        capture("temporary-chat-icon-inactive", element: button)

        button.tap()
        let selectedButton = app.buttons["chat-primary-action-button"].firstMatch
        XCTAssertTrue(selectedButton.waitForExistence(timeout: 5))
        XCTAssertEqual(selectedButton.label, "通常チャットに戻す")
        capture("temporary-chat-icon-selected", element: selectedButton)
    }

    func testNativeTimelineKeepsTheLastMessageInsideTheViewport() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppStoreScreenshotDemo",
            "-ChatTimelinePerformanceFixture",
            "-ScreenshotScene", "performance"
        ]
        app.launch()

        let timeline = app.collectionViews["chat-timeline"].firstMatch
        let composer = app.descendants(matching: .any)
            .matching(identifier: "chat-composer")
            .firstMatch
        XCTAssertTrue(timeline.waitForExistence(timeout: 20))
        XCTAssertTrue(composer.waitForExistence(timeout: 20))

        let finalMessage = app.textViews
            .matching(identifier: "selectable-chat-text")
            .matching(NSPredicate(format: "value BEGINSWITH %@", "Fixture message 199"))
            .firstMatch
        XCTAssertTrue(finalMessage.waitForExistence(timeout: 20))
        XCTAssertTrue(finalMessage.isHittable)
        XCTAssertLessThanOrEqual(finalMessage.frame.maxY, composer.frame.minY + 1)

        timeline.swipeDown()
        timeline.swipeDown()
        XCTAssertTrue(app.buttons["chat-latest-button"].waitForExistence(timeout: 5))

        composer.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["chat-latest-button"].exists)
    }

    func testChatComposerKeepsSoftwareKeyboardVisibleAcrossTypingAndNewline() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppStoreScreenshotDemo",
            "-ScreenshotScene", "chat"
        ]
        app.launch()

        let composer = app.descendants(matching: .any)
            .matching(identifier: "chat-composer")
            .firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 20))

        composer.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))

        composer.typeText("あ")
        XCTAssertTrue(keyboard.exists, "The first edit must not resign the native text view")
        XCTAssertEqual(composer.value as? String, "あ")

        composer.typeText("\nい")
        XCTAssertTrue(keyboard.exists, "A newline must keep the composer focused")
        XCTAssertEqual(composer.value as? String, "あ\nい")
    }

    func testReasoningEffortMeterOnlyAppearsWithKeyboardAndSliderChangesEffort() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppStoreScreenshotDemo",
            "-ReasoningEffortSliderFixture",
            "-ScreenshotScene", "chat"
        ]
        app.launch()

        let composer = app.descendants(matching: .any)
            .matching(identifier: "chat-composer")
            .firstMatch
        let meter = app.buttons["chat-reasoning-effort-button"].firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 20))
        XCTAssertFalse(meter.exists)

        composer.tap()
        let keyboard = app.keyboards.firstMatch
        XCTAssertTrue(keyboard.waitForExistence(timeout: 5))
        XCTAssertTrue(meter.waitForExistence(timeout: 5))
        XCTAssertEqual(meter.value as? String, "medium")

        meter.tap()
        let slider = app.descendants(matching: .any)
            .matching(identifier: "chat-reasoning-effort-slider")
            .firstMatch
        XCTAssertTrue(slider.waitForExistence(timeout: 5))
        capture("reasoning-effort-slider-medium", app: app)

        slider.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5))
            .press(
                forDuration: 0.1,
                thenDragTo: slider.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)
                )
            )
        let selectedLabel = app.descendants(matching: .any)
            .matching(identifier: "chat-reasoning-effort-value")
            .firstMatch
        XCTAssertTrue(selectedLabel.waitForExistence(timeout: 5))
        XCTAssertTrue(
            selectedLabel.label.contains("ultra"),
            "The slider must expose the exact selected effort label"
        )
        XCTAssertTrue(keyboard.exists, "Adjusting effort must keep the software keyboard visible")
    }

    func testLongPressOnChatTextUsesNativeTextSelection() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-AppStoreScreenshotDemo",
            "-ChatTextSelectionFixture",
            "-ScreenshotScene", "list"
        ]
        app.launch()

        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        openConversation(app: app, title: "Text Selection Fixture", fallbackTitle: "Text Selection Fixture")

        let expectedSelection = """
        First selectable paragraph.
        Second selectable paragraph.
        Third selectable paragraph.
        """
        let selectableText = app.textViews
            .matching(identifier: "selectable-chat-text")
            .matching(NSPredicate(format: "value BEGINSWITH %@", "First selectable paragraph."))
            .firstMatch
        XCTAssertTrue(selectableText.waitForExistence(timeout: 20))
        XCTAssertEqual(
            selectableText.value as? String,
            expectedSelection,
            "All Markdown paragraphs must share one native selectable text view"
        )

        selectableText.press(forDuration: 1)

        XCTAssertTrue(
            app.menuItems["コピー"].firstMatch.waitForExistence(timeout: 5),
            "Long-pressing message text should open the native text-selection menu"
        )
        XCTAssertTrue(app.menuItems["チャットで質問する"].firstMatch.exists)
        XCTAssertTrue(app.menuItems["すべて"].firstMatch.exists)
        XCTAssertFalse(
            app.buttons["ここからブランチ"].firstMatch.exists,
            "The message-wide context menu must not intercept text selection"
        )
    }

    private func navigateToConversationList(app: XCUIApplication) {
        if listIsVisible(app: app) {
            return
        }

        revealSidebarWithEdgeSwipe(app: app)
        if listIsVisible(app: app) {
            return
        }

        for label in ["openai/gpt-4o-mini", "Sidebar", "会話"] {
            let button = app.navigationBars.buttons[label].firstMatch
            if button.waitForExistence(timeout: 1), button.isHittable {
                button.tap()
                sleep(1)
                if listIsVisible(app: app) {
                    return
                }
            }
        }

        let backButton = app.navigationBars.buttons.element(boundBy: 0)
        if backButton.waitForExistence(timeout: 1), backButton.isHittable {
            backButton.tap()
            sleep(1)
        }
    }

    private func listIsVisible(app: XCUIApplication) -> Bool {
        ["旅行プラン", "Markdown 数式", "API 設計レビュー"].contains { title in
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch.exists
        }
    }

    private func revealSidebarWithEdgeSwipe(app: XCUIApplication) {
        let window = app.windows.element(boundBy: 0)
        guard window.exists else { return }
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5))
        let end = window.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        start.press(forDuration: 0.15, thenDragTo: end)
        sleep(1)
    }

    private func openConversation(app: XCUIApplication, title: String, fallbackTitle: String) {
        navigateToConversationList(app: app)
        let primary = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        if primary.waitForExistence(timeout: 5) {
            primary.tap()
            return
        }
        let fallback = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", fallbackTitle)).firstMatch
        XCTAssertTrue(fallback.waitForExistence(timeout: 5), "Conversation row was not found")
        fallback.tap()
    }

    @discardableResult
    private func openSettings(app: XCUIApplication) -> Bool {
        navigateToConversationList(app: app)
        let settings = app.buttons["open-settings"].firstMatch
        if settings.waitForExistence(timeout: 5), settings.isHittable {
            settings.tap()
            sleep(1)
            return app.navigationBars["設定"].waitForExistence(timeout: 5)
        }

        let labeled = app.buttons["設定"].firstMatch
        if labeled.waitForExistence(timeout: 3), labeled.isHittable {
            labeled.tap()
            sleep(1)
            return app.navigationBars["設定"].waitForExistence(timeout: 5)
        }
        return false
    }

    private func closeSettings(app: XCUIApplication) {
        let close = app.navigationBars.buttons["閉じる"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 3), "Settings close button was not found")
        XCTAssertTrue(close.isHittable)
        close.tap()
        sleep(1)
    }

    private func openSettingsCategory(app: XCUIApplication, subtitle: String, title: String) -> Bool {
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", subtitle)).firstMatch
        guard row.waitForExistence(timeout: 5), row.isHittable else { return false }
        row.tap()
        return app.navigationBars[title].waitForExistence(timeout: 5)
    }

    private func returnToSettingsIndex(app: XCUIApplication) -> Bool {
        let back = app.navigationBars.buttons["設定"].firstMatch
        guard back.waitForExistence(timeout: 3), back.isHittable else { return false }
        back.tap()
        return app.navigationBars["設定"].waitForExistence(timeout: 5)
    }

    private func scrollToText(app: XCUIApplication, text: String) -> Bool {
        let target = app.staticTexts[text].firstMatch
        for _ in 0..<8 {
            if target.exists, target.isHittable { return true }
            app.swipeUp()
        }
        return target.exists
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let url = outputDirectory.appendingPathComponent("\(name).png")
        let image = screenshot.image
        guard let data = image.pngData() else {
            XCTFail("Could not encode screenshot \(name)")
            return
        }
        XCTAssertNoThrow(try data.write(to: url, options: .atomic))
    }

    private func capture(_ name: String, element: XCUIElement) {
        let screenshot = element.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let url = outputDirectory.appendingPathComponent("\(name).png")
        guard let data = screenshot.image.pngData() else {
            XCTFail("Could not encode screenshot \(name)")
            return
        }
        XCTAssertNoThrow(try data.write(to: url, options: .atomic))
    }
}
