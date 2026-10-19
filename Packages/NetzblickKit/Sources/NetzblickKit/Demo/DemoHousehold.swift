import Foundation

/// Fixed demo household for the App Review and the first-run tour.
///
/// Deterministic: every call returns the same devices and values. Only the
/// timestamps follow the `now` parameter.
public enum DemoHousehold {

    /// Id of the unknown Espressif device, which counts as "new" in the demo.
    public static let newDeviceIDs: Set<String> = [
        Device.makeID(mac: "02:4E:42:00:00:01", ip: nil)
    ]

    /// A complete reading of the demo home network.
    public static func snapshot(now: Date = Date()) -> HouseholdSnapshot {
        HouseholdSnapshot(
            takenAt: now,
            box: BoxInfo(modelName: "FRITZ!Box 7590 AX", firmwareVersion: "8.03", updateAvailable: true),
            wan: WANStatus(isUp: true, maxDownstreamMbps: 100, maxUpstreamMbps: 40),
            radios: [
                WLANRadio(band: .ghz24, isEnabled: true, channel: 6, ssid: "Zuhause"),
                WLANRadio(band: .ghz5, isEnabled: true, channel: 36, ssid: "Zuhause"),
                WLANRadio(band: .ghz24, isEnabled: true, ssid: "Zuhause Gast", isGuest: true)
            ],
            devices: devices,
            security: security,
            warnings: []
        )
    }

    /// One forwarding to the NAS and remote access via MyFRITZ!, so the security screen has something to show.
    private static var security: SecurityStatus {
        SecurityStatus(
            wlans: [
                WLANSecurity(band: .ghz24, ssid: "Zuhause", encryption: .wpa2wpa3),
                WLANSecurity(band: .ghz5, ssid: "Zuhause", encryption: .wpa2wpa3),
                WLANSecurity(band: .ghz24, ssid: "Zuhause Gast", isGuest: true, encryption: .wpa2)
            ],
            portForwardings: [
                PortForwarding(externalPort: 5001, internalPort: 5001, transport: .tcp,
                               internalClient: "192.168.178.37", note: "Synology DSM")
            ],
            remoteAccess: RemoteAccess(httpsEnabled: false, myFritzEnabled: true),
            wpsPinEnabled: false
        )
    }

    /// The widget summary that matches the demo snapshot and the design mockup.
    public static func summary(now: Date = Date()) -> WidgetSummary {
        let snap = snapshot(now: now)
        return WidgetSummary(
            updatedAt: now,
            boxName: snap.box.modelName,
            devicesOnline: snap.activeDevices.count,
            newDevices: newDeviceIDs.count,
            findingCount: 2,
            topFinding: "Das iPad hängt im langsamen Band",
            lastSpeedMbps: 94,
            lastSpeedLevel: .fast,
            lastSpeedAt: now,
            trackingShare: 0.31,
            isDemo: true
        )
    }

    /// A presence history for the demo: a few days of phones coming and going, and the new device arriving.
    public static func presenceLog(now: Date = Date()) -> PresenceLog {
        let all = devices
        let newID = newDeviceIDs.first
        let phones: Set<String> = ["Mein iPhone", "Annas iPhone", "Galaxy S24", "MacBook", "Laptop Arbeit"]
        var log = PresenceLog()

        func reading(hoursAgo: Double, away: Set<String>, withNew: Bool) -> HouseholdSnapshot {
            let list = all.compactMap { device -> Device? in
                if device.id == newID && !withNew { return nil }
                var copy = device
                if phones.contains(device.name) { copy.isActive = !away.contains(device.name) }
                return copy
            }
            return HouseholdSnapshot(takenAt: now.addingTimeInterval(-hoursAgo * 3600), box: snapshot(now: now).box, devices: list)
        }

        // Weekday rhythm: work devices leave in the morning and come back in the evening.
        let schedule: [(Double, Set<String>, Bool)] = [
            (72, [], false), (62, ["Annas iPhone", "Laptop Arbeit"], false), (52, [], false),
            (38, ["Annas iPhone", "Laptop Arbeit", "Mein iPhone"], false), (28, [], false),
            (14, ["Annas iPhone", "Laptop Arbeit"], false), (5, ["Annas iPhone"], true), (0, [], true)
        ]
        for (hoursAgo, away, withNew) in schedule {
            log.record(reading(hoursAgo: hoursAgo, away: away, withNew: withNew))
        }
        return log
    }

    // MARK: - Devices (31 in total, 23 active)

