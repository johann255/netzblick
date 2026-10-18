import SwiftUI
import UIKit

// MARK: - Font availability

/// Checked once. If the bundled font files are not registered (missing from the
/// target or the UIAppFonts list), the system fallbacks are used instead.
private enum NBFontAvailability {
    static let geist: Bool = {
        UIFont(name: "Geist-Regular", size: 12) != nil
            || UIFont.familyNames.contains("Geist")
    }()
}

// MARK: - Typefaces

extension Font {
    /// Instrument Serif for headings and large numbers.
    /// Falls back to the system serif design when the font is not bundled.
    static func nbSerif(_ size: CGFloat, italic: Bool = false) -> Font {
        let name = italic ? "InstrumentSerif-Italic" : "InstrumentSerif-Regular"
        if UIFont(name: name, size: size) != nil {
            return .custom(name, size: size, relativeTo: .body)
        }
        let fallback = Font.system(size: size, design: .serif)
        return italic ? fallback.italic() : fallback
    }

    /// Geist for all other text. The variable font is selected by family and
    /// weighted with `.weight(_:)`. Falls back to the system font when missing.
    static func nbSans(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        if NBFontAvailability.geist {
            return .custom("Geist", size: size, relativeTo: .body).weight(weight)
        }
        return .system(size: size, weight: weight)
    }
}
