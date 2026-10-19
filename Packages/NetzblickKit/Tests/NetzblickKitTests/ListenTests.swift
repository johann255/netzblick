import XCTest
@testable import NetzblickKit

final class ListenTests: XCTestCase {

    // MARK: Helpers

    /// Ethernet + IPv4 + UDP + DNS query for `name`, as the capture delivers it.
    static func dnsFrame(mac: [UInt8], ip: [UInt8], name: String, port: UInt16 = 53, response: Bool = false) -> Data {
        var dns: [UInt8] = [0x12, 0x34, response ? 0x81 : 0x01, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0]
        for label in name.split(separator: ".") {
            dns.append(UInt8(label.utf8.count))
            dns.append(contentsOf: label.utf8)
        }
        dns.append(contentsOf: [0, 0x00, 0x01, 0x00, 0x01])
        let udpLength = 8 + dns.count
        var udp: [UInt8] = [0xC3, 0x50, UInt8(port >> 8), UInt8(port & 0xFF), UInt8(udpLength >> 8), UInt8(udpLength & 0xFF), 0, 0]
        udp += dns
        let ipLength = 20 + udp.count
        var ipv4: [UInt8] = [0x45, 0, UInt8(ipLength >> 8), UInt8(ipLength & 0xFF), 0, 0, 0, 0, 64, 17, 0, 0]
        ipv4 += ip + [192, 168, 178, 1]
        var frame: [UInt8] = [0x2C, 0x91, 0xAB, 0, 0, 1] + mac + [0x08, 0x00]
        frame += ipv4 + udp
        return Data(frame)
    }

