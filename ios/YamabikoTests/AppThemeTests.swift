import SwiftUI
import XCTest
@testable import YamabikoChat

final class AppThemeTests: XCTestCase {
    func testThemeColorKeysMatchPersistedAppearanceOptions() {
        XCTAssertEqual(
            AppThemeColor.allCases.map(\.rawValue),
            ["BLUE_PURPLE", "BLUE", "GREEN", "YELLOW", "PINK", "ORANGE", "WHITE", "BLACK"]
        )
    }

    func testThemeColorSettingIsCaseInsensitive() {
        XCTAssertEqual(AppThemeColor(setting: "blue"), .blue)
        XCTAssertEqual(AppThemeColor(setting: "Pink"), .pink)
        XCTAssertEqual(AppThemeColor(setting: "ORANGE"), .orange)
    }

    func testUnknownThemeColorFallsBackToDefault() {
        XCTAssertEqual(AppThemeColor(setting: ""), .bluePurple)
        XCTAssertEqual(AppThemeColor(setting: "SEPIA"), .bluePurple)
    }

    func testOnlyLightAccentsUseADarkOnAccentColor() {
        XCTAssertTrue(AppThemeColor.white.usesDarkOnAccentColor)
        XCTAssertTrue(AppThemeColor.yellow.usesDarkOnAccentColor)

        for themeColor in [AppThemeColor.bluePurple, .blue, .green, .pink, .orange, .black] {
            XCTAssertFalse(themeColor.usesDarkOnAccentColor, "\(themeColor) should keep a light glyph")
        }
    }

    func testAccentThemeResolvesColorAndGlyphTogether() {
        let lightTheme = AppAccentTheme(themeColor: "WHITE")
        XCTAssertEqual(lightTheme.color, Color(uiColor: .white))
        XCTAssertEqual(lightTheme.onAccentColor, Color(uiColor: .black))

        let darkTheme = AppAccentTheme(themeColor: "BLUE_PURPLE")
        XCTAssertEqual(darkTheme.color, Color(uiColor: .systemIndigo))
        XCTAssertEqual(darkTheme.onAccentColor, Color(uiColor: .white))
    }

    func testDefaultAccentThemeMatchesDefaultSetting() {
        XCTAssertEqual(AppAccentTheme.fallback, AppAccentTheme(themeColor: "BLUE_PURPLE"))
    }
}
