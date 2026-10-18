import XCTest
@testable import NetzblickKit

final class ClassifierTests: XCTestCase {
    let classifier = DeviceClassifier()

    func testRandomizedMACDetection() {
        XCTAssertTrue(DeviceClassifier.isRandomized(mac: "DE:AD:BE:EF:00:01"))
        XCTAssertTrue(DeviceClassifier.isRandomized(mac: "02:4E:42:00:00:01"))
        XCTAssertFalse(DeviceClassifier.isRandomized(mac: "38:10:D5:00:00:01"))
        XCTAssertFalse(DeviceClassifier.isRandomized(mac: "00:0E:58:AA:BB:CC"))
    }

    func testVendorLookupIgnoresCaseAndSeparators() {
        XCTAssertEqual(classifier.vendor(forMAC: "38:10:d5:01:02:03"), "AVM")
        XCTAssertEqual(classifier.vendor(forMAC: "000e58aabbcc"), "Sonos")
        XCTAssertNil(classifier.vendor(forMAC: "00:11:22:33:44:55"))
    }

    func testCategoryPrefersNameThenServiceThenVendor() {
        XCTAssertEqual(classifier.category(for: Device(id: "1", name: "FRITZ!Repeater 3000")), .network)
        XCTAssertEqual(classifier.category(for: Device(id: "2", name: "Wohnzimmer", bonjourServices: ["_sonos._tcp"])), .entertainment)
        XCTAssertEqual(classifier.category(for: Device(id: "3", name: "unbekannt", vendor: "Espressif")), .smartHome)
        XCTAssertEqual(classifier.category(for: Device(id: "4", name: "PC-192-168-178-40")), .unknown)
        XCTAssertEqual(classifier.category(for: Device(id: "5", name: "Johanns-MacBook-Pro")), .computer)
    }
}

final class DiagnosisTests: XCTestCase {
    let engine = DiagnosisEngine()

    private func snapshot(devices: [Device], radios: [WLANRadio]? = nil, update: Bool = false, wanUp: Bool = true) -> HouseholdSnapshot {
        HouseholdSnapshot(
            box: BoxInfo(modelName: "FRITZ!Box", updateAvailable: update),
            wan: WANStatus(isUp: wanUp, maxDownstreamMbps: 100),
            radios: radios ?? [WLANRadio(band: .ghz24, isEnabled: true), WLANRadio(band: .ghz5, isEnabled: true)],
            devices: devices
        )
    }

    func testSlowBandFlagsTabletButNotSmartPlug() {
        let ipad = Device(id: "a", name: "iPad", connection: .wifi(WiFiLink(band: .ghz24, signalPercent: 25)), category: .phoneTablet)
        let plug = Device(id: "b", name: "Steckdose", connection: .wifi(WiFiLink(band: .ghz24, signalPercent: 35)), category: .smartHome)
        let findings = engine.findings(for: snapshot(devices: [ipad, plug]))
        XCTAssertEqual(findings.filter { $0.kind == .slowBand }.map(\.deviceIDs), [["a"]])
        XCTAssertTrue(findings.filter { $0.kind == .weakSignal }.isEmpty, "plug at 35 % is not weak, iPad already reported")
    }

    func testNoSlowBandWithoutFastRadio() {
        let ipad = Device(id: "a", name: "iPad", connection: .wifi(WiFiLink(band: .ghz24, signalPercent: 25)), category: .phoneTablet)
        let findings = engine.findings(for: snapshot(devices: [ipad], radios: [WLANRadio(band: .ghz24, isEnabled: true)]))
        XCTAssertTrue(findings.allSatisfy { $0.kind != .slowBand })
        XCTAssertEqual(findings.first?.kind, .weakSignal)
    }

    func testWeakRepeaterIsReportedOnItsOwn() {
        let rep = Device(id: "r", name: "FRITZ!Repeater Flur", connection: .wifi(WiFiLink(band: .ghz5, signalPercent: 20)), category: .network)
        let bell = Device(id: "k", name: "Türklingel", connection: .wifi(WiFiLink(band: .ghz24, signalPercent: 15)), category: .smartHome)
        let weak = engine.findings(for: snapshot(devices: [rep, bell])).filter { $0.kind == .weakSignal }
        XCTAssertEqual(weak.count, 1)
        XCTAssertEqual(weak.first?.deviceIDs, ["r"])
    }

    func testGuestsAndInactiveDevicesAreIgnored() {
        let guest = Device(id: "g", name: "Laptop", isGuest: true, connection: .wifi(WiFiLink(band: .ghz24, signalPercent: 10)), category: .computer)
        let asleep = Device(id: "s", name: "iPad", isActive: false, connection: .wifi(WiFiLink(band: .ghz24, signalPercent: 10)), category: .phoneTablet)
        XCTAssertTrue(engine.findings(for: snapshot(devices: [guest, asleep])).isEmpty)
    }

