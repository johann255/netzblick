import Foundation

/// Reads a complete `HouseholdSnapshot` from a FRITZ!Box.
///
/// Only the login check (DeviceInfo) is fatal. Every other part is read on a best-effort basis:
/// a failing part becomes a warning, so one missing service never blanks the whole app.
public struct FritzBoxReader: RouterAdapter {
    public let kind = RouterKind.fritzBox
    public let capabilities = RouterCapabilities.all
    public let client: TR064Client
    public let classifier: DeviceClassifier

    public init(client: TR064Client, classifier: DeviceClassifier = DeviceClassifier()) {
        self.client = client
        self.classifier = classifier
    }

    public func readSnapshot(now: Date) async throws -> HouseholdSnapshot {
        let catalog = try await client.loadCatalog()
        var warnings: [String] = []

        // 1. Box info. Fails with .unauthorized on wrong credentials, so it doubles as login check.
        let info = try await client.call(catalog, "DeviceInfo", action: "GetInfo")
        var box = BoxInfo(
            modelName: info["NewModelName"] ?? catalog.modelName ?? "FRITZ!Box",
            firmwareVersion: info["NewSoftwareVersion"]
        )

        // 2. Firmware update.
        // VERIFY: field name on current FRITZ!OS; TR-064 standard calls it NewUpgradeAvailable.
        if let ui = try? await client.call(catalog, "UserInterface", action: "GetInfo") {
            box.updateAvailable = ui["NewUpgradeAvailable"] == "1"
        }

        // 3. Internet line.
        var wan: WANStatus?
        do {
            let link = try await client.call(catalog, "WANCommonInterfaceConfig", action: "GetCommonLinkProperties")
            wan = WANStatus(
                isUp: link["NewPhysicalLinkStatus"]?.lowercased() == "up",
                maxDownstreamMbps: Self.mbps(fromBits: link["NewLayer1DownstreamMaxBitRate"]),
                maxUpstreamMbps: Self.mbps(fromBits: link["NewLayer1UpstreamMaxBitRate"])
            )
        } catch {
            warnings.append("Der Zustand der Internetleitung konnte nicht gelesen werden.")
        }

        // 4. Wi-Fi radios and who is associated with them.
        let (radios, wifiLinks, wlanSecurity, wifiWarning) = await readWLAN(catalog)
        if let wifiWarning { warnings.append(wifiWarning) }

        // 5. Host list.
        var devices: [Device] = []
        do {
            let hosts = try await readHosts(catalog)
            devices = hosts.map { makeDevice(from: $0, wifiLinks: wifiLinks) }
        } catch let error as TR064Error where error == .unauthorized {
            throw error
        } catch {
            warnings.append("Die Geräteliste konnte nicht gelesen werden.")
        }

        // 6. Security settings. Read-only and silent: what fails shows up as "nicht lesbar".
        let security = await readSecurity(catalog, wlans: wlanSecurity)

        return HouseholdSnapshot(takenAt: now, box: box, wan: wan, radios: radios, devices: devices,
                                 security: security, warnings: warnings)
    }

    /// Current up/down traffic on the internet line.
    public func readLiveThroughput() async throws -> LiveThroughput {
        let catalog = try await client.loadCatalog()
        // VERIFY: GetAddonInfos returns NewByteReceiveRate / NewByteSendRate in bytes per second.
        let values = try await client.call(catalog, "WANCommonInterfaceConfig", action: "GetAddonInfos")
        let down = Double(values["NewByteReceiveRate"] ?? "") ?? 0
        let up = Double(values["NewByteSendRate"] ?? "") ?? 0
        return LiveThroughput(downstreamMbps: down * 8 / 1_000_000, upstreamMbps: up * 8 / 1_000_000)
    }

    /// The box sends the magic packet itself, so the iPhone needs no broadcast rights.
    public func wakeUp(macAddress: String) async throws {
        let catalog = try await client.loadCatalog()
        _ = try await client.call(catalog, "Hosts", action: "X_AVM-DE_WakeOnLANByMACAddress",
                                  arguments: [("NewMACAddress", macAddress)])
    }

