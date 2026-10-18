import SwiftUI

// MARK: - Screen scaffold

/// Standard screen: accent-colored header at the top, content card stack below.
/// The content overlaps the bottom of the header by 48 pt. The whole screen scrolls.
struct NBScreen<Header: View, Content: View>: View {
    @Environment(\.nbAccent) private var accent

    private let header: Header
    private let content: Content

    init(@ViewBuilder header: () -> Header, @ViewBuilder content: () -> Content) {
        self.header = header()
        self.content = content()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                    // Extend the accent surface up under the status bar.
                    .background(alignment: .top) {
                        accent.ignoresSafeArea(edges: .top)
                    }

                VStack(alignment: .leading, spacing: 22) {
                    content
                }
                .padding(.horizontal, 16)
                // Negative top padding pulls the content up over the header.
                .padding(.top, -48)
                .padding(.bottom, 24)
            }
        }
        .background(Color.nbPaper.ignoresSafeArea())
    }
}

// MARK: - Header

/// Full-width accent header. The title is Instrument Serif. `italicTail` is
/// appended on the same line in the italic cut, e.g. "Alles *im Blick*".
struct NBBlueHeader: View {
    @Environment(\.nbAccent) private var accent

    private let eyebrow: String?
    private let title: String
    private let italicTail: String?
    private let subtitle: String?

    init(eyebrow: String? = nil, title: String, italicTail: String? = nil, subtitle: String? = nil) {
        self.eyebrow = eyebrow
        self.title = title
        self.italicTail = italicTail
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let eyebrow {
                Text(eyebrow.uppercased())
                    .font(.nbSans(12, weight: .semibold))
                    .tracking(1.2)
                    .foregroundStyle(Color.nbOnBlueMuted)
            }

            titleText
                .foregroundStyle(.white)

            if let subtitle {
                Text(subtitle)
                    .font(.nbSans(15))
                    .foregroundStyle(Color.nbOnBlueMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 22)
        .padding(.top, 24)
        // Bottom space is where the content card stack overlaps the header.
        .padding(.bottom, 76)
        .background(accent)
    }

    /// Title with optional italic tail, joined as one Text so it wraps as a paragraph.
    private var titleText: Text {
        let head = Text(title).font(.nbSerif(46))
        guard let italicTail, !italicTail.isEmpty else { return head }
        return head + Text(" " + italicTail).font(.nbSerif(46, italic: true))
    }
}

// MARK: - Cards and sections

/// White rounded card. Content is not padded; callers add their own padding.
struct NBCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
    }

    var body: some View {
        content
            // Clip the content so rows and dividers follow the rounded corners.
            .clipShape(shape)
            .background {
                shape
                    .fill(Color.nbCard)
                    .shadow(color: .black.opacity(0.06), radius: 14, x: 0, y: 6)
            }
    }
}

/// Serif section heading shown above a card.
struct NBSectionTitle: View {
    private let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.nbSerif(28))
            .foregroundStyle(Color.nbInk)
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - List rows

/// List row with a 40 x 40 icon tile, a title, an optional subtitle and a trailing view.
struct NBRow<Trailing: View>: View {
    private let symbol: String
    private let title: String
    private let subtitle: String?
    private let symbolTint: Color?
    private let symbolBackground: Color?
    private let trailing: Trailing

    init(
        symbol: String,
        title: String,
        subtitle: String? = nil,
        symbolTint: Color? = nil,
        symbolBackground: Color? = nil,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.symbol = symbol
        self.title = title
        self.subtitle = subtitle
        self.symbolTint = symbolTint
        self.symbolBackground = symbolBackground
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(symbolBackground ?? Color.nbTint)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: symbol)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(symbolTint ?? Color.nbTintInk)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.nbSans(15, weight: .semibold))
                    .foregroundStyle(Color.nbInk)
                if let subtitle {
                    Text(subtitle)
                        .font(.nbSans(13))
                        .foregroundStyle(Color.nbMuted)
                }
            }

            Spacer(minLength: 0)

            trailing
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

extension NBRow where Trailing == EmptyView {
    /// Row without a trailing view.
    init(
        symbol: String,
        title: String,
        subtitle: String? = nil,
        symbolTint: Color? = nil,
        symbolBackground: Color? = nil
    ) {
        self.init(
            symbol: symbol,
            title: title,
            subtitle: subtitle,
            symbolTint: symbolTint,
            symbolBackground: symbolBackground,
            trailing: { EmptyView() }
        )
    }
}

/// 1 pt separator between rows, inset to the text column.
struct NBRowDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.nbLine)
            .frame(height: 1)
            .padding(.leading, 16)
    }
}

// MARK: - Chips and dots

/// `.warn` is orange (a problem). `.tip` is blue (a hint).
enum NBChipStyle {
    case warn
    case tip
}

/// Small capsule label.
struct NBChip: View {
    private let text: String
    private let style: NBChipStyle

    init(_ text: String, style: NBChipStyle) {
        self.text = text
        self.style = style
    }

    private var foreground: Color {
        switch style {
        case .warn: return .nbWarn
        case .tip: return .nbTintInk
        }
    }

