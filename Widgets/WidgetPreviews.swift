import SwiftUI
import WidgetKit
import NetzblickKit

// MARK: - Status

#Preview(as: .systemSmall) {
    StatusWidget()
} timeline: {
    SummaryEntry(date: .now, summary: WidgetSummary.placeholder, isPlaceholder: false)
}

#Preview(as: .accessoryCircular) {
    StatusWidget()
} timeline: {
    SummaryEntry(date: .now, summary: WidgetSummary.placeholder, isPlaceholder: false)
}

#Preview(as: .systemSmall) {
    StatusWidget()
} timeline: {
    SummaryEntry(date: .now, summary: nil, isPlaceholder: false)
}

// MARK: - Overview

#Preview(as: .systemMedium) {
    OverviewWidget()
} timeline: {
    SummaryEntry(date: .now, summary: WidgetSummary.placeholder, isPlaceholder: false)
}

#Preview(as: .accessoryRectangular) {
    OverviewWidget()
} timeline: {
    SummaryEntry(date: .now, summary: WidgetSummary.placeholder, isPlaceholder: false)
}

#Preview(as: .systemMedium) {
    OverviewWidget()
} timeline: {
    SummaryEntry(date: .now, summary: nil, isPlaceholder: false)
}

// MARK: - Speed

#Preview(as: .systemSmall) {
    SpeedWidget()
} timeline: {
    SummaryEntry(date: .now, summary: WidgetSummary.placeholder, isPlaceholder: false)
}

#Preview(as: .accessoryInline) {
    SpeedWidget()
} timeline: {
    SummaryEntry(date: .now, summary: WidgetSummary.placeholder, isPlaceholder: false)
}

#Preview(as: .systemSmall) {
    SpeedWidget()
} timeline: {
    SummaryEntry(
        date: .now,
        summary: WidgetSummary(
            updatedAt: .now,
            boxName: "FRITZ!Box",
            devicesOnline: 12,
            newDevices: 0,
            findingCount: 0
        ),
        isPlaceholder: false
    )
}

#Preview(as: .systemSmall) {
    SpeedWidget()
} timeline: {
    SummaryEntry(date: .now, summary: nil, isPlaceholder: false)
}