    /// A few small calls instead of the whole host list, so it can run every couple of seconds.
    // VERIFY: X_AVM-DE_GetSpecificHostEntryByIP and GetSpecificAssociatedDeviceInfo field names on FRITZ!OS 8.x.
    public func readWiFiLink(ip: String) async throws -> WiFiLink? {
        let catalog = try await client.loadCatalog()
        let host = try await client.call(catalog, "Hosts", action: "X_AVM-DE_GetSpecificHostEntryByIP",
                                         arguments: [("NewIPAddress", ip)])
        guard let mac = host["NewMACAddress"], !mac.isEmpty else { return nil }
        for entry in catalog.instances(of: "WLANConfiguration") {
            // A radio the device is not associated with answers with a fault; try the next one.
            guard let info = try? await client.call(entry.service, action: "GetSpecificAssociatedDeviceInfo",
                                                    arguments: [("NewAssociatedDeviceMACAddress", mac)]) else { continue }
            let radio = try? await client.call(entry.service, action: "GetInfo")
            let band = Self.band(instance: entry.instance, channel: Int(radio?["NewChannel"] ?? ""),
                                 frequencyField: radio?["NewX_AVM-DE_FrequencyBand"])
            return WiFiLink(band: band,
                            signalPercent: Int(info["NewX_AVM-DE_SignalStrength"] ?? ""),
                            rateMbps: Int(info["NewX_AVM-DE_Speed"] ?? ""))
        }
        return nil
    }

    // MARK: - Wi-Fi

    private func readWLAN(_ catalog: ServiceCatalog) async -> ([WLANRadio], [String: WiFiLink], [WLANSecurity], String?) {
        let instances = catalog.instances(of: "WLANConfiguration")
        guard !instances.isEmpty else { return ([], [:], [], "Die WLAN-Daten konnten nicht gelesen werden.") }

        var radios: [WLANRadio] = []
        var links: [String: WiFiLink] = [:]
        var security: [WLANSecurity] = []
        var failed = false
        var firstSSID: String?

        for (index, entry) in instances.enumerated() {
            guard let info = try? await client.call(entry.service, action: "GetInfo") else {
                failed = true
                continue
            }
            let channel = Int(info["NewChannel"] ?? "")
            let ssid = info["NewSSID"]
            if firstSSID == nil { firstSSID = ssid }
            let band = Self.band(instance: entry.instance, channel: channel, frequencyField: info["NewX_AVM-DE_FrequencyBand"])
            // VERIFY: the guest network is usually the last instance and has its own SSID.
            let isGuest = instances.count >= 3 && index == instances.count - 1 && ssid != firstSSID
            radios.append(WLANRadio(band: band, isEnabled: info["NewEnable"] == "1", channel: channel, ssid: ssid, isGuest: isGuest))
            // Only the encryption type; the Wi-Fi password (GetSecurityKeys) is never read.
            security.append(WLANSecurity(
                band: band, ssid: ssid, isGuest: isGuest, isEnabled: info["NewEnable"] == "1",
                encryption: WiFiEncryption.fromBeacon(info["NewBeaconType"], basicEncryption: info["NewBasicEncryptionModes"])
            ))

            for (mac, link) in await readAssociations(entry.service, band: band) {
                links[mac] = link
            }
        }
        return (radios, links, security, failed ? "Ein Teil der WLAN-Daten fehlt." : nil)
    }

