import Foundation

/// Compact state shared with the widgets through the App Group container.
///
/// The app writes it after every reading; widgets only read it. Widgets never talk to the
/// FRITZ!Box themselves, so they always show "Stand vor …".
public struct WidgetSummary: Hashable, Codable, Sendable {
    public var updatedAt: Date
    public var boxName: String
    public var devicesOnline: Int
    public var newDevices: Int
    public var findingCount: Int
    /// Headline of the most important finding, if any.
    public var topFinding: String?
    /// Last speed test result in Mbit/s.
    public var lastSpeedMbps: Double?
    public var lastSpeedLevel: SpeedLevel?
    public var lastSpeedAt: Date?
    /// Share of requests that went to advertising/tracking in the last listening session (0–1), v1.1.
    public var trackingShare: Double?
    public var isDemo: Bool

    public init(
        updatedAt: Date,
        boxName: String,
        devicesOnline: Int,
        newDevices: Int,
        findingCount: Int,
        topFinding: String? = nil,
        lastSpeedMbps: Double? = nil,
        lastSpeedLevel: SpeedLevel? = nil,
        lastSpeedAt: Date? = nil,
        trackingShare: Double? = nil,
        isDemo: Bool = false
    ) {
        self.updatedAt = updatedAt
        self.boxName = boxName
        self.devicesOnline = devicesOnline
        self.newDevices = newDevices
        self.findingCount = findingCount
        self.topFinding = topFinding
        self.lastSpeedMbps = lastSpeedMbps
        self.lastSpeedLevel = lastSpeedLevel
        self.lastSpeedAt = lastSpeedAt
        self.trackingShare = trackingShare
        self.isDemo = isDemo
    }

    /// Example values for widget previews and the widget gallery.
    public static let placeholder = WidgetSummary(
        updatedAt: Date(timeIntervalSince1970: 1_792_000_000),
        boxName: "FRITZ!Box",
        devicesOnline: 23,
        newDevices: 1,
        findingCount: 2,
        topFinding: "Das iPad hängt im langsamen Band",
        lastSpeedMbps: 94,
        lastSpeedLevel: .fast,
        lastSpeedAt: Date(timeIntervalSince1970: 1_792_000_000),
        trackingShare: 0.31,
        isDemo: true
    )
}

/// Reads and writes `WidgetSummary` as JSON at a file URL (the App Group container in the app).
public struct WidgetSummaryStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func save(_ summary: WidgetSummary) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(summary)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    public func load() -> WidgetSummary? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSummary.self, from: data)
    }
}
