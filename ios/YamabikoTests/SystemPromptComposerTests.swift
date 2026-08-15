import XCTest
@testable import YamabikoChat

final class SystemPromptComposerTests: XCTestCase {
    private var tokyoTimeZone: TimeZone {
        TimeZone(identifier: "Asia/Tokyo")!
    }

    private func makeDate(year: Int, month: Int, day: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tokyoTimeZone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    override func setUp() {
        super.setUp()
        NSTimeZone.default = tokyoTimeZone
    }

    override func tearDown() {
        NSTimeZone.default = .current
        super.tearDown()
    }

    func testComposeForAPI_appendsDateSuffixAfterPromptBody() {
        let composed = SystemPromptComposer.composeForAPI(
            "  Be helpful.  ",
            now: makeDate(year: 2026, month: 6, day: 27)
        )

        XCTAssertEqual(composed, "Be helpful.\n\nToday's date: 2026/06/27")
    }

    func testComposeForAPI_returnsDateOnlyWhenPromptIsNil() {
        let composed = SystemPromptComposer.composeForAPI(
            nil,
            now: makeDate(year: 2026, month: 6, day: 27)
        )

        XCTAssertEqual(composed, "Today's date: 2026/06/27")
    }

    func testComposeForAPI_returnsDateOnlyWhenPromptIsBlank() {
        let composed = SystemPromptComposer.composeForAPI(
            "   \n\t  ",
            now: makeDate(year: 2026, month: 6, day: 27)
        )

        XCTAssertEqual(composed, "Today's date: 2026/06/27")
    }

    func testComposeForAPI_keepsStaticPromptAsPrefixForCacheFriendliness() {
        let composed = SystemPromptComposer.composeForAPI(
            "Stable instructions",
            now: makeDate(year: 2026, month: 6, day: 27)
        )

        XCTAssertTrue(composed?.hasPrefix("Stable instructions") == true)
        XCTAssertFalse(composed?.hasPrefix("Today's date:") == true)
    }

    func testComposeForAPI_appendsAgenticWebSearchInstructionsWhenEnabled() {
        let composed = SystemPromptComposer.composeForAPI(
            "Be helpful.",
            enablesAgenticWebSearch: true,
            now: makeDate(year: 2026, month: 6, day: 27)
        )

        XCTAssertTrue(composed?.contains("You have access to web_search and fetch_url.") == true)
        XCTAssertTrue(composed?.contains("Search agentically when the task requires investigation:") == true)
        XCTAssertTrue(composed?.contains("Start with a broad search") == true)
        XCTAssertTrue(composed?.contains("Read titles and snippets") == true)
        XCTAssertTrue(composed?.contains("fetch_url(url, goal)") == true)
        XCTAssertTrue(composed?.contains("superficial wording changes") == true)
        XCTAssertTrue(composed?.contains("cite the URLs of the sources actually used") == true)
        XCTAssertTrue(composed?.hasSuffix("Today's date: 2026/06/27") == true)
    }

    func testComposeForAPI_omitsAgenticWebSearchInstructionsWhenDisabled() {
        let composed = SystemPromptComposer.composeForAPI(
            "Be helpful.",
            enablesAgenticWebSearch: false,
            now: makeDate(year: 2026, month: 6, day: 27)
        )

        XCTAssertFalse(composed?.contains("web_search") == true)
        XCTAssertEqual(composed, "Be helpful.\n\nToday's date: 2026/06/27")
    }
}