    private func readAssociations(_ service: TR064Service, band: WiFiBand) async -> [String: WiFiLink] {
        var result: [String: WiFiLink] = [:]
        // Preferred: one list download.
        if let path = try? await client.call(service, action: "X_AVM-DE_GetWLANDeviceListPath")["NewX_AVM-DE_WLANDeviceListPath"],
           let items = try? await client.fetchList(path: path) {
            for item in items {
                guard let mac = item["AssociatedDeviceMACAddress"]?.uppercased(), !mac.isEmpty else { continue }
                result[mac] = WiFiLink(band: band,
                                       signalPercent: Int(item["X_AVM-DE_SignalStrength"] ?? ""),
                                       rateMbps: Int(item["X_AVM-DE_Speed"] ?? ""))
            }
            return result
        }
        // Fallback: one call per associated device.
        guard let total = try? await client.call(service, action: "GetTotalAssociations"),
              let count = Int(total["NewTotalAssociations"] ?? "") else { return result }
        for i in 0..<min(count, 200) {
            guard let item = try? await client.call(service, action: "GetGenericAssociatedDeviceInfo",
                                                    arguments: [("NewAssociatedDeviceIndex", String(i))]),
                  let mac = item["NewAssociatedDeviceMACAddress"]?.uppercased() else { continue }
            result[mac] = WiFiLink(band: band,
                                   signalPercent: Int(item["NewX_AVM-DE_SignalStrength"] ?? ""),
                                   rateMbps: Int(item["NewX_AVM-DE_Speed"] ?? ""))
        }
        return result
    }

    /// Works out the band of a radio. The FRITZ!Box does not always say it directly.
    static func band(instance: Int, channel: Int?, frequencyField: String?) -> WiFiBand {
        if let f = frequencyField {
            if f.hasPrefix("24") { return .ghz24 }
            if f.hasPrefix("5") { return .ghz5 }
            if f.hasPrefix("6") { return .ghz6 }
        }
        if let channel, channel > 14 { return .ghz5 }
        return instance == 2 ? .ghz5 : .ghz24
    }

    // MARK: - Hosts

    /// Host entries as dictionaries with list-style keys (MACAddress, IPAddress, HostName, Active, InterfaceType, …).
    private func readHosts(_ catalog: ServiceCatalog) async throws -> [[String: String]] {
        if let path = try? await client.call(catalog, "Hosts", action: "X_AVM-DE_GetHostListPath")["NewX_AVM-DE_HostListPath"],
           let items = try? await client.fetchList(path: path) {
            return items
        }
        let countResult = try await client.call(catalog, "Hosts", action: "GetHostNumberOfEntries")
        let count = Int(countResult["NewHostNumberOfEntries"] ?? "") ?? 0
        var items: [[String: String]] = []
        for i in 0..<min(count, 300) {
            let entry = try await client.call(catalog, "Hosts", action: "GetGenericHostEntry",
                                              arguments: [("NewIndex", String(i))])
            // Normalise to list-style keys by dropping the "New" prefix.
            var item: [String: String] = [:]
            for (key, value) in entry {
                item[key.hasPrefix("New") ? String(key.dropFirst(3)) : key] = value
            }
            items.append(item)
        }
        return items
    }

    func makeDevice(from host: [String: String], wifiLinks: [String: WiFiLink]) -> Device {
        let mac = host["MACAddress"]?.uppercased()
        let ip = host["IPAddress"]
        let name = host["HostName"].flatMap { $0.isEmpty ? nil : $0 } ?? ip ?? "Unbenanntes Gerät"
        let interface = host["InterfaceType"] ?? ""

        let connection: Connection
        if let mac, let link = wifiLinks[mac] {
            connection = .wifi(link)
        } else if interface.caseInsensitiveCompare("Ethernet") == .orderedSame {
            connection = .ethernet
        } else {
            connection = .unknown
        }

        var device = Device(
            id: Device.makeID(mac: mac, ip: ip),
            name: name,
            macAddress: mac,
            ipAddress: ip,
            isActive: host["Active"] == "1",
            isGuest: host["X_AVM-DE_Guest"] == "1",
            connection: connection
        )
        device.vendor = mac.flatMap { classifier.vendor(forMAC: $0) }
        device.kind = classifier.kind(for: device)
        device.category = device.kind.category
        return device
    }

    static func mbps(fromBits value: String?) -> Double? {
        guard let value, let bits = Double(value), bits > 0 else { return nil }
        return bits / 1_000_000
    }
}
