import SwiftUI

/// The accent color chosen in Settings > Appearance.
///
/// The raw values mirror the persisted `AppSettings.themeColor` values so the
/// stored settings can be converted without a separate lookup table.
enum AppThemeColor: String, CaseIterable {
    case bluePurple = "BLUE_PURPLE"
    case blue = "BLUE"
    case green = "GREEN"
    case yellow = "YELLOW"
    case pink = "PINK"
    case orange = "ORANGE"
    case white = "WHITE"
    case black = "BLACK"

    init(setting: String) {
        self = AppThemeColor(rawValue: setting.uppercased()) ?? .bluePurple
    }

    var color: Color {
        switch self {
        case .bluePurple:
            return Color(uiColor: .systemIndigo)
        case .blue:
            return Color(uiColor: .systemBlue)
        case .green:
            return Color(uiColor: .systemGreen)
        case .yellow:
            return Color(uiColor: .systemYellow)
        case .pink:
            return Color(uiColor: .systemPink)
        case .orange:
            return Color(uiColor: .systemOrange)
        case .white:
            return Color(uiColor: .white)
        case .black:
            return Color(uiColor: .black)
        }
    }

    /// Light accents need a dark glyph when used as a filled surface.
    var usesDarkOnAccentColor: Bool {
        switch self {
        case .yellow, .white:
            return true
        case .bluePurple, .blue, .green, .pink, .orange, .black:
            return false
        }
    }

    var onAccentColor: Color {
        usesDarkOnAccentColor ? Color(uiColor: .black) : Color(uiColor: .white)
    }
}

/// The resolved accent palette for the current appearance setting.
struct AppAccentTheme: Equatable {
    let color: Color
    let onAccentColor: Color

    static let fallback = AppAccentTheme(
        color: AppThemeColor.bluePurple.color,
        onAccentColor: AppThemeColor.bluePurple.onAccentColor
    )

    init(themeColor: String) {
        let theme = AppThemeColor(setting: themeColor)
        color = theme.color
        onAccentColor = theme.onAccentColor
    }

    init(color: Color, onAccentColor: Color) {
        self.color = color
        self.onAccentColor = onAccentColor
    }
}

private struct AppAccentThemeKey: EnvironmentKey {
    static let defaultValue = AppAccentTheme.fallback
}

extension EnvironmentValues {
    /// Accent palette from Settings > Appearance. Prefer this over
    /// `Color.accentColor` for custom-drawn fills and strokes because the app
    /// resolves the accent itself instead of relying on the system tint.
    var appAccent: AppAccentTheme {
        get { self[AppAccentThemeKey.self] }
        set { self[AppAccentThemeKey.self] = newValue }
    }
}
