import SwiftUI
import UIKit

// MARK: - Hex helpers (file-private)

private extension UIColor {
    /// Opaque sRGB color from a 0xRRGGBB value.
    convenience init(hex: UInt32) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255.0
        let green = CGFloat((hex >> 8) & 0xFF) / 255.0
        let blue = CGFloat(hex & 0xFF) / 255.0
        self.init(red: red, green: green, blue: blue, alpha: 1.0)
    }
}

private extension Color {
    /// Opaque color from a 0xRRGGBB value, identical in light and dark mode.
    init(hex: UInt32) {
        self.init(uiColor: UIColor(hex: hex))
    }

    /// Color that resolves to `light` or `dark` depending on the current interface style.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor(dynamicProvider: { traits in
            traits.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        }))
    }
}

// MARK: - Semantic palette (see ARCHITECTURE.md, "Designsystem")

extension Color {
    /// Page background.
    static let nbPaper = Color(light: 0xF6F5F0, dark: 0x0C0F1E)
    /// Cards.
    static let nbCard = Color(light: 0xFFFFFF, dark: 0x161A2E)
    /// Primary text.
    static let nbInk = Color(light: 0x0B1352, dark: 0xF2F3F8)
    /// Body text.
    static let nbInkSoft = Color(light: 0x2E3555, dark: 0xC9CCDA)
    /// Secondary text.
    static let nbMuted = Color(light: 0x5A607A, dark: 0xA3A8BF)
    /// Dividers.
    static let nbLine = Color(light: 0xECEDF2, dark: 0x262B44)
    /// Blue hint background.
    static let nbTint = Color(light: 0xE3E7FB, dark: 0x1E2550)
    /// Blue hint text.
    static let nbTintInk = Color(light: 0x1A2A9C, dark: 0xB9C2FF)
    /// Warning chip background.
    static let nbWarnBg = Color(light: 0xFCEBDD, dark: 0x3A2412)
    /// Warning chip text.
    static let nbWarn = Color(light: 0x9A4206, dark: 0xF3B07A)
    /// Orange accent: dots, tracking share.
    static let nbOrange = Color(light: 0xE07B28, dark: 0xE8893A)
    /// Neutral share.
    static let nbGray = Color(light: 0xBFC3D3, dark: 0x4A5070)
    /// Destructive actions.
    static let nbDanger = Color(light: 0xB42318, dark: 0xFF8A80)
    /// Secondary text on the blue accent surface.
    static let nbOnBlueMuted = Color(light: 0xD3D8FA, dark: 0xD3D8FA)
    /// Speed rating: slow (red).
    static let nbSpeedSlow = Color(light: 0xC62828, dark: 0xEF5350)
    /// Speed rating: ok (yellow).
    static let nbSpeedOk = Color(light: 0xD69E00, dark: 0xF2C14E)
    /// Speed rating: fast (green).
    static let nbSpeedFast = Color(light: 0x1E8E5A, dark: 0x4CC38A)
}

// MARK: - Selectable accent blue

/// User-selectable accent blue, stored under `@AppStorage("accentBlue")`.
enum AccentBlue: String, CaseIterable, Identifiable {
    case ultramarin
    case nachtblau
    case himmelblau

    /// Standard accent.
    static let standard: AccentBlue = .ultramarin

    var id: String { rawValue }

    /// German display name for the settings screen.
    var name: String {
        switch self {
        case .ultramarin: return "Ultramarin"
        case .nachtblau: return "Nachtblau"
        case .himmelblau: return "Himmelblau"
        }
    }

    /// The accent color. Same in light and dark mode.
    var color: Color {
        switch self {
        case .ultramarin: return Color(hex: 0x2133D0)
        case .nachtblau: return Color(hex: 0x16226E)
        case .himmelblau: return Color(hex: 0x1F62D6)
        }
    }
}

// MARK: - Environment access

private struct NBAccentKey: EnvironmentKey {
    static let defaultValue: Color = AccentBlue.standard.color
}

extension EnvironmentValues {
    /// The current accent blue. Read with `@Environment(\.nbAccent) var accent`.
    var nbAccent: Color {
        get { self[NBAccentKey.self] }
        set { self[NBAccentKey.self] = newValue }
    }
}

// MARK: - Accent injection

private struct NBAccentFromStorage: ViewModifier {
    @AppStorage("accentBlue") private var raw: String = AccentBlue.standard.rawValue

    func body(content: Content) -> some View {
        let accent = AccentBlue(rawValue: raw)?.color ?? AccentBlue.standard.color
        content
            .environment(\.nbAccent, accent)
            .tint(accent)
    }
}

extension View {
    /// Reads the stored accent choice and injects it as `\.nbAccent` and as the tint.
    /// Apply once near the root of the view hierarchy.
    func nbAccentFromStorage() -> some View {
        modifier(NBAccentFromStorage())
    }
}
