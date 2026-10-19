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
