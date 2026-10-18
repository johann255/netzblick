import SwiftUI
import WidgetKit
import NetzblickKit

// MARK: - Timeline

/// One widget entry. `summary` is nil until the app has written its first summary.
struct SummaryEntry: TimelineEntry {
    let date: Date
    let summary: WidgetSummary?
    let isPlaceholder: Bool
}

/// Reads the stored summary. Widgets only read; they never talk to the FRITZ!Box.
struct SummaryProvider: TimelineProvider {
    func placeholder(in context: Context) -> SummaryEntry {
        SummaryEntry(date: .now, summary: WidgetSummary.placeholder, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (SummaryEntry) -> Void) {
        // Gallery and previews show example data, never the user's own network.
        if context.isPreview {
            completion(SummaryEntry(date: .now, summary: WidgetSummary.placeholder, isPlaceholder: true))
        } else {
            completion(storedEntry(now: .now))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SummaryEntry>) -> Void) {
        let now = Date.now
        let timeline = Timeline(
            entries: [storedEntry(now: now)],
            policy: .after(now.addingTimeInterval(30 * 60))
        )
        completion(timeline)
    }

    private func storedEntry(now: Date) -> SummaryEntry {
        SummaryEntry(
            date: now,
            summary: SharedContainer.summaryStore().load(),
            isPlaceholder: false
        )
    }
}

// MARK: - Shared copy and formatting

enum WidgetCopy {
    static let emptyState = "Öffne Netzblick einmal, dann erscheint hier dein Heimnetz."
}

/// German relative age, e.g. "gerade eben", "vor 5 Min.", "vor 2 Std.", "vor 3 Tagen".
func relativeAge(_ date: Date, now: Date) -> String {
    let seconds = now.timeIntervalSince(date)
    if seconds < 60 {
        return "gerade eben"
    }
    let minutes = Int(seconds / 60)
    if minutes < 60 {
        return "vor \(minutes) Min."
    }
    let hours = minutes / 60
    if hours < 24 {
        return "vor \(hours) Std."
    }
    let days = hours / 24
    return days == 1 ? "vor 1 Tag" : "vor \(days) Tagen"
}

/// Footer line: "Stand vor 5 Min.", or "Demo" for example data.
func standLine(_ summary: WidgetSummary, now: Date) -> String {
    summary.isDemo ? "Demo" : "Stand \(relativeAge(summary.updatedAt, now: now))"
}

func findingCountText(_ count: Int) -> String {
    count == 1 ? "1 Hinweis" : "\(count) Hinweise"
}

/// Short speed text for lock-screen widgets, e.g. "94 Mbit/s · schnell".
func speedShortText(_ summary: WidgetSummary) -> String {
    guard let mbps = summary.lastSpeedMbps else {
        return "Kein Tempo-Test"
    }
    guard let level = summary.lastSpeedLevel else {
        return "\(Int(mbps)) Mbit/s"
    }
    return "\(Int(mbps)) Mbit/s · \(level.label)"
}

// MARK: - Accent and speed colors

enum WidgetAccent {
    /// Accent chosen in the app, mirrored into the App Group. Falls back to Ultramarin.
    static var current: Color {
        let stored = UserDefaults(suiteName: SharedContainer.appGroupID)?.string(forKey: "accentBlue")
        let accent = stored.flatMap { AccentBlue(rawValue: $0) } ?? .ultramarin
        return accent.color
    }
}

extension SpeedLevel {
    /// Traffic-light fill for a speed result.
    var widgetColor: Color {
        switch self {
        case .slow: return .nbSpeedSlow
        case .ok: return .nbSpeedOk
        case .fast: return .nbSpeedFast
        }
    }

    /// Text color on top of `widgetColor`. Yellow gets dark ink for contrast.
    var widgetTextColor: Color {
        switch self {
        case .ok: return Color.black.opacity(0.85)
        case .slow, .fast: return .white
        }
    }
}
