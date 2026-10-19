import Foundation

/// Which kind of router a reading comes from.
public enum RouterKind: String, Codable, Sendable {
    case fritzBox
    case demo
}

/// What a router integration can deliver. Screens hide what a router cannot report.
public struct RouterCapabilities: OptionSet, Hashable, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }

    /// List of devices in the home network.
    public static let devices = RouterCapabilities(rawValue: 1 << 0)
    /// Band, signal and link rate per Wi-Fi device.
    public static let wifiDetails = RouterCapabilities(rawValue: 1 << 1)
    /// Whether the internet line is up, and its synchronised rate.
    public static let lineStatus = RouterCapabilities(rawValue: 1 << 2)
    /// Current traffic through the internet line.
    public static let liveThroughput = RouterCapabilities(rawValue: 1 << 3)
    /// Whether a firmware update is waiting.
    public static let firmwareStatus = RouterCapabilities(rawValue: 1 << 4)

    /// Listening to which addresses devices ask for (DNS), via a packet capture.
    public static let dnsListening = RouterCapabilities(rawValue: 1 << 5)
    /// Wi-Fi encryption, port forwardings and remote access, for the security check.
    public static let securityCheck = RouterCapabilities(rawValue: 1 << 6)
    /// Waking a sleeping device (Wake on LAN) through the router.
    public static let wakeOnLAN = RouterCapabilities(rawValue: 1 << 7)

    public static let all: RouterCapabilities = [.devices, .wifiDetails, .lineStatus, .liveThroughput, .firmwareStatus, .dnsListening, .securityCheck, .wakeOnLAN]
}

/// Current traffic through the internet line, as reported by the router.
public struct LiveThroughput: Hashable, Sendable {
    public var downstreamMbps: Double
    public var upstreamMbps: Double

    public init(downstreamMbps: Double, upstreamMbps: Double) {
        self.downstreamMbps = downstreamMbps
        self.upstreamMbps = upstreamMbps
    }
}

/// The one seam between Netzblick and a concrete router.
///
/// Everything above it (diagnosis, classification, screens, widgets) works on
/// `HouseholdSnapshot` only and never knows which router delivered it.
public protocol RouterAdapter: Sendable {
    var kind: RouterKind { get }
    var capabilities: RouterCapabilities { get }

    /// A complete reading of the home network. Throws only if nothing useful can be read
    /// (e.g. wrong login); partial failures end up in `HouseholdSnapshot.warnings`.
    func readSnapshot(now: Date) async throws -> HouseholdSnapshot

    /// Current up/down traffic on the internet line. Only called if `capabilities` contains `.liveThroughput`.
    func readLiveThroughput() async throws -> LiveThroughput

    /// Asks the router to send a Wake-on-LAN packet. Changes no setting.
    /// Only called if `capabilities` contains `.wakeOnLAN`.
    func wakeUp(macAddress: String) async throws
}

public extension RouterAdapter {
    func readSnapshot() async throws -> HouseholdSnapshot {
        try await readSnapshot(now: Date())
    }
}
