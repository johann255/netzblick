import Foundation

// Read-only security settings of a FRITZ!Box. Nothing here changes the box.
extension FritzBoxReader {
    func readSecurity(_ catalog: ServiceCatalog, wlans: [WLANSecurity]) async -> SecurityStatus {
        SecurityStatus(
            wlans: wlans,
            portForwardings: await readPortForwardings(catalog),
            remoteAccess: await readRemoteAccess(catalog),
            wpsPinEnabled: await readWPSPin(catalog)
        )
    }

    /// Port forwardings from both WAN connection services; nil if neither answers.
    // VERIFY: whether GetGenericPortMappingEntry also lists forwardings set up by hand in the
    // FRITZ!Box UI or only those created via UPnP/TR-064, and which of the two services is active.
    func readPortForwardings(_ catalog: ServiceCatalog) async -> [PortForwarding]? {
        var result: [PortForwarding] = []
        var answered = false
        for serviceName in ["WANPPPConnection", "WANIPConnection"] {
            guard let count = try? await client.call(catalog, serviceName, action: "GetPortMappingNumberOfEntries"),
                  let total = Int(count["NewPortMappingNumberOfEntries"] ?? "") else { continue }
            answered = true
            for i in 0..<min(total, 100) {
                guard let entry = try? await client.call(catalog, serviceName, action: "GetGenericPortMappingEntry",
                                                         arguments: [("NewPortMappingIndex", String(i))]),
                      let forwarding = Self.portForwarding(from: entry) else { continue }
                if !result.contains(where: { $0.externalPort == forwarding.externalPort && $0.transport == forwarding.transport }) {
                    result.append(forwarding)
                }
            }
        }
        return answered ? result : nil
    }

    static func portForwarding(from entry: [String: String]) -> PortForwarding? {
        guard let external = Int(entry["NewExternalPort"] ?? ""),
              let client = entry["NewInternalClient"], !client.isEmpty else { return nil }
        let transport: PortForwarding.TransportProtocol = entry["NewProtocol"]?.uppercased() == "UDP" ? .udp : .tcp
        let note = entry["NewPortMappingDescription"].flatMap { $0.isEmpty ? nil : $0 }
        return PortForwarding(
            externalPort: external,
            internalPort: Int(entry["NewInternalPort"] ?? "") ?? external,
            transport: transport,
            internalClient: client,
            isEnabled: entry["NewEnabled"] != "0",
            note: note
        )
    }

    /// HTTPS access from the internet and MyFRITZ!; nil if neither service answers.
    func readRemoteAccess(_ catalog: ServiceCatalog) async -> RemoteAccess? {
        let remote = try? await client.call(catalog, "X_AVM-DE_RemoteAccess", action: "GetInfo")
        let myFritz = try? await client.call(catalog, "X_AVM-DE_MyFritz", action: "GetInfo")
        guard remote != nil || myFritz != nil else { return nil }
        return RemoteAccess(
            httpsEnabled: remote?["NewEnabled"] == "1",
            httpsPort: remote.flatMap { Int($0["NewPort"] ?? "") },
            myFritzEnabled: myFritz?["NewEnabled"] == "1"
        )
    }

    /// True if WPS runs in a PIN mode.
    // VERIFY: values of NewX_AVM-DE_WPSMode ("pbc", "pin_ap", "pin_client", "stop") and whether it
    // reflects the configured mode or only a running pairing.
    func readWPSPin(_ catalog: ServiceCatalog) async -> Bool? {
        guard let info = try? await client.call(catalog, "WLANConfiguration", action: "X_AVM-DE_GetWPSInfo"),
              let mode = info["NewX_AVM-DE_WPSMode"]?.lowercased() else { return nil }
        return mode.contains("pin")
    }
}
