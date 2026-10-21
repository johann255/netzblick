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

    // MARK: - Kind and category

    public func category(for device: Device) -> DeviceCategory {
        kind(for: device).category
    }

    /// Best guess what the device is. Order: name, then Bonjour services, then manufacturer.
    public func kind(for device: Device) -> DeviceKind {
        if !Self.isDefaultName(device.name), let byName = Self.kind(forName: device.name) {
            return byName
        }
        for service in device.bonjourServices {
            if let byService = Self.serviceRules[service] { return byService }
        }
        if let vendor = device.vendor?.lowercased(),
           let byVendor = Self.vendorRules.first(where: { vendor.contains($0.0) })?.1 {
            return byVendor
        }
        return .unknown
    }

    /// FRITZ!OS names unnamed hosts "PC-192-168-178-40"; that "PC" says nothing.
    static func isDefaultName(_ name: String) -> Bool {
        name.range(of: #"^pc-\d+-\d+-\d+-\d+$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    static func kind(forName name: String) -> DeviceKind? {
        let normalized = normalize(name)
        let words = normalized.split(separator: " ").map(String.init)
        let padded = " " + normalized + " "
        for (pattern, kind) in nameRules {
            switch pattern {
            case let .part(text):
                if padded.contains(text) { return kind }
            case let .word(text):
                if words.contains(where: { matches(word: $0, text) }) { return kind }
            }
        }
        return nil
    }

    /// Lower-cased, everything that is not a letter or digit becomes one space ("Johanns-MBP" → "johanns mbp").
    static func normalize(_ name: String) -> String {
        let mapped = name.lowercased()
            .replacingOccurrences(of: "ä", with: "ae").replacingOccurrences(of: "ö", with: "oe")
            .replacingOccurrences(of: "ü", with: "ue").replacingOccurrences(of: "ß", with: "ss")
            .map { $0.isLetter || $0.isNumber ? $0 : " " }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    /// A word matches exactly or followed only by digits ("mbp" matches "mbp16", "ps" does not match "pse").
    private static func matches(word: String, _ text: String) -> Bool {
        guard word.hasPrefix(text) else { return false }
        return word.dropFirst(text.count).allSatisfy(\.isNumber)
    }

    enum Pattern: Sendable {
        /// Substring of the normalized name; add spaces around it to match whole words.
        case part(String)
        /// A whole word, optionally followed by digits.
        case word(String)
    }

    private static func parts(_ texts: [String], _ kind: DeviceKind) -> [(Pattern, DeviceKind)] {
        texts.map { (.part($0), kind) }
    }

    private static func words(_ texts: [String], _ kind: DeviceKind) -> [(Pattern, DeviceKind)] {
        texts.map { (.word($0), kind) }
    }

    /// Name keywords → kind. Checked in order; the more specific a rule, the earlier it stands.
    static let nameRules: [(Pattern, DeviceKind)] = {
        var r: [(Pattern, DeviceKind)] = []
        // AVM smart-home devices before the generic "fritz" rule.
        r += parts(["fritz dect 2", "fritzdect 2", "fritz smart energy 2"], .smartPlug)
        r += parts(["fritz dect 3", "fritzdect 3", "fritz smart thermo"], .thermostat)
        r += parts(["fritz dect 5", "fritzdect 5"], .light)
        r += parts(["repeater", "mesh", "fritz wlan", "access point"], .repeater)
        r += words(["eero", "deco", "unifi", "uap"], .repeater)
        r += parts(["powerline", "fritz powerline", "devolo", "dlan"], .powerline)
        r += words(["plc"], .powerline)
        r += parts(["fritz", "speedport", "router", "vodafone station"], .router)
        // Cameras before smart home, so "ring cam" or "tapo c200" land here (Fing's "find hidden cameras").
        r += parts(["kamera", "camera", "webcam", "ipcam", "reolink", "hikvision", "dahua", "eufycam", "tapo c", "blink"], .camera)
        r += words(["cam", "arlo", "wyze", "ipc", "foscam", "ezviz", "imou", "annke"], .camera)
        // Phones, tablets, watches
        r += parts(["iphone"], .iPhone)
        r += parts(["ipad", "galaxy tab", "fire tablet", "kindle fire", "mediapad", "tab s", "lenovo tab"], .tablet)
        r += parts(["apple watch", "applewatch", "galaxy watch", "pixel watch"], .watch)
        r += parts(["kindle", "tolino", "kobo", "pocketbook", "remarkable"], .eReader)
        r += parts(["galaxy", "android", "redmi", "xiaomi", "oneplus", "huawei", "honor", "oppo", "realme", "motorola", "nokia", "fairphone", "nothing phone", "poco", "smartphone", "handy"], .smartphone)
        r += words(["pixel", "moto", "phone", "sm"], .smartphone)
        r += words(["watch"], .watch)
        r += words(["tablet"], .tablet)
        // Computers
        r += parts(["macbook", "thinkpad", "ideapad", "zenbook", "vivobook", "elitebook", "probook", "chromebook", "notebook", "laptop", "surface", "latitude", "inspiron", "spectre", "matebook", "yoga"], .laptop)
        r += words(["mbp", "mba", "mb", "xps", "lt", "nb"], .laptop)
        r += parts(["imac", "mac mini", "macmini", "mac studio", "macstudio", "mac pro", "desktop", "workstation"], .desktop)
        r += words(["pc", "tower", "gaming"], .desktop)
        r += parts(["synology", "diskstation", "qnap", "truenas", "unraid", "netzwerkspeicher", "fritz nas"], .nas)
        r += words(["nas", "ds"], .nas)
        r += parts(["raspberry", "pihole", "pi hole", "homeassistant", "home assistant", "proxmox", "server", "nuc"], .server)
        r += words(["raspi", "rpi", "hass", "homebridge", "iobroker", "openhab"], .server)
        r += words(["mac"], .computer)
        // Entertainment
        r += parts(["playstation", "xbox", "nintendo", "steam deck", "steamdeck", "konsole"], .console)
        r += words(["ps"], .console)
        r += parts(["apple tv", "appletv"], .appleTV)
        r += parts(["chromecast", "fire tv", "firetv", "roku", "shield", "google tv", "magenta tv", "magentatv", "streaming", "waipu", "tv box", "mediabox", "media box", "tv stick", "zattoo", "kodi", "libreelec"], .streamingBox)
        r += parts(["homepod"], .homePod)
        r += parts(["sonos", "bose", "alexa", "nest audio", "nest mini", "google home", "home mini", "bluesound", "teufel", "raumfeld", "lautsprecher", "speaker", "soundbar", "marshall", "libratone", "denon home", "harman", "jbl", "ue boom", "beosound", "bang olufsen"], .speaker)
        r += words(["echo", "heos", "audio", "radio"], .speaker)
        r += parts(["receiver", "denon", "marantz", "yamaha", "onkyo", "pioneer"], .avReceiver)
        r += words(["avr"], .avReceiver)
        r += parts(["fernseher", "bravia", "webos", "lgwebostv", "tizen", "ambilight", "hisense", "smart tv", "smarttv", "philips tv", "grundig", "loewe", "metz"], .tv)
        r += words(["tv", "oled", "qled"], .tv)
        // Smart home
        r += parts(["klingel", "doorbell", "ring doorbell"], .doorbell)
        r += words(["ring"], .doorbell)
        r += parts(["nuki", "tuerschloss", "smartlock", "smart lock"], .lock)
        r += parts(["hue bridge", "bridge", "homematic", "raspberrymatic", "ccu", "conbee", "deconz", "zigbee", "homey", "aqara hub", "tado bridge", "smartthings", "home center", "homepilot", "gateway"], .hub)
        r += words(["hub"], .hub)
        r += parts(["tado", "thermostat", "heizung", "netatmo", "ecobee", "comet dect", "viessmann", "vaillant", "buderus", "waermepumpe", "heatpump", "daikin", "klima"], .thermostat)
        r += parts(["steckdose", "plug", "meross", "shelly", "tasmota", "sonoff", "tapo p", "kasa", "gosund", "nous", "switchbot", "smart socket", "relay", "relais"], .smartPlug)
        r += parts(["hue", "nanoleaf", "lifx", "tradfri", "govee", "yeelight", "lampe", "licht", "light", "bulb", "leuchte", "led strip", "ledstrip", "wled", "twinkly"], .light)
        r += words(["wiz", "led"], .light)
        r += parts(["aqara", "sensor", "airthings", "awair", "wetter", "weather", "luftqualitaet", "rauchmelder", "smoke", "leak", "eve "], .sensor)
        r += words(["eve"], .sensor)
        r += parts(["roborock", "roomba", "irobot", "ecovacs", "deebot", "dreame", "staubsauger", "sauger", "vacuum", "neato", "rockrobo", "valetudo", "saugroboter", "wischroboter"], .vacuum)
        r += parts(["maehroboter", "mower", "automower", "gardena", "landroid", "worx", "rasenmaeher"], .mower)
        r += parts(["miele", "homeconnect", "home connect", "bsh", "waschmaschine", "washer", "trockner", "dryer", "geschirrspueler", "spuelmaschine", "dishwasher", "kuehlschrank", "fridge", "backofen", "oven", "thermomix", "kaffee", "coffee", "jura", "delonghi", "dunstabzug", "airfryer"], .appliance)
        r += parts(["wallbox", "easee", "openwb", "keba", "go echarger", "goe charger", "ev charger", "zappi", "ladestation"], .evCharger)
        r += parts(["wechselrichter", "inverter", "fronius", "kostal", "solaredge", "enphase", "envoy", "hoymiles", "opendtu", "ahoy", "zendure", "solix", "ecoflow", "powerstation", "batteriespeicher", "solar", "photovoltaik"], .solar)
        r += words(["sma", "pv"], .solar)
        r += parts(["tesla", "polestar", "volkswagen", "bmw", "skoda"], .car)
        r += parts(["tuya", "smartlife", "smart life"], .smartHomeDevice)
        r += words(["esp", "nodemcu", "wemos"], .smartHomeDevice)
        // Printers
        r += parts(["drucker", "printer", "officejet", "deskjet", "laserjet", "pixma", "ecotank", "workforce", "brother", "epson", "canon", "kyocera", "xerox", "lexmark", "ricoh"], .printer)
        r += words(["mfc", "dcp", "hl", "hp"], .printer)
        return r
    }()

    static let serviceRules: [String: DeviceKind] = [
        "_sonos._tcp": .speaker,
        "_googlecast._tcp": .streamingBox,
        "_airplay._tcp": .mediaDevice,
        "_raop._tcp": .speaker,
        "_spotify-connect._tcp": .speaker,
        "_ipp._tcp": .printer,
        "_printer._tcp": .printer,
        "_pdl-datastream._tcp": .printer,
        "_hap._tcp": .smartHomeDevice,
        "_matter._tcp": .smartHomeDevice,
        "_companion-link._tcp": .smartphone,
        "_rtsp._tcp": .camera
    ]

    /// Manufacturer (from the MAC prefix) → kind. Only makers that build one kind of device.
    static let vendorRules: [(String, DeviceKind)] = [
        ("hikvision", .camera), ("dahua", .camera), ("reolink", .camera), ("axis", .camera),
        ("arlo", .camera), ("wyze", .camera), ("foscam", .camera), ("amcrest", .camera), ("ezviz", .camera),
        ("sonos", .speaker), ("bose", .speaker), ("bluesound", .speaker),
        ("meross", .smartPlug), ("shelly", .smartPlug), ("allterco", .smartPlug),
        ("eve systems", .sensor), ("aqara", .sensor), ("lumi united", .sensor),
        ("signify", .hub), ("philips lighting", .hub), ("nanoleaf", .light), ("lifx", .light),
        ("tado", .thermostat), ("netatmo", .thermostat), ("nuki", .lock), ("ring", .doorbell),
        ("roborock", .vacuum), ("ecovacs", .vacuum), ("irobot", .vacuum), ("dreame", .vacuum),
        ("husqvarna", .mower),
        ("synology", .nas), ("qnap", .nas),
        ("raspberry", .server),
        ("nintendo", .console), ("sony interactive", .console), ("valve", .console),
        ("roku", .streamingBox),
        ("brother", .printer), ("seiko epson", .printer), ("canon", .printer), ("kyocera", .printer),
        ("miele", .appliance), ("bsh", .appliance),
        ("fronius", .solar), ("sma solar", .solar),
        ("tesla", .car),
        ("ubiquiti", .repeater),
        ("avm", .router),
        ("espressif", .smartHomeDevice), ("tuya", .smartHomeDevice)
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
        // Cameras. VERIFY against the IEEE list when the full table replaces this seed.
        "C056E3": "Hikvision", "4CBD8F": "Hikvision", "BCAD28": "Hikvision", "44197B": "Hikvision",
        "3CEF8C": "Dahua", "E0508B": "Dahua", "9C1463": "Dahua",
        "EC71DB": "Reolink", "00408C": "Axis", "ACCC8E": "Axis", "B8A44F": "Axis",
        "2CAA8E": "Wyze", "D03F27": "Wyze",
        // Raspberry Pi
        "B827EB": "Raspberry Pi", "DCA632": "Raspberry Pi", "E45F01": "Raspberry Pi"
    ]
}
