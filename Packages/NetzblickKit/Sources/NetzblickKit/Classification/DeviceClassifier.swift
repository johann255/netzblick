import Foundation

/// Guesses manufacturer and category of a device from its MAC prefix, name and Bonjour services.
/// Everything runs locally against tables shipped with the app.
public struct DeviceClassifier: Sendable {
    /// Maps a 6-hex-digit OUI ("38:10:D5" → "3810D5") to a vendor name.
    private let vendors: [String: String]

    public init(vendors: [String: String] = DeviceClassifier.seedVendors) {
        self.vendors = vendors
    }

    // MARK: - Vendor

    /// True for "private" (randomised) MAC addresses that phones use per network.
    /// Those carry no manufacturer information, so they must not be flagged as suspicious.
    public static func isRandomized(mac: String) -> Bool {
        let hex = mac.filter(\.isHexDigit)
        guard hex.count >= 2, let firstByte = UInt8(hex.prefix(2), radix: 16) else { return false }
        return firstByte & 0b0000_0010 != 0 // locally administered bit
    }

    public func vendor(forMAC mac: String) -> String? {
        if Self.isRandomized(mac: mac) { return nil }
        let hex = mac.uppercased().filter(\.isHexDigit)
        guard hex.count >= 6 else { return nil }
        return vendors[String(hex.prefix(6))]
    }

    // MARK: - Category

    public func category(for device: Device) -> DeviceCategory {
        let name = device.name.lowercased()
        if let byName = Self.rule(for: name, in: Self.nameRules) { return byName }
        for service in device.bonjourServices {
            if let byService = Self.serviceRules[service] { return byService }
        }
        if let vendor = device.vendor?.lowercased(), let byVendor = Self.rule(for: vendor, in: Self.vendorRules) {
            return byVendor
        }
        return .unknown
    }

    private static func rule(for text: String, in rules: [(String, DeviceCategory)]) -> DeviceCategory? {
        rules.first { text.contains($0.0) }?.1
    }

    /// Keyword in the device name → category. Checked in order; more specific words first.
    static let nameRules: [(String, DeviceCategory)] = [
        ("repeater", .network), ("fritz", .network), ("powerline", .network), ("mesh", .network),
        ("iphone", .phoneTablet), ("ipad", .phoneTablet), ("android", .phoneTablet), ("galaxy", .phoneTablet),
        ("pixel", .phoneTablet), ("handy", .phoneTablet), ("tablet", .phoneTablet), ("redmi", .phoneTablet),
        ("macbook", .computer), ("imac", .computer), ("mac-mini", .computer), ("laptop", .computer),
        ("notebook", .computer), ("desktop", .computer), ("-pc", .computer), ("thinkpad", .computer),
        ("drucker", .printer), ("printer", .printer), ("epson", .printer), ("brother", .printer), ("canon", .printer),
        ("fernseher", .entertainment), ("-tv", .entertainment), ("tv-", .entertainment), ("bravia", .entertainment),
        ("sonos", .entertainment), ("playstation", .entertainment), ("ps5", .entertainment), ("xbox", .entertainment),
        ("nintendo", .entertainment), ("chromecast", .entertainment), ("firetv", .entertainment), ("fire-tv", .entertainment),
        ("appletv", .entertainment), ("apple-tv", .entertainment), ("roku", .entertainment), ("echo", .entertainment),
        ("homepod", .entertainment), ("lautsprecher", .entertainment), ("speaker", .entertainment),
        ("shelly", .smartHome), ("tasmota", .smartHome), ("esp-", .smartHome), ("esp_", .smartHome),
        ("hue", .smartHome), ("tado", .smartHome), ("thermostat", .smartHome), ("steckdose", .smartHome),
        ("roborock", .smartHome), ("roomba", .smartHome), ("sauger", .smartHome), ("klingel", .smartHome),
        ("ring-", .smartHome), ("nest", .smartHome), ("wallbox", .smartHome), ("wechselrichter", .smartHome),
        ("inverter", .smartHome)
    ]

    static let serviceRules: [String: DeviceCategory] = [
        "_sonos._tcp": .entertainment,
        "_googlecast._tcp": .entertainment,
        "_airplay._tcp": .entertainment,
        "_raop._tcp": .entertainment,
        "_spotify-connect._tcp": .entertainment,
        "_ipp._tcp": .printer,
        "_printer._tcp": .printer,
        "_hap._tcp": .smartHome,
        "_matter._tcp": .smartHome,
        "_companion-link._tcp": .phoneTablet
    ]

    static let vendorRules: [(String, DeviceCategory)] = [
        ("sonos", .entertainment),
        ("avm", .network),
        ("espressif", .smartHome),
        ("raspberry", .computer)
    ]

    /// A small seed table of well-known prefixes. Replace with the full IEEE list via
    /// `scripts/update-oui.py` before release.
    public static let seedVendors: [String: String] = [
        // AVM / FRITZ!
        "3810D5": "AVM", "3CA62F": "AVM", "2C91AB": "AVM", "C80E14": "AVM", "444E6D": "AVM",
        "E0286D": "AVM", "9CC7A6": "AVM", "7CFF4D": "AVM", "BC0543": "AVM", "DC396F": "AVM",
        // Sonos
        "000E58": "Sonos", "5CAAFD": "Sonos", "949F3E": "Sonos", "48A6B8": "Sonos", "B8E937": "Sonos", "7828CA": "Sonos",
        // Espressif (chips in many smart-home devices)
        "240AC4": "Espressif", "30AEA4": "Espressif", "A4CF12": "Espressif", "84CCA8": "Espressif",
        "BCDDC2": "Espressif", "246F28": "Espressif", "ECFABC": "Espressif", "3C71BF": "Espressif",
        // Raspberry Pi
        "B827EB": "Raspberry Pi", "DCA632": "Raspberry Pi", "E45F01": "Raspberry Pi"
    ]
}
