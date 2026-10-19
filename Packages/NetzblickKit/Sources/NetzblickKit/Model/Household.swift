import Foundation

/// Basic facts about the FRITZ!Box itself.
public struct BoxInfo: Hashable, Codable, Sendable {
    public var modelName: String
    public var firmwareVersion: String?
    public var updateAvailable: Bool

    public init(modelName: String, firmwareVersion: String? = nil, updateAvailable: Bool = false) {
        self.modelName = modelName
        self.firmwareVersion = firmwareVersion
        self.updateAvailable = updateAvailable
    }
}

/// State of the internet connection as seen by the FRITZ!Box.
public struct WANStatus: Hashable, Codable, Sendable {
    public var isUp: Bool
    /// Synchronised line rate (what the line can carry) in Mbit/s.
    public var maxDownstreamMbps: Double?
    public var maxUpstreamMbps: Double?

    public init(isUp: Bool, maxDownstreamMbps: Double? = nil, maxUpstreamMbps: Double? = nil) {
        self.isUp = isUp
        self.maxDownstreamMbps = maxDownstreamMbps
        self.maxUpstreamMbps = maxUpstreamMbps
    }
}

/// One Wi-Fi radio of the FRITZ!Box.
public struct WLANRadio: Hashable, Codable, Sendable {
    public var band: WiFiBand
    public var isEnabled: Bool
    public var channel: Int?
    public var ssid: String?
    public var isGuest: Bool

    public init(band: WiFiBand, isEnabled: Bool, channel: Int? = nil, ssid: String? = nil, isGuest: Bool = false) {
        self.band = band
        self.isEnabled = isEnabled
        self.channel = channel
        self.ssid = ssid
        self.isGuest = isGuest
    }
}

/// A complete reading of the home network at one point in time.
public struct HouseholdSnapshot: Hashable, Codable, Sendable {
    public var takenAt: Date
    public var box: BoxInfo
    public var wan: WANStatus?
    public var radios: [WLANRadio]
    public var devices: [Device]
    /// Security settings of the router; nil if the router cannot report them.
    public var security: SecurityStatus?
    /// Parts of the reading that failed without stopping the rest, in plain German.
    public var warnings: [String]

    public init(
        takenAt: Date = Date(),
        box: BoxInfo,
        wan: WANStatus? = nil,
        radios: [WLANRadio] = [],
        devices: [Device] = [],
        security: SecurityStatus? = nil,
        warnings: [String] = []
    ) {
        self.takenAt = takenAt
        self.box = box
        self.wan = wan
        self.radios = radios
        self.devices = devices
        self.security = security
        self.warnings = warnings
    }

    public var activeDevices: [Device] { devices.filter(\.isActive) }

    /// Devices grouped by category in display order. Guests are returned separately.
    public var groupedDevices: [(category: DeviceCategory, devices: [Device])] {
        let home = devices.filter { !$0.isGuest }
        let groups = Dictionary(grouping: home, by: \.category)
        return groups
            .map { (category: $0.key, devices: $0.value.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }) }
            .sorted { $0.category.sortOrder < $1.category.sortOrder }
    }

    public var guestDevices: [Device] { devices.filter(\.isGuest) }

    /// The home-network device with this IPv4 address, if the router lists one.
    public func device(ip: String) -> Device? {
        devices.first { $0.ipAddress == ip && !$0.isGuest }
    }

    /// True if any 5 GHz or 6 GHz radio is switched on.
    public var hasFastRadio: Bool {
        radios.contains { $0.isEnabled && !$0.isGuest && $0.band != .ghz24 }
    }
}
