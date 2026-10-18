import XCTest
@testable import NetzblickKit

final class TR064Tests: XCTestCase {
    func testEnvelopeContainsActionAndEscapedArguments() {
        let body = String(decoding: SOAPEnvelope.body(serviceType: "urn:dslforum-org:service:Hosts:1",
                                                      action: "GetGenericHostEntry",
                                                      arguments: [("NewIndex", "<1>")]), as: UTF8.self)
        XCTAssertTrue(body.contains("<u:GetGenericHostEntry xmlns:u=\"urn:dslforum-org:service:Hosts:1\">"))
        XCTAssertTrue(body.contains("<NewIndex>&lt;1&gt;</NewIndex>"))
        XCTAssertEqual(SOAPEnvelope.soapActionHeader(serviceType: "urn:x:1", action: "A"), "\"urn:x:1#A\"")
    }

    func testCatalogParsesNestedServicesAndModel() throws {
        let catalog = try ServiceCatalog.parse(Fixture.data("tr64desc.xml"))
        XCTAssertEqual(catalog.modelName, "FRITZ!Box 7590 AX")
        XCTAssertEqual(catalog.service("Hosts")?.controlURL, "/upnp/control/hosts")
        XCTAssertEqual(catalog.instances(of: "WLANConfiguration").map(\.instance), [1, 2])
        XCTAssertNotNil(catalog.service("WANCommonInterfaceConfig"))
        XCTAssertNil(catalog.service("Hosts", instance: 2))
    }

    func testFault606MapsToUnauthorized() async {
        let t = MockTransport()
        t.routes["/upnp/control/hosts#GetHostNumberOfEntries"] = HTTPResponse(statusCode: 500, body: Fixture.data("fault-606.xml"))
        let client = TR064Client(transport: t)
        let service = TR064Service(serviceType: "urn:dslforum-org:service:Hosts:1", controlURL: "/upnp/control/hosts")
        do {
            _ = try await client.call(service, action: "GetHostNumberOfEntries")
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? TR064Error, .unauthorized)
        }
    }

    func testHTTP401MapsToUnauthorized() async {
        let t = MockTransport()
        t.routes["/upnp/control/deviceinfo#GetInfo"] = HTTPResponse(statusCode: 401, body: Data())
        let client = TR064Client(transport: t)
        let service = TR064Service(serviceType: "urn:dslforum-org:service:DeviceInfo:1", controlURL: "/upnp/control/deviceinfo")
        do {
            _ = try await client.call(service, action: "GetInfo")
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? TR064Error, .unauthorized)
        }
    }

    func testResolveHandlesRelativeAndAbsolutePaths() {
        let client = TR064Client(baseURL: URL(string: "http://192.168.178.1:49000")!, transport: MockTransport())
        XCTAssertEqual(client.resolve("/devicehostlist.lua?sid=1").absoluteString, "http://192.168.178.1:49000/devicehostlist.lua?sid=1")
        XCTAssertEqual(client.resolve("http://fritz.box:49000/x.lua").absoluteString, "http://fritz.box:49000/x.lua")
    }

    func testItemListParser() throws {
        let items = try ItemListParser.parse(Fixture.data("hostlist.xml"))
        XCTAssertEqual(items.count, 5)
        XCTAssertEqual(items[0]["HostName"], "iPad-Wohnzimmer")
        XCTAssertEqual(items[3]["X_AVM-DE_Guest"], "1")
        XCTAssertEqual(items[4]["HostName"], "")
    }

    func testReaderBuildsSnapshot() async throws {
        let reader = FritzBoxReader(client: TR064Client(transport: MockTransport.fullBox()))
        let s = try await reader.readSnapshot()

        XCTAssertEqual(s.box.modelName, "FRITZ!Box 7590 AX")
        XCTAssertEqual(s.box.firmwareVersion, "8.03")
        XCTAssertTrue(s.box.updateAvailable)
        XCTAssertEqual(s.wan?.isUp, true)
        XCTAssertEqual(s.wan?.maxDownstreamMbps ?? 0, 116, accuracy: 0.01)
        XCTAssertEqual(s.radios.map(\.band), [.ghz24, .ghz5])
        XCTAssertEqual(s.warnings, [])
        XCTAssertEqual(s.devices.count, 5)

        let ipad = try XCTUnwrap(s.devices.first { $0.name == "iPad-Wohnzimmer" })
        XCTAssertEqual(ipad.wifi, WiFiLink(band: .ghz24, signalPercent: 25, rateMbps: 58))
        XCTAssertEqual(ipad.category, .phoneTablet)
        XCTAssertNil(ipad.vendor, "randomised MAC carries no vendor")

        let sonos = try XCTUnwrap(s.devices.first { $0.name == "Sonos-Kueche" })
        XCTAssertEqual(sonos.wifi?.band, .ghz5)
        XCTAssertEqual(sonos.vendor, "Sonos")
        XCTAssertEqual(sonos.category, .entertainment)

        let tv = try XCTUnwrap(s.devices.first { $0.name == "Samsung-TV" })
        XCTAssertEqual(tv.connection, .ethernet)
        XCTAssertEqual(tv.category, .entertainment)

        let unnamed = try XCTUnwrap(s.devices.first { $0.ipAddress == "192.168.178.23" })
        XCTAssertEqual(unnamed.name, "192.168.178.23")
        XCTAssertEqual(unnamed.vendor, "Espressif")
        XCTAssertEqual(unnamed.category, .smartHome)
        XCTAssertEqual(unnamed.wifi?.signalPercent, 55, "lower-case MAC in WLAN list must still match")

        XCTAssertEqual(s.guestDevices.map(\.name), ["Gast-Laptop"])
    }

    func testReaderSurvivesMissingParts() async throws {
        let t = MockTransport.fullBox()
        t.routes["/upnp/control/wancommonifconfig1#GetCommonLinkProperties"] = nil
        t.routes["/upnp/control/hosts#X_AVM-DE_GetHostListPath"] = nil
        let s = try await FritzBoxReader(client: TR064Client(transport: t)).readSnapshot()
        XCTAssertNil(s.wan)
        XCTAssertTrue(s.devices.isEmpty)
        XCTAssertEqual(s.warnings.count, 2)
    }

    func testReaderPropagatesWrongPassword() async {
        let t = MockTransport.fullBox()
        t.routes["/upnp/control/deviceinfo#GetInfo"] = HTTPResponse(statusCode: 401, body: Data())
        do {
            _ = try await FritzBoxReader(client: TR064Client(transport: t)).readSnapshot()
            XCTFail("expected error")
        } catch {
            XCTAssertEqual(error as? TR064Error, .unauthorized)
        }
    }

    func testLiveThroughputConvertsBytesToMbps() async throws {
        let live = try await FritzBoxReader(client: TR064Client(transport: MockTransport.fullBox())).readLiveThroughput()
        XCTAssertEqual(live.downstreamMbps, 10, accuracy: 0.001)
        XCTAssertEqual(live.upstreamMbps, 1, accuracy: 0.001)
    }

    func testBandHeuristics() {
        XCTAssertEqual(FritzBoxReader.band(instance: 1, channel: 6, frequencyField: nil), .ghz24)
        XCTAssertEqual(FritzBoxReader.band(instance: 1, channel: 100, frequencyField: nil), .ghz5)
        XCTAssertEqual(FritzBoxReader.band(instance: 3, channel: 5, frequencyField: "6000"), .ghz6)
        XCTAssertEqual(FritzBoxReader.band(instance: 2, channel: nil, frequencyField: nil), .ghz5)
    }
}
