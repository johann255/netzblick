import XCTest
@testable import NetzblickKit

final class ICMPEchoTests: XCTestCase {
    func testRequestChecksumVerifies() {
        let packet = ICMPEcho.request(identifier: 0x1234, sequence: 7)
        XCTAssertEqual(packet[0], 8)
        XCTAssertEqual(ICMPEcho.checksum(packet), 0, "a packet with a correct checksum sums to zero")
    }

    func testChecksumOfKnownBytes() {
        // RFC 1071 example words 0001 f203 f4f5 f6f7 sum to ddf2, checksum 220d.
        XCTAssertEqual(ICMPEcho.checksum([0x00, 0x01, 0xF2, 0x03, 0xF4, 0xF5, 0xF6, 0xF7]), 0x220D)
    }

    func testReplyWithAndWithoutIPHeader() {
        let icmp: [UInt8] = [0, 0, 0, 0, 0x12, 0x34, 0x00, 0x05] + Array(repeating: 0, count: 8)
        XCTAssertEqual(ICMPEcho.replySequence(icmp), 5)
        let ipHeader: [UInt8] = [0x45] + Array(repeating: 0, count: 19)
        XCTAssertEqual(ICMPEcho.replySequence(ipHeader + icmp), 5)
        XCTAssertNil(ICMPEcho.replySequence(ICMPEcho.request(identifier: 1, sequence: 5)), "a request is not a reply")
        XCTAssertNil(ICMPEcho.replySequence([0x45, 0]), "too short")
    }

    func testPingLocalhost() async throws {
        let result = await Pinger(timeout: 1, count: 2).ping("127.0.0.1")
        guard result.isReachable else { throw XCTSkip("ICMP sockets are not available on this machine") }
        XCTAssertEqual(result.sent, 2)
        XCTAssertTrue(result.summary.hasPrefix("antwortet in"))
    }

    func testPingSummary() {
        XCTAssertEqual(PingResult(sent: 3, received: 0, averageMs: nil).summary, "antwortet nicht")
        XCTAssertEqual(PingResult(sent: 3, received: 3, averageMs: 4.4).summary, "antwortet in 4 ms")
        XCTAssertEqual(PingResult(sent: 3, received: 2, averageMs: 0.3).summary, "antwortet in unter 1 ms (1 von 3 verloren)")
    }
}

final class ServiceProbeTests: XCTestCase {
    func testClosedPortOnLocalhostIsNotOpen() async {
        // Port 1 (tcpmux) is closed on every CI machine.
        let open = await ServiceProbe(timeout: 1).isOpen(host: "127.0.0.1", port: 1)
        XCTAssertFalse(open)
    }

    func testServiceListIsUniqueAndFlagsCameras() {
        let ports = KnownService.common.map(\.port)
        XCTAssertEqual(Set(ports).count, ports.count)
        XCTAssertTrue(KnownService.common.contains { $0.port == 554 && $0.isCamera })
        XCTAssertTrue(KnownService.common.contains { $0.port == 23 && $0.isRisky })
    }
}

final class CameraClassificationTests: XCTestCase {
    let classifier = DeviceClassifier()

    func testCamerasGetTheirOwnCategory() {
        XCTAssertEqual(classifier.category(for: Device(id: "1", name: "Kamera Garten")), .camera)
        XCTAssertEqual(classifier.category(for: Device(id: "2", name: "Tapo-C200")), .camera)
        XCTAssertEqual(classifier.category(for: Device(id: "3", name: "unbekannt", vendor: "Hikvision")), .camera)
        XCTAssertEqual(classifier.category(for: Device(id: "4", name: "x", bonjourServices: ["_rtsp._tcp"])), .camera)
        XCTAssertEqual(classifier.category(for: Device(id: "5", name: "Türklingel")), .smartHome)
    }

    func testDemoHasACameraGroup() {
        XCTAssertTrue(DemoHousehold.snapshot().groupedDevices.contains { $0.category == .camera })
    }
}

final class WakeOnLANTests: XCTestCase {
    func testWakeUpCallsTheBox() async throws {
        let t = MockTransport.fullBox()
        t.soap("/upnp/control/hosts", "X_AVM-DE_WakeOnLANByMACAddress", [:])
        try await FritzBoxReader(client: TR064Client(transport: t)).wakeUp(macAddress: "AA:BB:CC:DD:EE:FF")
        let request = try XCTUnwrap(t.requests.last)
        XCTAssertEqual(request.headers["SOAPACTION"], "\"urn:dslforum-org:service:Hosts:1#X_AVM-DE_WakeOnLANByMACAddress\"")
        let body = String(decoding: request.body ?? Data(), as: UTF8.self)
        XCTAssertTrue(body.contains("<NewMACAddress>AA:BB:CC:DD:EE:FF</NewMACAddress>"))
    }
}

