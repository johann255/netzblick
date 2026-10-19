import SwiftUI
import NetzblickKit

/// Colors of the three groups, as in the design: accent blue, orange, gray.
extension DomainGroup {
    func color(accent: Color) -> Color {
        switch self {
        case .normal: return accent
        case .tracking: return .nbOrange
        case .vendor: return .nbGray
        }
    }

    /// Order in bars and legends.
    static let displayOrder: [DomainGroup] = [.normal, .tracking, .vendor]
}

/// Share bar with legend for a set of counts per group.
struct ListenShareBar: View {
    let counts: [DomainGroup: Int]
    var height: CGFloat = 10

    @Environment(\.nbAccent) private var accent

    private var total: Int { counts.values.reduce(0, +) }

    private func percent(_ group: DomainGroup) -> Int {
        total == 0 ? 0 : Int((Double(counts[group] ?? 0) / Double(total) * 100).rounded())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            NBSegmentBar(
                segments: DomainGroup.displayOrder.map { (value: Double(counts[$0] ?? 0), color: $0.color(accent: accent)) },
                height: height,
                accessibilityLabel: DomainGroup.displayOrder.map { "\($0.label) \(percent($0)) Prozent" }.joined(separator: ", ")
            )

            FlowRow {
                ForEach(DomainGroup.displayOrder, id: \.self) { group in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(group.color(accent: accent))
                            .frame(width: 8, height: 8)
                        Text("\(group.label) \(percent(group)) %")
                    }
                    .font(.nbSans(13))
                    .foregroundStyle(Color.nbInkSoft)
                }
            }
            .accessibilityHidden(true)
        }
    }
}

extension ListenReport {
    var groupCounts: [DomainGroup: Int] {
        Dictionary(uniqueKeysWithValues: DomainGroup.allCases.map { ($0, count($0)) })
    }

    /// The device with the most advertising/tracking requests.
    var biggestChatterbox: DeviceListen? {
        devices.max { $0.count(.tracking) < $1.count(.tracking) }.flatMap { $0.count(.tracking) > 0 ? $0 : nil }
    }

    /// "heute 09:12–09:17"
    var timeLabel: String {
        let time = Date.FormatStyle(date: .omitted, time: .shortened).locale(Locale(identifier: "de_DE"))
        let day = Calendar.current.isDateInToday(startedAt)
            ? "heute"
            : startedAt.formatted(.dateTime.day().month(.wide).locale(Locale(identifier: "de_DE")))
        return "\(day) \(startedAt.formatted(time))–\(endedAt.formatted(time))"
    }
}

extension DeviceListen {
    var groupCounts: [DomainGroup: Int] {
        Dictionary(uniqueKeysWithValues: DomainGroup.allCases.map { ($0, count($0)) })
    }
}

/// Simple wrapping row for short legend items.
struct FlowRow: Layout {
    var spacing: CGFloat = 14
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxX: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            maxX = max(maxX, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxX, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

/// One contacted domain with its group dot, owner and count.
struct DomainRow: View {
    let entry: DomainCount

    @Environment(\.nbAccent) private var accent

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Circle()
                .fill(entry.match.group.color(accent: accent))
                .frame(width: 10, height: 10)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.match.domain)
                    .font(.nbSans(15, weight: .semibold))
                    .foregroundStyle(Color.nbInk)
                Text([entry.match.owner, entry.match.group.label].compactMap { $0 }.joined(separator: " · "))
                    .font(.nbSans(13))
                    .foregroundStyle(Color.nbMuted)
            }
            Spacer(minLength: 8)
            Text("\(entry.count)")
                .font(.nbSerif(24))
                .monospacedDigit()
                .foregroundStyle(Color.nbInk)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
