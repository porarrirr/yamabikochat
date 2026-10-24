import SwiftUI

extension Color {
    init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int = UInt64(0)
        Scanner(string: cleaned).scanHexInt64(&int)

        let r, g, b: UInt64
        switch cleaned.count {
        case 6:
            (r, g, b) = (int >> 16, int >> 8 & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (58, 122, 254)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}

// Keep the canvas true black, but preserve visible surfaces for controls and cards.
// Light appearance continues to use the original system colors.
extension UIColor {
    private static func amoled(_ lightColor: UIColor, dark: UIColor = .black) -> UIColor {
        UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : lightColor.resolvedColor(with: traits)
        }
    }

    static let amoledSecondarySystemFill = amoled(.secondarySystemFill, dark: UIColor(white: 0.16, alpha: 1))
    static let amoledTertiarySystemFill = amoled(.tertiarySystemFill, dark: UIColor(white: 0.11, alpha: 1))
    static let amoledSystemBackground = amoled(.systemBackground)
    static let amoledSecondarySystemBackground = amoled(.secondarySystemBackground, dark: UIColor(white: 0.09, alpha: 1))
    static let amoledTertiarySystemBackground = amoled(.tertiarySystemBackground, dark: UIColor(white: 0.14, alpha: 1))
    static let amoledSystemGroupedBackground = amoled(.systemGroupedBackground)
    static let amoledSecondarySystemGroupedBackground = amoled(.secondarySystemGroupedBackground, dark: UIColor(white: 0.09, alpha: 1))
    static let amoledTertiarySystemGroupedBackground = amoled(.tertiarySystemGroupedBackground, dark: UIColor(white: 0.14, alpha: 1))
    static let amoledSecondaryLabel = amoled(.secondaryLabel, dark: UIColor(white: 0.72, alpha: 1))
    static let amoledTertiaryLabel = amoled(.tertiaryLabel, dark: UIColor(white: 0.62, alpha: 1))
    static let amoledPlaceholderText = amoled(.placeholderText, dark: UIColor(white: 0.62, alpha: 1))
    static let amoledSeparator = amoled(.separator, dark: UIColor(white: 0.3, alpha: 1))

    // The compact drawer moves the conversation over a true black sidebar.
    // Dimming cannot separate two black surfaces, so dark mode lifts the card
    // with a light veil and a hairline instead; light mode keeps the dim scrim.
    static let amoledDrawerCardVeil = amoled(
        .black.withAlphaComponent(0.14), dark: UIColor(white: 1, alpha: 0.08)
    )
    static let amoledDrawerCardBorder = amoled(
        .black.withAlphaComponent(0.08), dark: UIColor(white: 1, alpha: 0.2)
    )
}

struct AMOLEDForm<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content

    var body: some View {
        Form {
            content
                .listRowBackground(colorScheme == .dark ? Color(uiColor: .amoledSecondarySystemGroupedBackground) : nil)
                .listRowSeparatorTint(colorScheme == .dark ? Color(uiColor: .amoledSeparator) : nil)
        }
        .scrollContentBackground(colorScheme == .dark ? .hidden : .visible)
        .background(Color(uiColor: .amoledSystemGroupedBackground))
        .amoledPresentation()
    }
}

struct AMOLEDList<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder var content: Content

    var body: some View {
        List {
            content
                .listRowBackground(colorScheme == .dark ? Color(uiColor: .amoledSecondarySystemGroupedBackground) : nil)
                .listRowSeparatorTint(colorScheme == .dark ? Color(uiColor: .amoledSeparator) : nil)
        }
        .scrollContentBackground(colorScheme == .dark ? .hidden : .visible)
        .background(Color(uiColor: .amoledSystemGroupedBackground))
        .amoledPresentation()
    }
}

struct AMOLEDMaterial: ShapeStyle {
    let material: Material

    func resolve(in environment: EnvironmentValues) -> AnyShapeStyle {
        environment.colorScheme == .dark
            ? AnyShapeStyle(Color(uiColor: .amoledSecondarySystemBackground))
            : AnyShapeStyle(material)
    }
}

extension Color {
    static func amoledSubtleSurface(lightOpacity: Double) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: max(0.09, lightOpacity), alpha: 1)
                : UIColor.label.resolvedColor(with: traits).withAlphaComponent(lightOpacity)
        })
    }
}

private struct AMOLEDPresentation: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .toolbarBackground(Color(uiColor: .amoledSystemBackground), for: .navigationBar, .bottomBar)
            .toolbarBackground(colorScheme == .dark ? .visible : .automatic, for: .navigationBar, .bottomBar)
            .toolbarColorScheme(colorScheme, for: .navigationBar, .bottomBar)
            .presentationBackground(Color(uiColor: .amoledSystemBackground))
    }
}

extension View {
    func amoledPresentation() -> some View {
        modifier(AMOLEDPresentation())
    }
}
