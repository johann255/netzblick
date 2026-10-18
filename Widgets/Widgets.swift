import SwiftUI
import WidgetKit
import NetzblickKit

@main
struct NetzblickWidgetsBundle: WidgetBundle {
    var body: some Widget {
        StatusWidget()
        OverviewWidget()
        SpeedWidget()
    }
}

// MARK: - Shared empty state

/// "Öffne Netzblick einmal …" shown until the app has written a summary.
/// Callers set the color; lock-screen callers set no color (monochrome rendering).
struct WidgetEmptyText: View {
    let font: Font

    init(font: Font = .nbSans(13)) {
        self.font = font
    }

    var body: some View {
        Text(WidgetCopy.emptyState)
            .font(font)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

// MARK: - Status

struct StatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedContainer.statusWidgetKind, provider: SummaryProvider()) { entry in
            StatusWidgetView(entry: entry)
        }
        .configurationDisplayName("Heimnetz-Status")
        .description("Geräte online und ob es Hinweise gibt.")
        .supportedFamilies([.systemSmall, .accessoryCircular])
    }
}

struct StatusWidgetView: View {
    let entry: SummaryEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        contentView
            .containerBackground(for: .widget) {
                // Lock-screen widgets draw AccessoryWidgetBackground in their content instead.
                family == .accessoryCircular ? Color.clear : WidgetAccent.current
            }
            .widgetURL(URL(string: "netzblik://overview"))
    }

    @ViewBuilder
    private var contentView: some View {
        if family == .accessoryCircular {
            circularView
        } else {
            smallView
        }
    }

    // MARK: Home screen, small

    @ViewBuilder
    private var smallView: some View {
        if let summary = entry.summary {
            VStack(alignment: .leading, spacing: 0) {
                Text("Heimnetz".uppercased())
                    .font(.nbSans(11, weight: .semibold))
                    .tracking(1.0)
                    .foregroundStyle(Color.nbOnBlueMuted)

                Spacer(minLength: 4)

                Text("\(summary.devicesOnline)")
                    .font(.nbSerif(44))
                    .foregroundStyle(.white)
                Text("Geräte online")
                    .font(.nbSans(12))
                    .foregroundStyle(.white)

                Spacer(minLength: 8)

                findingLine(summary)

                Text(standLine(summary, now: entry.date))
                    .font(.nbSans(10))
                    .foregroundStyle(Color.nbOnBlueMuted)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            WidgetEmptyText()
                .foregroundStyle(.white)
        }
    }

    private func findingLine(_ summary: WidgetSummary) -> some View {
        HStack(spacing: 6) {
            if summary.findingCount > 0 {
                Circle()
                    .fill(Color.nbOrange)
                    .frame(width: 8, height: 8)
                    .accessibilityHidden(true)
                Text(findingCountText(summary.findingCount))
            } else {
                Text("Alles normal")
            }
        }
        .font(.nbSans(13, weight: .semibold))
        .foregroundStyle(.white)
    }

    // MARK: Lock screen, circular

    private var circularView: some View {
        ZStack {
            AccessoryWidgetBackground()

            if let summary = entry.summary {
                VStack(spacing: 0) {
                    Text("\(summary.devicesOnline)")
                        .font(.system(size: 20, weight: .semibold))
                        .minimumScaleFactor(0.6)
                    Text("online")
                        .font(.system(size: 10))
                }
            } else {
                Text("–")
                    .font(.system(size: 20, weight: .semibold))
            }
        }
    }
}

// MARK: - Overview

struct OverviewWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedContainer.overviewWidgetKind, provider: SummaryProvider()) { entry in
            OverviewWidgetView(entry: entry)
        }
        .configurationDisplayName("Heimnetz-Übersicht")
        .description("Geräte, Hinweise, Tempo und Tracking-Anteil auf einen Blick.")
        .supportedFamilies([.systemMedium, .accessoryRectangular])
    }
}

