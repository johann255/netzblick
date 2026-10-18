import Foundation

/// Frequency band of a Wi-Fi connection.
public enum WiFiBand: String, Codable, Sendable, CaseIterable {
    case ghz24 = "2.4"
    case ghz5 = "5"
    case ghz6 = "6"

    /// Human-readable label, e.g. "2,4 GHz".
    public var label: String {
        switch self {
        case .ghz24: return "2,4 GHz"
        case .ghz5: return "5 GHz"
        case .ghz6: return "6 GHz"
        }
    }
}

/// How a device is attached to the home network.
public enum Connection: Hashable, Codable, Sendable {
    case ethernet
    case wifi(WiFiLink)
    case unknown
}

/// Details of a Wi-Fi association as reported by the FRITZ!Box.
public struct WiFiLink: Hashable, Codable, Sendable {
    public var band: WiFiBand
    /// Signal strength in percent (0–100) as the FRITZ!Box reports it.
    public var signalPercent: Int?
    /// Current link rate in Mbit/s.
    public var rateMbps: Int?

    public init(band: WiFiBand, signalPercent: Int? = nil, rateMbps: Int? = nil) {
        self.band = band
        self.signalPercent = signalPercent
        self.rateMbps = rateMbps
    }

    /// Coarse quality bucket used throughout the UI.
    public var quality: SignalQuality {
        guard let s = signalPercent else { return .unknown }
        switch s {
        case ..<30: return .weak
        case 30..<60: return .fair
        default: return .strong
        }
    }
}

public enum SignalQuality: String, Codable, Sendable {
    case strong, fair, weak, unknown

    public var label: String {
        switch self {
        case .strong: return "starkes Signal"
        case .fair: return "mittleres Signal"
        case .weak: return "schwaches Signal"
        case .unknown: return "Signal unbekannt"
        }
    }
}

/// Broad device category, used for grouping and icons.
public enum DeviceCategory: String, Codable, Sendable, CaseIterable {
    case unknown
    case entertainment
    case phoneTablet
    case computer
    case smartHome
    case printer
    case network

    /// German group title shown in the device list.
    public var title: String {
        switch self {
        case .unknown: return "Unbekannt"
        case .entertainment: return "Unterhaltung"
        case .phoneTablet: return "Handys & Tablets"
        case .computer: return "Computer"
        case .smartHome: return "Smart Home"
        case .printer: return "Drucker"
        case .network: return "Netzwerk"
        }
    }

    /// SF Symbol name for this category.
    public var symbolName: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .entertainment: return "tv"
        case .phoneTablet: return "iphone"
        case .computer: return "laptopcomputer"
        case .smartHome: return "house"
        case .printer: return "printer"
        case .network: return "wifi.router"
        }
    }

    /// Order of groups in the device list (unknown first, it needs attention).
    public var sortOrder: Int {
        switch self {
        case .unknown: return 0
        case .entertainment: return 1
        case .phoneTablet: return 2
        case .computer: return 3
        case .smartHome: return 4
        case .printer: return 5
        case .network: return 6
        }
    }
}

/// One device known to the FRITZ!Box.
public struct Device: Identifiable, Hashable, Codable, Sendable {
    /// Stable identifier: the upper-cased MAC address, or "ip:<address>" when no MAC is known.
    public var id: String
    /// Name as stored in the FRITZ!Box (user may have renamed it there).
    public var name: String
    public var macAddress: String?
    public var ipAddress: String?
    /// Currently online.
    public var isActive: Bool
    /// Connected through the guest network. Guest devices are never analysed in detail.
    public var isGuest: Bool
    public var connection: Connection
    /// Manufacturer derived from the MAC address prefix, if known.
    public var vendor: String?
    public var category: DeviceCategory
    /// Bonjour service types seen for this device, e.g. "_sonos._tcp".
    public var bonjourServices: [String]

    public init(
        id: String,
        name: String,
        macAddress: String? = nil,
        ipAddress: String? = nil,
        isActive: Bool = true,
        isGuest: Bool = false,
        connection: Connection = .unknown,
        vendor: String? = nil,
        category: DeviceCategory = .unknown,
        bonjourServices: [String] = []
    ) {
        self.id = id
        self.name = name
        self.macAddress = macAddress
        self.ipAddress = ipAddress
        self.isActive = isActive
        self.isGuest = isGuest
        self.connection = connection
        self.vendor = vendor
        self.category = category
        self.bonjourServices = bonjourServices
    }

    /// Builds the stable id from a MAC or IP address.
    public static func makeID(mac: String?, ip: String?) -> String {
        if let mac, !mac.isEmpty { return mac.uppercased() }
        return "ip:\(ip ?? UUID().uuidString)"
    }

    public var wifi: WiFiLink? {
        if case let .wifi(link) = connection { return link }
        return nil
    }

    /// Short plain-language line under the device name, e.g. "WLAN 5 GHz · starkes Signal".
    public var connectionSummary: String {
        switch connection {
        case .ethernet: return "Kabel (LAN)"
        case let .wifi(link): return "WLAN \(link.band.label) · \(link.quality.label)"
        case .unknown: return isActive ? "Verbunden" : "Schläft gerade"
        }
    }
}