    private var background: Color {
        switch style {
        case .warn: return .nbWarnBg
        case .tip: return .nbTint
        }
    }

    var body: some View {
        Text(text)
            .font(.nbSans(12, weight: .semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(Capsule().fill(background))
            .fixedSize()
    }
}

/// 10 x 10 colored dot, e.g. as a legend marker.
struct NBDot: View {
    private let color: Color

    init(_ color: Color) {
        self.color = color
    }

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 10, height: 10)
    }
}

// MARK: - Segment bar

/// Horizontal bar split into proportional colored segments.
/// Values are relative; they do not need to sum to 1.
struct NBSegmentBar: View {
    private let segments: [(value: Double, color: Color)]
    private let height: CGFloat
    private let accessibilityLabel: String?

    /// Gap between segments in points.
    private let spacing: CGFloat = 2

    init(
        segments: [(value: Double, color: Color)],
        height: CGFloat = 10,
        accessibilityLabel: String? = nil
    ) {
        self.segments = segments
        self.height = height
        self.accessibilityLabel = accessibilityLabel
    }

    private var bar: some View {
        GeometryReader { geometry in
            let total = segments.reduce(0) { $0 + max($1.value, 0) }
            let gaps = CGFloat(max(segments.count - 1, 0)) * spacing
            let available = max(geometry.size.width - gaps, 0)

            HStack(spacing: spacing) {
                ForEach(segments.indices, id: \.self) { index in
                    let segment = segments[index]
                    Rectangle()
                        .fill(segment.color)
                        .frame(
                            width: total > 0 ? available * CGFloat(max(segment.value, 0) / total) : 0,
                            height: geometry.size.height
                        )
                }
            }
        }
        .frame(height: height)
        .background(Capsule().fill(Color.nbLine))
        .clipShape(Capsule())
    }

    var body: some View {
        if let accessibilityLabel {
            bar.accessibilityLabel(accessibilityLabel)
        } else {
            bar
        }
    }
}

// MARK: - Buttons

/// Filled primary button in the current accent. Pressed opacity 0.85, dimmed when disabled.
struct NBPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        NBPrimaryButtonBody(configuration: configuration)
    }
}

/// Needs its own View so it can read `@Environment` (ButtonStyle cannot).
private struct NBPrimaryButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.nbAccent) private var accent
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.nbSans(15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(minHeight: 44)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
    }
}

/// Outlined secondary button on the card surface. Pressed opacity 0.85, dimmed when disabled.
struct NBSecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        NBSecondaryButtonBody(configuration: configuration)
    }
}

private struct NBSecondaryButtonBody: View {
    let configuration: ButtonStyleConfiguration

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.nbSans(15, weight: .semibold))
            .foregroundStyle(Color.nbInk)
            .frame(minHeight: 44)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.nbCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.nbGray, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.4)
    }
}

// MARK: - Previews

#Preview("Komponenten, hell") {
    NBScreen {
        NBBlueHeader(
            eyebrow: "Heimnetz",
            title: "Alles",
            italicTail: "im Blick",
            subtitle: "Geräte, Tempo und Hinweise auf einen Blick."
        )
    } content: {
        NBSectionTitle("Geräte")

        NBCard {
            VStack(spacing: 0) {
                NBRow(symbol: "laptopcomputer", title: "MacBook", subtitle: "WLAN, 5 GHz") {
                    NBChip("Neu", style: .tip)
                }
                NBRowDivider()
                NBRow(symbol: "tv", title: "Fernseher", subtitle: "LAN-Kabel") {
                    NBChip("Langsam", style: .warn)
                }
                NBRowDivider()
                NBRow(symbol: "printer", title: "Drucker")
            }
        }

        NBSegmentBar(
            segments: [
                (value: 0.7, color: Color.nbGray),
                (value: 0.2, color: Color.nbOrange),
                (value: 0.1, color: Color.nbTintInk)
            ],
            accessibilityLabel: "Normal 70 Prozent, Tracking 20 Prozent, Hersteller 10 Prozent"
        )

        HStack(spacing: 8) {
            NBDot(Color.nbSpeedFast)
            NBDot(Color.nbSpeedOk)
            NBDot(Color.nbSpeedSlow)
        }

        Button("Speedtest starten") {}
            .buttonStyle(NBPrimaryButtonStyle())

        Button("Abbrechen") {}
            .buttonStyle(NBSecondaryButtonStyle())
    }
    .nbAccentFromStorage()
}

#Preview("Komponenten, dunkel") {
    NBScreen {
        NBBlueHeader(
            title: "Netzwerk",
            italicTail: "ruhig",
            subtitle: "Dunkler Modus mit Nachtblau."
        )
    } content: {
        NBCard {
            NBRow(symbol: "wifi", title: "Gastnetz", subtitle: "Aktiv") {
                NBChip("Hinweis", style: .tip)
            }
        }
        Button("Speichern") {}
            .buttonStyle(NBPrimaryButtonStyle())
    }
    .environment(\.nbAccent, AccentBlue.nachtblau.color)
    .environment(\.colorScheme, .dark)
}
