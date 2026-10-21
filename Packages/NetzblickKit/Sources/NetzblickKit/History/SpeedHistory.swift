import Foundation

/// All speed tests on this iPhone, oldest first (Fing's speed-test history, kept locally).
public struct SpeedHistory: Hashable, Codable, Sendable {
    public static let maxCount = 100

    public private(set) var results: [SpeedResult] = []

    public init(results: [SpeedResult] = []) {
        self.results = Array(results.sorted { $0.measuredAt < $1.measuredAt }.suffix(Self.maxCount))
    }

    public mutating func append(_ result: SpeedResult) {
        results.append(result)
        if results.count > Self.maxCount { results.removeFirst(results.count - Self.maxCount) }
    }

    public var latest: SpeedResult? { results.last }

    /// The newest `count` results, oldest first, for a small bar chart.
    public func recent(_ count: Int = 10) -> [SpeedResult] {
        Array(results.suffix(count))
    }

    /// Results within `days` before `now`.
    public func within(days: Int, of now: Date = Date()) -> [SpeedResult] {
        let cutoff = now.addingTimeInterval(-Double(days) * 24 * 3600)
        return results.filter { $0.measuredAt >= cutoff }
    }

    /// Median download over the last `days` days; nil without measurements.
    public func medianMbps(days: Int = 30, now: Date = Date()) -> Double? {
        let values = within(days: days, of: now).map(\.downloadMbps).sorted()
        guard !values.isEmpty else { return nil }
        let mid = values.count / 2
        return values.count.isMultiple(of: 2) ? (values[mid - 1] + values[mid]) / 2 : values[mid]
    }

    /// How many of the last `days` days' measurements came out red, yellow and green.
    public func levelCounts(days: Int = 30, bookedMbps: Double?, now: Date = Date()) -> [SpeedLevel: Int] {
        var counts: [SpeedLevel: Int] = [:]
        for result in within(days: days, of: now) {
            counts[SpeedRating.rate(downloadMbps: result.downloadMbps, bookedMbps: bookedMbps).level, default: 0] += 1
        }
        return counts
    }

    /// One plain-German line, e.g. "Typisch in den letzten 30 Tagen: 87 Mbit/s (6 Messungen, 1 davon langsam)."
    public func summary(bookedMbps: Double?, now: Date = Date()) -> String? {
        let recent = within(days: 30, of: now)
        guard recent.count >= 2, let median = medianMbps(days: 30, now: now) else { return nil }
        var line = "Typisch in den letzten 30 Tagen: \(Int(median.rounded())) Mbit/s (\(recent.count) Messungen"
        let slow = levelCounts(days: 30, bookedMbps: bookedMbps, now: now)[.slow] ?? 0
        if slow > 0 { line += ", \(slow) davon langsam" }
        return line + ")."
    }
}