struct OverviewWidgetView: View {
    let entry: SummaryEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        contentView
            .containerBackground(for: .widget) {
                family == .accessoryRectangular ? Color.clear : Color.nbPaper
            }
            .widgetURL(URL(string: "netzblik://overview"))
    }

    @ViewBuilder
    private var contentView: some View {
        if let summary = entry.summary {
            if family == .accessoryRectangular {
                rectangular(summary)
            } else {
                medium(summary)
            }
        } else if family == .accessoryRectangular {
            WidgetEmptyText(font: .system(size: 12))
        } else {
            WidgetEmptyText()
                .foregroundStyle(Color.nbInk)
        }
    }

    // MARK: Home screen, medium

    private func medium(_ summary: WidgetSummary) -> some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                leftColumn(summary)
                    .frame(width: geometry.size.width * 0.4)
                rightColumn(summary)
                    .frame(width: geometry.size.width * 0.6)
            }
        }
    }

    private func leftColumn(_ summary: WidgetSummary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Heimnetz".uppercased())
                .font(.nbSans(10, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Color.nbOnBlueMuted)

            Spacer(minLength: 0)

            Text("\(summary.devicesOnline)")
                .font(.nbSerif(40))
                .foregroundStyle(.white)
            Text("online")
                .font(.nbSans(12))
                .foregroundStyle(Color.nbOnBlueMuted)

            if summary.newDevices > 0 {
                Text("+\(summary.newDevices) neu")
                    .font(.nbSans(11, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(WidgetAccent.current)
        )
    }

    private func rightColumn(_ summary: WidgetSummary) -> some View {
        let headline = summary.topFinding
            ?? (summary.findingCount > 0 ? findingCountText(summary.findingCount) : "Keine Hinweise")

        return VStack(alignment: .leading, spacing: 8) {
            Text(headline)
                .font(.nbSans(13))
                .foregroundStyle(Color.nbInk)
                .lineLimit(2)

            speedLine(summary)

            if let share = summary.trackingShare {
                trackingLine(share)
            }

            Spacer(minLength: 0)

            Text(standLine(summary, now: entry.date))
                .font(.nbSans(11))
                .foregroundStyle(Color.nbMuted)
        }
        .padding(.leading, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private func speedLine(_ summary: WidgetSummary) -> some View {
        HStack(spacing: 6) {
            if let mbps = summary.lastSpeedMbps {
                if let level = summary.lastSpeedLevel {
                    Circle()
                        .fill(level.widgetColor)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text("\(Int(mbps)) Mbit/s · \(level.label)")
                } else {
                    Text("\(Int(mbps)) Mbit/s")
                }
            } else {
                Text("Noch kein Tempo-Test")
            }
        }
        .font(.nbSans(13))
        .foregroundStyle(Color.nbInk)
        .lineLimit(1)
    }

    private func trackingLine(_ share: Double) -> some View {
        let clamped = min(max(share, 0), 1)
        let percent = Int((clamped * 100).rounded())

        return VStack(alignment: .leading, spacing: 4) {
            Text("Tracking \(percent) %")
                .font(.nbSans(12))
                .foregroundStyle(Color.nbInk)
            NBSegmentBar(
                segments: [
                    (value: clamped, color: Color.nbOrange),
                    (value: 1 - clamped, color: WidgetAccent.current)
                ],
                height: 6,
                accessibilityLabel: "Tracking \(percent) Prozent"
            )
        }
    }

    // MARK: Lock screen, rectangular

    private func rectangular(_ summary: WidgetSummary) -> some View {
        let headline = summary.topFinding
            ?? (summary.findingCount > 0 ? findingCountText(summary.findingCount) : "Alles normal")

        return VStack(alignment: .leading, spacing: 2) {
            Text("\(summary.devicesOnline) Geräte online")
                .font(.system(size: 13, weight: .semibold))
                .widgetAccentable()
            Text(headline)
                .font(.system(size: 12))
                .lineLimit(1)
            Text(speedShortText(summary))
                .font(.system(size: 12))
                .lineLimit(1)
        }
    }
}

// MARK: - Speed

struct SpeedWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: SharedContainer.speedWidgetKind, provider: SummaryProvider()) { entry in
            SpeedWidgetView(entry: entry)
        }
        .configurationDisplayName("Netz-Tempo")
        .description("Letztes Tempo-Ergebnis deiner Leitung, mit Ampelfarbe und Wort.")
        .supportedFamilies([.systemSmall, .accessoryInline])
    }
}

struct SpeedWidgetView: View {
    let entry: SummaryEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        contentView
            .containerBackground(for: .widget) {
                widgetBackground
            }
            .widgetURL(URL(string: "netzblik://speedtest"))
    }

    /// Speed color when a result exists, neutral card otherwise. Inline widgets have none.
    private var widgetBackground: Color {
        guard family == .systemSmall else { return .clear }
        guard let summary = entry.summary, summary.lastSpeedMbps != nil else { return .nbCard }
        return summary.lastSpeedLevel?.widgetColor ?? .nbCard
    }

    @ViewBuilder
    private var contentView: some View {
        if family == .accessoryInline {
            Text(inlineText)
        } else {
            smallView
        }
    }

    private var inlineText: String {
        guard let mbps = entry.summary?.lastSpeedMbps else {
            return "Netzblick: kein Tempo-Test"
        }
        guard let level = entry.summary?.lastSpeedLevel else {
            return "Netz: \(Int(mbps)) Mbit/s"
        }
        return "Netz: \(Int(mbps)) Mbit/s · \(level.label)"
    }

    // MARK: Home screen, small

    @ViewBuilder
    private var smallView: some View {
        if let summary = entry.summary {
            if let mbps = summary.lastSpeedMbps {
                speedResult(summary, mbps: mbps)
            } else {
                speedEmpty
            }
        } else {
            WidgetEmptyText()
                .foregroundStyle(Color.nbInk)
        }
    }

    private func speedResult(_ summary: WidgetSummary, mbps: Double) -> some View {
        let ink = summary.lastSpeedLevel?.widgetTextColor ?? Color.nbInk

        return VStack(alignment: .leading, spacing: 0) {
            Text("Tempo".uppercased())
                .font(.nbSans(11, weight: .semibold))
                .tracking(1.0)
                .opacity(0.85)

            Spacer(minLength: 4)

            Text("\(Int(mbps))")
                .font(.nbSerif(46))
            Text("Mbit/s")
                .font(.nbSans(12))

            Spacer(minLength: 6)

            if let level = summary.lastSpeedLevel {
                Text(level.label)
                    .font(.nbSans(15, weight: .semibold))
            }

            Spacer(minLength: 6)

            if let measuredAt = summary.lastSpeedAt {
                Text("Gemessen \(relativeAge(measuredAt, now: entry.date))")
                    .font(.nbSans(10))
                    .opacity(0.85)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .foregroundStyle(ink)
    }

    private var speedEmpty: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Tempo".uppercased())
                .font(.nbSans(11, weight: .semibold))
                .tracking(1.0)
                .foregroundStyle(Color.nbMuted)

            Spacer(minLength: 0)

            Text("Noch kein Tempo-Test")
                .font(.nbSans(15, weight: .semibold))
                .foregroundStyle(Color.nbInk)
            Text("In der App starten")
                .font(.nbSans(12))
                .foregroundStyle(Color.nbMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