final class SignalWalkTests: XCTestCase {
    private func link(_ signal: Int, rate: Int = 400) -> WiFiLink { WiFiLink(band: .ghz5, signalPercent: signal, rateMbps: rate) }

    func testRepeaterGoesToGoodRoomNearTheWeakOne() {
        var walk = SignalWalk()
        walk.note("Wohnzimmer", link: link(85))
        XCTAssertNil(walk.verdict, "one place is not enough")
        walk.note("Flur", link: link(60))
        walk.note("Küche", link: link(70))
        walk.note("Bad", link: link(20))
        XCTAssertEqual(walk.boxRoom?.name, "Wohnzimmer")
        XCTAssertEqual(walk.weakRooms.map(\.name), ["Bad"])
        XCTAssertEqual(walk.repeaterRoom?.name, "Flur")
        XCTAssertTrue(walk.verdict?.hasPrefix("Stell den Repeater in den Raum „Flur“") ?? false)
    }

    func testRepeaterPrefersTheProblemFloor() {
        var walk = SignalWalk()
        walk.note("Wohnzimmer", link: link(90))
        walk.note("Küche", link: link(58))
        walk.note("Dachboden Büro", link: link(65))
        walk.note("Dachboden", link: link(15))
        XCTAssertEqual(walk.repeaterRoom?.name, "Dachboden Büro")
    }

    func testOtherFloorWithoutCandidateSuggestsCable() {
        var walk = SignalWalk()
        walk.note("Wohnzimmer", link: link(80))
        walk.note("Keller", link: link(10))
        XCTAssertNil(walk.repeaterRoom)
        XCTAssertTrue(walk.verdict?.contains("Powerline") ?? false)
    }

    func testSamplesAreAveragedPerRoom() {
        var walk = SignalWalk()
        walk.note("Küche", link: link(40, rate: 200))
        walk.note("küche", link: link(61, rate: 300))
        walk.note("  ", link: link(90))
        XCTAssertEqual(walk.spots.count, 2)
        XCTAssertEqual(walk.spots.first?.signalPercent, 51)
        XCTAssertEqual(walk.spots.first?.rateMbps, 250)
        XCTAssertEqual(walk.spots.last?.name, "Ort 2")
    }

    func testAllStrong() {
        var walk = SignalWalk()
        walk.note("A", link: link(80))
        walk.note("B", link: link(75))
        XCTAssertEqual(walk.verdict, "Überall starkes Signal. Ein Repeater bringt hier nichts.")
    }

    func testFloorsFromNamesAndOrder() {
        XCTAssertEqual(Floor.guess(for: "Keller"), .basement)
        XCTAssertEqual(Floor.guess(for: "Dachboden"), .attic)
        XCTAssertEqual(Floor.guess(for: "Bad OG"), .upper)
        XCTAssertEqual(Floor.guess(for: "Wohnzimmer"), .ground)
        XCTAssertEqual(Floor.guess(for: "Yoga-Raum"), .ground, "\"og\" inside a word is not a storey")
        var walk = SignalWalk()
        walk.note("Keller", link: link(30))
        walk.note("Dachboden", link: link(50))
        walk.note("Küche", link: link(70))
        XCTAssertEqual(walk.floors.map(\.floor), [.attic, .ground, .basement])
    }

    func testReaderFindsOwnLink() async throws {
        let t = MockTransport.fullBox()
        t.soap("/upnp/control/hosts", "X_AVM-DE_GetSpecificHostEntryByIP", ["NewMACAddress": "AA:BB:CC:00:00:01", "NewActive": "1"])
        t.soap("/upnp/control/wlanconfig2", "GetSpecificAssociatedDeviceInfo", [
            "NewAssociatedDeviceMACAddress": "AA:BB:CC:00:00:01",
            "NewX_AVM-DE_SignalStrength": "64", "NewX_AVM-DE_Speed": "780"
        ])
        let link = try await FritzBoxReader(client: TR064Client(transport: t)).readWiFiLink(ip: "192.168.178.30")
        XCTAssertEqual(link, WiFiLink(band: .ghz5, signalPercent: 64, rateMbps: 780))
    }
}
