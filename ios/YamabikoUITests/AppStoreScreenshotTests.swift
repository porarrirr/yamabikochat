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

        openSettings(app: app)
        capture("03-settings-api", app: app)

        if tapSegmentedTab(app: app, title: "外観/診断") {
            sleep(1)
            capture("04-settings-appearance", app: app)
        }

        if tapSegmentedTab(app: app, title: "デュアル") {
            sleep(1)
            capture("05-settings-dual", app: app)
        }

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
            if app.staticTexts["仕事用"].firstMatch.waitForExistence(timeout: 3) {
                app.staticTexts["仕事用"].firstMatch.tap()
                sleep(1)
                capture("06-project-conversations", app: app)
            }
        }

        if openSettings(app: app), tapSegmentedTab(app: app, title: "自動会話") {
            sleep(1)
            capture("08-settings-auto", app: app)
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
        app.staticTexts["旅行プラン"].exists
            || app.staticTexts["Markdown 数式"].exists
            || app.staticTexts["API 設計レビュー"].exists
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
        let primary = app.staticTexts[title].firstMatch
        if primary.waitForExistence(timeout: 5) {
            primary.tap()
            return
        }
        app.staticTexts[fallbackTitle].firstMatch.tap()
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
        if close.waitForExistence(timeout: 3), close.isHittable {
            close.tap()
            sleep(1)
        }
    }

    @discardableResult
    private func tapSegmentedTab(app: XCUIApplication, title: String) -> Bool {
        let tab = app.segmentedControls.buttons[title].firstMatch
        guard tab.waitForExistence(timeout: 3), tab.isHittable else { return false }
        tab.tap()
        return true
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        let url = outputDirectory.appendingPathComponent("\(name).png")
        let image = screenshot.image
        guard let data = image.pngData() else { return }
        try? data.write(to: url, options: .atomic)
    }
}
