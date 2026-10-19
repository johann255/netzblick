import XCTest
@testable import NetzblickKit

final class SecurityTests: XCTestCase {
    let engine = DiagnosisEngine()

    func testBeaconTypeMapping() {
        XCTAssertEqual(WiFiEncryption.fromBeacon("11i"), .wpa2)
        XCTAssertEqual(WiFiEncryption.fromBeacon("11iandWPA3"), .wpa2wpa3)
        XCTAssertEqual(WiFiEncryption.fromBeacon("WPA3"), .wpa3)
        XCTAssertEqual(WiFiEncryption.fromBeacon("WPAand11i"), .wpaLegacy)
        XCTAssertEqual(WiFiEncryption.fromBeacon("None"), .open)
        XCTAssertEqual(WiFiEncryption.fromBeacon("Basic", basicEncryption: "WEPEncryption"), .wep)
        XCTAssertEqual(WiFiEncryption.fromBeacon("Basic", basicEncryption: "None"), .open)
        XCTAssertEqual(WiFiEncryption.fromBeacon(nil), .unknown)
        XCTAssertEqual(WiFiEncryption.fromBeacon("Quantum"), .unknown)
    }

    func testReaderReadsSecuritySettings() async throws {
        let t = MockTransport.fullBox()
        t.soap("/upnp/control/wlanconfig1", "GetInfo", ["NewEnable": "1", "NewChannel": "6", "NewSSID": "Zuhause", "NewBeaconType": "11iandWPA3"])
        t.soap("/upnp/control/wlanconfig2", "GetInfo", ["NewEnable": "1", "NewChannel": "36", "NewSSID": "Zuhause", "NewBeaconType": "WPAand11i"])
        t.soap("/upnp/control/wlanconfig1", "X_AVM-DE_GetWPSInfo", ["NewX_AVM-DE_WPSMode": "pbc", "NewX_AVM-DE_WPSStatus": "off"])
        t.soap("/upnp/control/wanpppconn1", "GetPortMappingNumberOfEntries", ["NewPortMappingNumberOfEntries": "2"])
        t.soap("/upnp/control/wanpppconn1", "GetGenericPortMappingEntry", [
            "NewRemoteHost": "", "NewExternalPort": "443", "NewProtocol": "TCP", "NewInternalPort": "443",
            "NewInternalClient": "192.168.178.20", "NewEnabled": "1", "NewPortMappingDescription": "NAS", "NewLeaseDuration": "0"
        ])
        t.soap("/upnp/control/x_remote", "GetInfo", ["NewEnabled": "1", "NewPort": "44321", "NewUsername": ""])
        t.soap("/upnp/control/x_myfritz", "GetInfo", ["NewEnabled": "0"])

        let s = try await FritzBoxReader(client: TR064Client(transport: t)).readSnapshot()
        let security = try XCTUnwrap(s.security)
        XCTAssertEqual(security.wlans.map(\.encryption), [.wpa2wpa3, .wpaLegacy])
        XCTAssertEqual(security.wpsPinEnabled, false)
        // The mock answers every index with the same entry; duplicates are dropped.
        XCTAssertEqual(security.portForwardings?.count, 1)
        XCTAssertEqual(security.portForwardings?.first?.note, "NAS")
        XCTAssertEqual(security.remoteAccess, RemoteAccess(httpsEnabled: true, httpsPort: 44321, myFritzEnabled: false))
        XCTAssertEqual(s.warnings, [], "security reading never adds warnings")

        let ids = t.requests.compactMap { $0.headers["SOAPACTION"] }
        XCTAssertFalse(ids.contains { $0.contains("GetSecurityKeys") }, "never reads the Wi-Fi password")
    }

    func testMissingServicesStayUnknown() async throws {
        let s = try await FritzBoxReader(client: TR064Client(transport: MockTransport.fullBox())).readSnapshot()
        let security = try XCTUnwrap(s.security)
        XCTAssertNil(security.portForwardings)
        XCTAssertNil(security.wpsPinEnabled)
        let items = SecurityCheck.items(for: s)
        XCTAssertEqual(items.first { $0.id == "ports" }?.state, .unknown)
        XCTAssertNil(items.first { $0.id == "wps" }, "unreported WPS gets no line")
    }

    private func snapshot(_ security: SecurityStatus, devices: [Device] = []) -> HouseholdSnapshot {
        HouseholdSnapshot(box: BoxInfo(modelName: "FRITZ!Box"), devices: devices, security: security)
    }

    func testOpenHomeWiFiIsHighButOpenGuestIsIgnored() {
        let open = snapshot(SecurityStatus(wlans: [WLANSecurity(band: .ghz24, ssid: "Zuhause", encryption: .open)]))
        XCTAssertEqual(engine.wifiEncryption(open).first?.severity, .high)

        let guest = snapshot(SecurityStatus(wlans: [
            WLANSecurity(band: .ghz5, ssid: "Zuhause", encryption: .wpa2wpa3),
            WLANSecurity(band: .ghz24, ssid: "Gast", isGuest: true, encryption: .open)
        ]))
        XCTAssertTrue(engine.wifiEncryption(guest).isEmpty)
    }

    func testPortForwardingNamesTheDevice() {
        let nas = Device(id: "NAS", name: "NAS Keller", ipAddress: "192.168.178.37")
        let s = snapshot(SecurityStatus(portForwardings: [
            PortForwarding(externalPort: 5001, internalPort: 5001, transport: .tcp, internalClient: "192.168.178.37"),
            PortForwarding(externalPort: 8080, internalPort: 80, transport: .tcp, internalClient: "192.168.178.37", isEnabled: false)
        ]), devices: [nas])
        let finding = try? XCTUnwrap(engine.portForwardings(s).first)
        XCTAssertEqual(finding?.title, "NAS Keller ist aus dem Internet erreichbar")
        XCTAssertEqual(finding?.deviceIDs, ["NAS"])
        XCTAssertTrue(finding?.explanation.contains("5001/TCP") ?? false)
        XCTAssertFalse(finding?.explanation.contains("8080") ?? true, "disabled forwardings are ignored")
    }

    func testRemoteAccessOnlyForHTTPS() {
        let myFritzOnly = snapshot(SecurityStatus(remoteAccess: RemoteAccess(httpsEnabled: false, myFritzEnabled: true)))
        XCTAssertTrue(engine.remoteAccess(myFritzOnly).isEmpty)
        let https = snapshot(SecurityStatus(remoteAccess: RemoteAccess(httpsEnabled: true, httpsPort: 443)))
        XCTAssertEqual(engine.remoteAccess(https).first?.severity, .info)
    }

    func testChecklistForDemo() {
        let s = DemoHousehold.snapshot()
        let items = SecurityCheck.items(for: s, newDeviceCount: DemoHousehold.newDeviceIDs.count)
        let states = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0.state) })
        XCTAssertEqual(states["wifi"], .ok)
        XCTAssertEqual(states["ports"], .warn)
        XCTAssertEqual(states["remote"], .ok)
        XCTAssertEqual(states["firmware"], .warn)
        XCTAssertEqual(states["new-devices"], .warn)
        XCTAssertTrue(engine.findings(for: s).contains { $0.kind == .portForwarding })
    }

    func testSecurityKinds() {
        XCTAssertTrue(FindingKind.portForwarding.isSecurity)
        XCTAssertTrue(FindingKind.firmwareUpdate.isSecurity)
        XCTAssertFalse(FindingKind.slowBand.isSecurity)
    }
}