    private static var devices: [Device] {
        [
            // Unknown
            device(1, "Espressif-Gerät", vendor: "Espressif", category: .unknown, connection: wlan(.ghz24, 55)),

            // Unterhaltung
            device(2, "Sonos Küche", vendor: "Sonos", category: .entertainment, connection: wlan(.ghz5, 82), bonjour: ["_sonos._tcp", "_airplay._tcp"]),
            device(3, "Sonos Wohnzimmer", vendor: "Sonos", category: .entertainment, connection: wlan(.ghz5, 85), bonjour: ["_sonos._tcp", "_airplay._tcp"]),
            device(4, "Sonos Bad", vendor: "Sonos", category: .entertainment, connection: wlan(.ghz5, 74), bonjour: ["_sonos._tcp", "_airplay._tcp"]),
            device(5, "Samsung Fernseher", vendor: "Samsung", category: .entertainment, connection: .ethernet),
            device(6, "Spielkonsole", vendor: "Sony", category: .entertainment, connection: wlan(.ghz5, 64), active: false),
            device(7, "Streaming-Box", vendor: "Amazon", category: .entertainment, connection: .ethernet),
            device(8, "Apple TV Schlafzimmer", vendor: "Apple", category: .entertainment, connection: .ethernet, active: false, bonjour: ["_airplay._tcp"]),

            // Handys & Tablets
            device(9, "Mein iPhone", vendor: "Apple", category: .phoneTablet, connection: wlan(.ghz5, 80)),
            device(10, "iPad Wohnzimmer", vendor: "Apple", category: .phoneTablet, connection: wlan(.ghz24, 25)),
            device(11, "Annas iPhone", vendor: "Apple", category: .phoneTablet, connection: wlan(.ghz5, 66)),
            device(12, "Galaxy S24", vendor: "Samsung", category: .phoneTablet, connection: wlan(.ghz5, 58)),
            device(13, "Pixel 8", vendor: "Google", category: .phoneTablet, connection: wlan(.ghz5, 61), active: false),
            device(14, "Fire-Tablet", vendor: "Amazon", category: .phoneTablet, connection: wlan(.ghz24, 44), active: false),

            // Computer
            device(15, "MacBook", vendor: "Apple", category: .computer, connection: wlan(.ghz5, 78)),
            device(16, "Laptop Arbeit", vendor: "Lenovo", category: .computer, connection: wlan(.ghz5, 72)),
            device(17, "Desktop PC", vendor: "ASUS", category: .computer, connection: .ethernet, active: false),
            device(18, "NAS Keller", vendor: "Synology", category: .computer, connection: .ethernet),

            // Smart Home
            device(19, "Heizungsthermostat Wohnzimmer", vendor: "AVM", category: .smartHome, connection: .unknown),
            device(20, "Heizungsthermostat Schlafzimmer", vendor: "AVM", category: .smartHome, connection: .unknown),
            device(21, "Heizungsthermostat Küche", vendor: "AVM", category: .smartHome, connection: .unknown),
            device(22, "Heizungsthermostat Bad", vendor: "AVM", category: .smartHome, connection: .unknown),
            device(23, "Saugroboter", vendor: "Roborock", category: .smartHome, connection: wlan(.ghz24, 60), active: false),
            device(24, "Smarte Steckdose 1", vendor: "Tuya", category: .smartHome, connection: wlan(.ghz24, 48)),
            device(25, "Smarte Steckdose 2", vendor: "Tuya", category: .smartHome, connection: wlan(.ghz24, 52)),
            device(26, "Smarte Steckdose 3", vendor: "Tuya", category: .smartHome, connection: wlan(.ghz24, 35), active: false),
            device(27, "Türklingel", vendor: "Siedle", category: .smartHome, connection: wlan(.ghz24, 40)),
            device(28, "Kamera Garten", vendor: "Reolink", category: .camera, connection: wlan(.ghz24, 47)),

            // Drucker (the camera above sits in its own group)
            device(29, "Drucker Arbeitszimmer", vendor: "HP", category: .printer, connection: wlan(.ghz24, 56), bonjour: ["_ipp._tcp"]),

            // Netzwerk
            device(30, "FRITZ!Repeater Flur", vendor: "AVM", category: .network, connection: wlan(.ghz5, 28)),

            // Gastnetz: counted, never analysed in detail
            device(31, "Laptop im Gastnetz", vendor: "Dell", category: .computer, connection: wlan(.ghz24, 50), active: false, guest: true)
        ]
    }

    private static func device(
        _ index: Int,
        _ name: String,
        vendor: String?,
        category: DeviceCategory,
        connection: Connection,
        active: Bool = true,
        guest: Bool = false,
        bonjour: [String] = []
    ) -> Device {
        let address = macAddress(index)
        return Device(
            id: Device.makeID(mac: address, ip: nil),
            name: name,
            macAddress: address,
            ipAddress: "192.168.178.\(19 + index)",
            isActive: active,
            isGuest: guest,
            connection: connection,
            vendor: vendor,
            category: category,
            bonjourServices: bonjour
        )
    }

    /// Locally administered MAC address derived from a running index: 02:4E:42:00:00:01, 02:4E:42:00:00:02, ...
    private static func macAddress(_ index: Int) -> String {
        let hex = String(index, radix: 16, uppercase: true)
        return "02:4E:42:00:00:" + (hex.count < 2 ? "0" + hex : hex)
    }

    private static func wlan(_ band: WiFiBand, _ signal: Int) -> Connection {
        .wifi(WiFiLink(band: band, signalPercent: signal))
    }
}