    static func pcap(_ frames: [Data]) -> Data {
        func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24)] }
        var out: [UInt8] = [0xD4, 0xC3, 0xB2, 0xA1, 2, 0, 4, 0] + le32(0) + le32(0) + le32(65535) + le32(1)
        for (i, frame) in frames.enumerated() {
            out += le32(1_760_000_000 + UInt32(i)) + le32(0) + le32(UInt32(frame.count)) + le32(UInt32(frame.count))
            out += frame
        }
        return Data(out)
    }

    static let phoneMAC: [UInt8] = [0x02, 0x4E, 0x42, 0x00, 0x00, 0x09]

    // MARK: pcap + DNS

    func testReadsFramesAcrossChunkBoundaries() throws {
        let data = Self.pcap([
            Self.dnsFrame(mac: Self.phoneMAC, ip: [192, 168, 178, 28], name: "graph.facebook.com"),
            Self.dnsFrame(mac: Self.phoneMAC, ip: [192, 168, 178, 28], name: "spiegel.de")
        ])
        var reader = PcapReader()
        var frames: [CapturedFrame] = []
        // Feed in awkward pieces, as the network delivers them.
        var index = 0
        for size in [10, 20, 7, 50, 1000] where index < data.count {
            let end = min(index + size, data.count)
            frames += try reader.feed(data[index..<end])
            index = end
        }
        XCTAssertEqual(frames.count, 2)
        let queries = frames.compactMap(DNSQuery.parse)
        XCTAssertEqual(queries.map(\.name), ["graph.facebook.com", "spiegel.de"])
        XCTAssertEqual(queries.first?.sourceMAC, "02:4E:42:00:00:09")
        XCTAssertEqual(queries.first?.sourceIP, "192.168.178.28")
        XCTAssertEqual(queries.first?.type, 1)
    }

    func testIgnoresResponsesAndOtherPorts() {
        let response = CapturedFrame(linkType: 1, timestamp: Date(), data: Self.dnsFrame(mac: Self.phoneMAC, ip: [1, 1, 1, 1], name: "a.de", response: true))
        let https = CapturedFrame(linkType: 1, timestamp: Date(), data: Self.dnsFrame(mac: Self.phoneMAC, ip: [1, 1, 1, 1], name: "a.de", port: 443))
        XCTAssertNil(DNSQuery.parse(response))
        XCTAssertNil(DNSQuery.parse(https))
    }

    func testRejectsHTMLWithHexHead() {
        var reader = PcapReader()
        XCTAssertThrowsError(try reader.feed(Data("<!DOCTYPE html><html><body>Anmeldung</body></html>".utf8))) {
            guard case let PcapReader.ReadError.unknownFormat(head) = $0 else { return XCTFail() }
            XCTAssertTrue(head.hasPrefix("3C 21 44 4F"))
        }
    }

    func testReadsPcapNG() throws {
        func le32(_ v: UInt32) -> [UInt8] { [UInt8(v & 0xFF), UInt8(v >> 8 & 0xFF), UInt8(v >> 16 & 0xFF), UInt8(v >> 24)] }
        func block(_ type: UInt32, _ body: [UInt8]) -> [UInt8] {
            var body = body
            while body.count % 4 != 0 { body.append(0) }
            let length = UInt32(12 + body.count)
            return le32(type) + le32(length) + body + le32(length)
        }
        let frame = [UInt8](Self.dnsFrame(mac: Self.phoneMAC, ip: [192, 168, 178, 28], name: "app-measurement.com"))
        let shb = block(0x0A0D0D0A, [0x4D, 0x3C, 0x2B, 0x1A, 1, 0, 0, 0] + Array(repeating: 0xFF, count: 8))
        let idb = block(1, [1, 0, 0, 0] + le32(65535))
        let epb = block(6, le32(0) + le32(0) + le32(1_000_000) + le32(UInt32(frame.count)) + le32(UInt32(frame.count)) + frame)
        let data = Data(shb + idb + epb)
        var reader = PcapReader()
        var frames: [CapturedFrame] = []
        frames += try reader.feed(data.prefix(30))
        frames += try reader.feed(data.dropFirst(30))
        XCTAssertEqual(frames.compactMap(DNSQuery.parse).map(\.name), ["app-measurement.com"])
    }

    // MARK: Domain groups

    func testGroupsByLongestSuffix() {
        let groups = DomainGroups.bundled
        XCTAssertEqual(groups.match("googleads.g.doubleclick.net").group, .tracking)
        XCTAssertEqual(groups.match("googleads.g.doubleclick.net").owner, "Google")
        XCTAssertEqual(groups.match("a1.tuyaeu.com").group, .vendor)
        XCTAssertEqual(groups.match("www.spiegel.de"), DomainMatch(domain: "spiegel.de", group: .normal, owner: nil))
        XCTAssertEqual(groups.match("news.bbc.co.uk").domain, "bbc.co.uk")
        XCTAssertTrue(groups.isLocal("fritz.box"))
        XCTAssertTrue(groups.isLocal("1.178.168.192.in-addr.arpa"))
        XCTAssertTrue(groups.isLocal("drucker"))
        XCTAssertFalse(groups.isLocal("posteo.de"))
    }

    // MARK: Report

    func testRecorderCountsPerDeviceAndSkipsGuests() {
        let snapshot = DemoHousehold.snapshot()
        var recorder = ListenRecorder(devices: snapshot.devices)
        let phone = "02:4E:42:00:00:09"
        let guest = "02:4E:42:00:00:1F"
        for name in ["graph.facebook.com", "graph.facebook.com", "spiegel.de", "gateway.icloud.com", "fritz.box"] {
            recorder.record(DNSQuery(sourceMAC: phone, sourceIP: "192.168.178.28", name: name, type: 1, timestamp: Date()))
        }
        recorder.record(DNSQuery(sourceMAC: guest, sourceIP: "192.168.178.50", name: "doubleclick.net", type: 1, timestamp: Date()))
        recorder.record(DNSQuery(sourceMAC: nil, sourceIP: "192.168.178.99", name: "example.org", type: 1, timestamp: Date()))

        let report = recorder.report()
        XCTAssertEqual(report.total, 5)
        XCTAssertEqual(report.devices.first?.deviceID, phone)
        XCTAssertEqual(report.devices.first?.domains.first?.match.domain, "graph.facebook.com")
        XCTAssertEqual(report.devices.first?.domains.first?.count, 2)
        XCTAssertEqual(report.device(phone)?.share(.tracking), 0.5)
        XCTAssertNil(report.device(guest))
        XCTAssertNotNil(report.device("ip:192.168.178.99"))
        XCTAssertEqual(report.share(.tracking), 0.4, accuracy: 0.0001)
    }

    // MARK: Web login

    func testPBKDF2ResponseMatchesAVMExample() throws {
        // Example from AVM's technical note on login_sid.lua (version 2).
        let answer = try FritzWebSession.response(challenge: "2$10000$5A1711$2000$5A1722", password: "1example!")
        XCTAssertEqual(answer, "5A1722$1798a1672bca7c6463d6b245f82b53703b0f50813401b03e4045a5861e689adb")
    }

    func testLegacyMD5ResponseMatchesAVMExample() throws {
        let answer = try FritzWebSession.response(challenge: "1234567z", password: "äbc")
        XCTAssertEqual(answer, "1234567z-9e224a41eeefa284df7bb0f26c2913e2")
    }

    func testParsesSessionInfoFromRealBox() {
        // Answer of a FRITZ!Box 7590 AX (FRITZ!OS 8.25) before login.
        let before = FritzWebSession.parseSessionInfo(#"<?xml version="1.0" encoding="utf-8"?><SessionInfo><SID>0000000000000000</SID><Challenge>2$60000$c2f44f0434e18c49da4f4381ffe48a82$6000$fe35abe74c25003db5092e514b6499d1</Challenge><BlockTime>0</BlockTime><Rights></Rights><Users><User last="1">fritz2690</User></Users></SessionInfo>"#)
        XCTAssertEqual(before.sid, FritzWebSession.invalidSID)
        XCTAssertEqual(before.challenge?.hasPrefix("2$60000$"), true)
        XCTAssertTrue(before.rights.isEmpty)

        let after = FritzWebSession.parseSessionInfo("<SessionInfo><SID>9a1b2c3d4e5f6071</SID><Challenge>x</Challenge><BlockTime>0</BlockTime><Rights><Name>Dial</Name><Access>2</Access><Name>App</Name><Access>2</Access><Name>BoxAdmin</Name><Access>2</Access></Rights></SessionInfo>")
        XCTAssertEqual(after.sid, "9a1b2c3d4e5f6071")
        XCTAssertEqual(after.rights["BoxAdmin"], 2)
        XCTAssertEqual(after.rights["Dial"], 2)
    }

    func testLoginSendsResponseAndReadsRight() async throws {
        let transport = MockTransport()
        transport.routes["/login_sid.lua"] = HTTPResponse(statusCode: 200, body: Data("<SessionInfo><SID>0000000000000000</SID><Challenge>2$10000$5A1711$2000$5A1722</Challenge><BlockTime>0</BlockTime><Rights></Rights></SessionInfo>".utf8))
        let session = FritzWebSession(baseURL: URL(string: "http://192.168.178.1")!, transport: transport)
        // The mock returns the challenge again for the POST, i.e. a refused login.
        do {
            _ = try await session.login(username: "fritz2690", password: "1example!")
            XCTFail("expected refusal")
        } catch {
            XCTAssertEqual(error as? ListenError, .loginFailed(blockSeconds: 0))
        }
        let post = transport.requests.last
        XCTAssertEqual(post?.method, "POST")
        XCTAssertEqual(post.flatMap { $0.body }.map { String(decoding: $0, as: UTF8.self) },
                       "username=fritz2690&response=5A1722$1798a1672bca7c6463d6b245f82b53703b0f50813401b03e4045a5861e689adb")
    }

    // MARK: Demo

    func testDemoListenerMapsToDemoDevices() async throws {
        let snapshot = DemoHousehold.snapshot()
        var recorder = ListenRecorder(devices: snapshot.devices)
        var heard = 0
        for try await query in DemoDNSListener(rate: 1000).queries() {
            recorder.record(query)
            heard += 1
            if heard == 50 { break }
        }
        let report = recorder.report()
        XCTAssertEqual(report.total, 50)
        XCTAssertTrue(report.devices.allSatisfy { !$0.deviceID.hasPrefix("ip:") })
    }
}
