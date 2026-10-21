import Foundation

/// What a device most likely is, finer than `DeviceCategory`. Drives the icon and the "Gerätetyp" line.
/// A guess from name, manufacturer and Bonjour services; never shown as fact.
public enum DeviceKind: String, Codable, Sendable, CaseIterable {
    case unknown

    // Handys & Tablets
    case iPhone, smartphone, tablet, watch, eReader

    // Computer
    case laptop, desktop, nas, server, computer

    // Unterhaltung
    case tv, streamingBox, appleTV, speaker, homePod, avReceiver, console, mediaDevice

    // Smart Home
    case smartPlug, light, hub, thermostat, sensor, doorbell, lock, vacuum, mower,
         appliance, evCharger, solar, car, smartHomeDevice

    // Kameras, Drucker, Netzwerk
    case camera, printer, router, repeater, powerline

    public var category: DeviceCategory {
        switch self {
        case .unknown: return .unknown
        case .iPhone, .smartphone, .tablet, .watch, .eReader: return .phoneTablet
        case .laptop, .desktop, .nas, .server, .computer: return .computer
        case .tv, .streamingBox, .appleTV, .speaker, .homePod, .avReceiver, .console, .mediaDevice: return .entertainment
        case .smartPlug, .light, .hub, .thermostat, .sensor, .doorbell, .lock, .vacuum, .mower,
             .appliance, .evCharger, .solar, .car, .smartHomeDevice: return .smartHome
        case .camera: return .camera
        case .printer: return .printer
        case .router, .repeater, .powerline: return .network
        }
    }

    /// The generic kind used when only the category is known.
    public static func generic(for category: DeviceCategory) -> DeviceKind {
        switch category {
        case .unknown: return .unknown
        case .entertainment: return .mediaDevice
        case .phoneTablet: return .smartphone
        case .computer: return .computer
        case .smartHome: return .smartHomeDevice
        case .camera: return .camera
        case .printer: return .printer
        case .network: return .router
        }
    }

    /// SF Symbol for the device row.
    public var symbolName: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .iPhone: return "iphone"
        case .smartphone: return "smartphone"
        case .tablet: return "ipad"
        case .watch: return "applewatch"
        case .eReader: return "book"
        case .laptop: return "laptopcomputer"
        case .desktop: return "desktopcomputer"
        case .nas: return "externaldrive.connected.to.line.below"
        case .server: return "server.rack"
        case .computer: return "desktopcomputer"
        case .tv: return "tv"
        case .streamingBox: return "tv.and.mediabox"
        case .appleTV: return "appletv"
        case .speaker: return "hifispeaker"
        case .homePod: return "homepod"
        case .avReceiver: return "hifireceiver"
        case .console: return "gamecontroller"
        case .mediaDevice: return "play.tv"
        case .smartPlug: return "poweroutlet.type.f"
        case .light: return "lightbulb"
        case .hub: return "homekit"
        case .thermostat: return "thermometer.medium"
        case .sensor: return "sensor"
        case .doorbell: return "bell"
        case .lock: return "lock"
        case .vacuum: return "fan"
        case .mower: return "leaf"
        case .appliance: return "washer"
        case .evCharger: return "ev.charger"
        case .solar: return "sun.max"
        case .car: return "car"
        case .smartHomeDevice: return "house"
        case .camera: return "video"
        case .printer: return "printer"
        case .router: return "wifi.router"
        case .repeater: return "wifi"
        case .powerline: return "cable.connector"
        }
    }

    /// German name for the "Gerätetyp" line, e.g. "Laptop".
    public var title: String {
        switch self {
        case .unknown: return "unbekannt"
        case .iPhone: return "iPhone"
        case .smartphone: return "Smartphone"
        case .tablet: return "Tablet"
        case .watch: return "Uhr"
        case .eReader: return "E-Book-Reader"
        case .laptop: return "Laptop"
        case .desktop: return "Desktop-Rechner"
        case .nas: return "Netzwerkspeicher (NAS)"
        case .server: return "Server / Mini-Rechner"
        case .computer: return "Computer"
        case .tv: return "Fernseher"
        case .streamingBox: return "Streaming-Box"
        case .appleTV: return "Apple TV"
        case .speaker: return "Lautsprecher"
        case .homePod: return "HomePod"
        case .avReceiver: return "AV-Receiver"
        case .console: return "Spielkonsole"
        case .mediaDevice: return "Mediengerät"
        case .smartPlug: return "Smarte Steckdose"
        case .light: return "Licht"
        case .hub: return "Smart-Home-Zentrale"
        case .thermostat: return "Heizung / Thermostat"
        case .sensor: return "Sensor"
        case .doorbell: return "Türklingel"
        case .lock: return "Türschloss"
        case .vacuum: return "Saugroboter"
        case .mower: return "Mähroboter"
        case .appliance: return "Haushaltsgerät"
        case .evCharger: return "Wallbox"
        case .solar: return "Solaranlage / Speicher"
        case .car: return "Auto"
        case .smartHomeDevice: return "Smart-Home-Gerät"
        case .camera: return "Kamera"
        case .printer: return "Drucker"
        case .router: return "Router"
        case .repeater: return "Repeater / Mesh"
        case .powerline: return "Powerline-Adapter"
        }
    }
}
