import Foundation

/// How much a finding matters. Sorted from most to least important.
public enum Severity: Int, Codable, Sendable, Comparable {
    case high = 0
    case medium = 1
    case info = 2

    public static func < (lhs: Severity, rhs: Severity) -> Bool { lhs.rawValue < rhs.rawValue }

    public var label: String {
        switch self {
        case .high: return "Größter Effekt"
        case .medium: return "Mittel"
        case .info: return "Hinweis"
        }
    }
}

/// What kind of problem a finding describes. Stable identifiers for analytics-free UI logic.
public enum FindingKind: String, Codable, Sendable {
    case internetDown
    case firmwareUpdate
    case slowBand
    case weakSignal
    case wifiBottleneck
}

/// A plain-language problem with a suggested next step.
/// Netzblick v1.0 never changes FRITZ!Box settings itself; `howTo` explains the steps.
public struct Finding: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var kind: FindingKind
    public var severity: Severity
    /// Short headline, e.g. "Das iPad hängt im langsamen Band".
    public var title: String
    /// One or two sentences in plain German.
    public var explanation: String
    /// Short scope label, e.g. "1 Gerät" or "ganzes WLAN".
    public var scope: String
    /// Ids of the devices this finding is about.
    public var deviceIDs: [String]
    /// Step-by-step instructions shown on "So stellst du es ein".
    public var howTo: [String]

    public init(
        id: String,
        kind: FindingKind,
        severity: Severity,
        title: String,
        explanation: String,
        scope: String,
        deviceIDs: [String] = [],
        howTo: [String] = []
    ) {
        self.id = id
        self.kind = kind
        self.severity = severity
        self.title = title
        self.explanation = explanation
        self.scope = scope
        self.deviceIDs = deviceIDs
        self.howTo = howTo
    }
}
