import SwiftUI

struct DaylightPalette: Equatable {
    let isLight: Bool
    let canvasTop: Color
    let canvasBottom: Color
    let ink: Color
    let secondaryInk: Color
    let quietInk: Color
    let rule: Color
    let today: Color
    let panel: Color
    let elevatedPanel: Color
    let focus: Color
    let texture: Color

    static let dark = DaylightPalette(
        isLight: false,
        canvasTop: Color(red: 0.075, green: 0.105, blue: 0.11),
        canvasBottom: Color(red: 0.035, green: 0.055, blue: 0.07),
        ink: Color(red: 0.95, green: 0.93, blue: 0.86),
        secondaryInk: Color(red: 0.68, green: 0.70, blue: 0.67),
        quietInk: Color(red: 0.51, green: 0.54, blue: 0.52),
        rule: Color.white.opacity(0.09),
        today: Color(red: 0.96, green: 0.73, blue: 0.30),
        panel: Color(red: 0.10, green: 0.14, blue: 0.15).opacity(0.88),
        elevatedPanel: Color.white.opacity(0.055),
        focus: Color(red: 0.48, green: 0.76, blue: 0.98),
        texture: Color.white.opacity(0.055)
    )

    static let light = DaylightPalette(
        isLight: true,
        canvasTop: Color(red: 0.97, green: 0.95, blue: 0.90),
        canvasBottom: Color(red: 0.90, green: 0.87, blue: 0.80),
        ink: Color(red: 0.09, green: 0.13, blue: 0.12),
        secondaryInk: Color(red: 0.25, green: 0.31, blue: 0.29),
        quietInk: Color(red: 0.34, green: 0.39, blue: 0.37),
        rule: Color.black.opacity(0.13),
        today: Color(red: 0.65, green: 0.35, blue: 0.03),
        panel: Color.white.opacity(0.78),
        elevatedPanel: Color.white.opacity(0.46),
        focus: Color(red: 0.02, green: 0.38, blue: 0.60),
        texture: Color.black.opacity(0.035)
    )
}

extension DaylightAppearance {
    var palette: DaylightPalette { self == .light ? .light : .dark }
    var colorScheme: ColorScheme { self == .light ? .light : .dark }
}

private struct DaylightPaletteKey: EnvironmentKey {
    static let defaultValue = DaylightPalette.dark
}

extension EnvironmentValues {
    var daylightPalette: DaylightPalette {
        get { self[DaylightPaletteKey.self] }
        set { self[DaylightPaletteKey.self] = newValue }
    }
}

enum DaylightTheme {
    static let tiny: CGFloat = 6
    static let small: CGFloat = 10
    static let medium: CGFloat = 16
    static let large: CGFloat = 24
    static let xLarge: CGFloat = 36
    static let radius: CGFloat = 14
}

struct GlassControlSurface<Content: View>: View {
    @Environment(\.daylightPalette) private var palette
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 18))
        } else {
            content
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(palette.rule, lineWidth: 1)
                }
        }
    }
}
