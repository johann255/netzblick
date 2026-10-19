import Foundation

/// How a Wi-Fi network is protected, as far as the router reports it.
public enum WiFiEncryption: String, Codable, Sendable {
    /// No encryption at all: anyone nearby can join and read along.
    case open
    /// WEP, broken for decades.
    case wep
    /// WPA (TKIP) alone or mixed with WPA2.
    case wpaLegacy
    case wpa2
    /// WPA2 and WPA3 side by side, the FRITZ!Box default since FRITZ!OS 7.20.
    case wpa2wpa3
    case wpa3
    case unknown

    /// True if the protection is good enough today.
    public var isModern: Bool {
        [.wpa2, .wpa2wpa3, .wpa3].contains(self)
    }

    public var label: String {
        switch self {
        case .open: return "unverschlüsselt"
        case .wep: return "WEP (veraltet)"
        case .wpaLegacy: return "WPA (veraltet)"
        case .wpa2: return "WPA2"
        case .wpa2wpa3: return "WPA2 + WPA3"
        case .wpa3: return "WPA3"
        case .unknown: return "unbekannt"
        }
    }

    /// Maps the TR-064 `NewBeaconType` (plus `NewBasicEncryptionModes` for the "Basic" case).
    // VERIFY: exact BeaconType strings on FRITZ!OS 7.5x/8.x ("11i", "WPAand11i", "11iandWPA3", "WPA3", "None").
    public static func fromBeacon(_ beacon: String?, basicEncryption: String? = nil) -> WiFiEncryption {
        guard let raw = beacon?.lowercased(), !raw.isEmpty else { return .unknown }
        switch raw {
        case "none", "owetrans", "owe":
            // OWE encrypts without a password (hotspot style); still "open" to anyone nearby.
            return .open
        case "basic":
            return basicEncryption?.lowercased().contains("wep") == true ? .wep : .open
        case "wpa":
            return .wpaLegacy
        case "wpaand11i":
            return .wpaLegacy
        case "11i":
            return .wpa2
        case "11iandwpa3":
            return .wpa2wpa3
        case "wpa3":
            return .wpa3
        default:
            if raw.contains("wpa3") { return raw.contains("11i") ? .wpa2wpa3 : .wpa3 }
            return .unknown
        }
    }
}

/// Security-relevant settings of one Wi-Fi network.
public struct WLANSecurity: Hashable, Codable, Sendable {
    public var band: WiFiBand
    public var ssid: String?
    public var isGuest: Bool
    public var isEnabled: Bool
    public var encryption: WiFiEncryption

    public init(band: WiFiBand, ssid: String? = nil, isGuest: Bool = false, isEnabled: Bool = true, encryption: WiFiEncryption) {
        self.band = band
        self.ssid = ssid
        self.isGuest = isGuest
        self.isEnabled = isEnabled
        self.encryption = encryption
    }
}

/// A port opened from the internet to a device in the home network.
public struct PortForwarding: Hashable, Codable, Sendable {
    public enum TransportProtocol: String, Codable, Sendable {
        case tcp = "TCP"
        case udp = "UDP"
    }

    public var externalPort: Int
    public var internalPort: Int
    public var transport: TransportProtocol
    /// IPv4 address of the device the port leads to.
    public var internalClient: String
    public var isEnabled: Bool
    /// Free text from the router, e.g. the app that asked for the port via UPnP.
    public var note: String?

    public init(externalPort: Int, internalPort: Int, transport: TransportProtocol, internalClient: String,
                isEnabled: Bool = true, note: String? = nil) {
        self.externalPort = externalPort
        self.internalPort = internalPort
        self.transport = transport
        self.internalClient = internalClient
        self.isEnabled = isEnabled
        self.note = note
    }
}

/// How the router itself can be reached from the internet.
public struct RemoteAccess: Hashable, Codable, Sendable {
    /// "Internetzugriff auf die FRITZ!Box über HTTPS" is on.
    public var httpsEnabled: Bool
    public var httpsPort: Int?
    /// A MyFRITZ! account is set up and active.
    public var myFritzEnabled: Bool

    public init(httpsEnabled: Bool, httpsPort: Int? = nil, myFritzEnabled: Bool = false) {
        self.httpsEnabled = httpsEnabled
        self.httpsPort = httpsPort
        self.myFritzEnabled = myFritzEnabled
    }

    public var isReachableFromInternet: Bool { httpsEnabled || myFritzEnabled }
}

/// Everything the security check reads from the router. `nil` means "could not be read",
/// which the check shows as unknown instead of pretending it is fine.
public struct SecurityStatus: Hashable, Codable, Sendable {
    public var wlans: [WLANSecurity]
    public var portForwardings: [PortForwarding]?
    public var remoteAccess: RemoteAccess?
    /// WPS with PIN is on; the PIN can be brute-forced.
    public var wpsPinEnabled: Bool?

    public init(wlans: [WLANSecurity] = [], portForwardings: [PortForwarding]? = nil,
                remoteAccess: RemoteAccess? = nil, wpsPinEnabled: Bool? = nil) {
        self.wlans = wlans
        self.portForwardings = portForwardings
        self.remoteAccess = remoteAccess
        self.wpsPinEnabled = wpsPinEnabled
    }

    public var activeForwardings: [PortForwarding] {
        (portForwardings ?? []).filter(\.isEnabled)
    }
}