    func testOrderingPutsHighSeverityFirst() {
        let ipad = Device(id: "a", name: "iPad", connection: .wifi(WiFiLink(band: .ghz24, signalPercent: 25)), category: .phoneTablet)
        let findings = engine.findings(for: snapshot(devices: [ipad], update: true, wanUp: false))
        XCTAssertEqual(findings.first?.severity, .high)
        XCTAssertEqual(findings.last?.kind, .firmwareUpdate)
    }

    func testWifiBottleneckNeedsPhoneMeasurement() {
        let s = snapshot(devices: [])
        XCTAssertTrue(engine.findings(for: s).isEmpty)
        XCTAssertEqual(engine.findings(for: s, phoneSpeedMbps: 30).map(\.kind), [.wifiBottleneck])
        XCTAssertTrue(engine.findings(for: s, phoneSpeedMbps: 90).isEmpty)
    }

    func testNewDeviceDetector() {
        let s = snapshot(devices: [Device(id: "a", name: "A"), Device(id: "b", name: "B"), Device(id: "g", name: "G", isGuest: true)])
        let detector = NewDeviceDetector()
        XCTAssertEqual(detector.newDeviceIDs(in: s, known: []), [], "first run reports nothing")
        XCTAssertEqual(detector.newDeviceIDs(in: s, known: ["a"]), ["b"])
    }

    func testDemoHouseholdProducesTheMockupFindings() {
        let s = DemoHousehold.snapshot()
        XCTAssertEqual(s.devices.count, 31)
        XCTAssertEqual(s.activeDevices.count, 23)
        XCTAssertEqual(DemoHousehold.newDeviceIDs.count, 1)
        let kinds = Set(engine.findings(for: s).map(\.kind))
        XCTAssertTrue(kinds.contains(.slowBand))
        XCTAssertTrue(kinds.contains(.firmwareUpdate))
        XCTAssertEqual(Set(s.devices.map(\.id)).count, s.devices.count, "ids are unique")
    }
}

final class SpeedTests: XCTestCase {
    func testRatingAgainstTariff() {
        XCTAssertEqual(SpeedRating.rate(downloadMbps: 92, bookedMbps: 100).level, .fast)
        XCTAssertEqual(SpeedRating.rate(downloadMbps: 89, bookedMbps: 100).level, .ok)
        XCTAssertEqual(SpeedRating.rate(downloadMbps: 50, bookedMbps: 100).level, .ok)
        XCTAssertEqual(SpeedRating.rate(downloadMbps: 49, bookedMbps: 100).level, .slow)
    }

    func testRatingWithoutTariff() {
        XCTAssertEqual(SpeedRating.rate(downloadMbps: 14.9, bookedMbps: nil).level, .slow)
        XCTAssertEqual(SpeedRating.rate(downloadMbps: 15, bookedMbps: nil).level, .ok)
        XCTAssertEqual(SpeedRating.rate(downloadMbps: 50, bookedMbps: nil).level, .fast)
        XCTAssertEqual(SpeedRating.rate(downloadMbps: 30, bookedMbps: 0).level, .ok, "zero tariff falls back to absolute")
    }

    func testThroughputMeterIgnoresWarmUp() {
        var meter = ThroughputMeter(warmUp: 1, window: 0.5)
        // Slow first second, then a steady 12.5 MB/s (= 100 Mbit/s).
        _ = meter.record(t: 0.5, totalBytes: 100_000)
        _ = meter.record(t: 1.0, totalBytes: 200_000)
        var total: Int64 = 200_000
        var t = 1.0
        var last = 0.0
        while t < 5 {
            t += 0.5
            total += 6_250_000
            last = meter.record(t: t, totalBytes: total)
        }
        XCTAssertEqual(last, 100, accuracy: 0.5)
        XCTAssertEqual(meter.resultMbps, 100, accuracy: 0.5)
    }

    func testBottleneckVerdict() {
        XCTAssertEqual(BottleneckVerdict.judge(phoneMbps: 30, lineMaxMbps: 100), .wifiIsLimit(lineMbps: 100, phoneMbps: 30))
        XCTAssertEqual(BottleneckVerdict.judge(phoneMbps: 80, lineMaxMbps: 100), .lineIsLimit)
        XCTAssertEqual(BottleneckVerdict.judge(phoneMbps: 80, lineMaxMbps: nil), .unknown)
    }
}

final class WidgetSummaryTests: XCTestCase {
    func testRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("summary.json")
        let store = WidgetSummaryStore(fileURL: url)
        XCTAssertNil(store.load())
        try store.save(.placeholder)
        XCTAssertEqual(store.load()?.devicesOnline, 23)
        XCTAssertEqual(store.load()?.lastSpeedLevel, .fast)
    }
}
