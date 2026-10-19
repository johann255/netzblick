import XCTest
@testable import NetzblickKit

final class PresenceLogTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func reading(_ at: Date, _ devices: [Device]) -> HouseholdSnapshot {
        HouseholdSnapshot(takenAt: at, box: BoxInfo(modelName: "FRITZ!Box"), devices: devices)
    }

    private func device(_ id: String, active: Bool, guest: Bool = false) -> Device {
        Device(id: id, name: id, isActive: active, isGuest: guest)
    }

    func testFirstReadingIsBaselineWithoutEvents() {
        var log = PresenceLog()
        let events = log.record(reading(t0, [device("a", active: true), device("b", active: false)]))
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(log.lastSeen["a"], t0)
        XCTAssertNil(log.lastSeen["b"])
    }

    func testOnlineOfflineAndJoined() {
        var log = PresenceLog()
        log.record(reading(t0, [device("a", active: true), device("b", active: false)]))
        let t1 = t0.addingTimeInterval(600)
        let events = log.record(reading(t1, [device("a", active: false), device("b", active: true), device("c", active: true)]))
        XCTAssertEqual(Set(events.map { "\($0.deviceID):\($0.kind.rawValue)" }), ["a:offline", "b:online", "c:joined"])
        XCTAssertEqual(log.lastSeen["a"], t0)
        XCTAssertEqual(log.lastSeen["b"], t1)
        XCTAssertEqual(log.events(for: "b").first?.kind, .online)
    }

    func testUnchangedStateProducesNothing() {
        var log = PresenceLog()
        log.record(reading(t0, [device("a", active: true)]))
        XCTAssertTrue(log.record(reading(t0.addingTimeInterval(60), [device("a", active: true)])).isEmpty)
    }

    func testDisappearedDeviceGoesOffline() {
        var log = PresenceLog()
        log.record(reading(t0, [device("a", active: true)]))
        let events = log.record(reading(t0.addingTimeInterval(60), []))
        XCTAssertEqual(events.map(\.kind), [.offline])
    }

    func testGuestsAreNeverRecorded() {
        var log = PresenceLog()
        log.record(reading(t0, []))
        let events = log.record(reading(t0.addingTimeInterval(60), [device("g", active: true, guest: true)]))
        XCTAssertTrue(events.isEmpty)
        XCTAssertNil(log.lastSeen["g"])
    }

    func testOldEventsArePruned() {
        var log = PresenceLog()
        log.record(reading(t0, [device("a", active: true)]))
        log.record(reading(t0.addingTimeInterval(60), [device("a", active: false)]))
        XCTAssertEqual(log.events.count, 1)
        log.record(reading(t0.addingTimeInterval(PresenceLog.retention + 120), [device("a", active: false)]))
        XCTAssertTrue(log.events.isEmpty)
    }

    func testForgetRemovesDevice() {
        var log = PresenceLog()
        log.record(reading(t0, [device("a", active: true)]))
        log.record(reading(t0.addingTimeInterval(60), [device("a", active: false)]))
        log.forget(deviceID: "a")
        XCTAssertTrue(log.events(for: "a").isEmpty)
        XCTAssertNil(log.lastSeen["a"])
    }

    func testOnlineHours() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let start = calendar.date(from: DateComponents(year: 2027, month: 1, day: 4, hour: 8, minute: 10))!
        let end = calendar.date(from: DateComponents(year: 2027, month: 1, day: 4, hour: 10, minute: 30))!
        var log = PresenceLog()
        log.record(reading(start.addingTimeInterval(-60), [device("a", active: false)]))
        log.record(reading(start, [device("a", active: true)]))
        log.record(reading(end, [device("a", active: false)]))
        XCTAssertEqual(log.onlineHours(for: "a"), [8, 9, 10])
    }

    func testCodableRoundTrip() throws {
        var log = PresenceLog()
        log.record(reading(t0, [device("a", active: true)]))
        log.record(reading(t0.addingTimeInterval(60), [device("a", active: false)]))
        let decoded = try JSONDecoder().decode(PresenceLog.self, from: JSONEncoder().encode(log))
        XCTAssertEqual(decoded, log)
    }
}

final class DemoPresenceTests: XCTestCase {
    func testDemoLogHasEventsAndTheNewDevice() {
        let log = DemoHousehold.presenceLog()
        XCTAssertFalse(log.events.isEmpty)
        let newID = DemoHousehold.newDeviceIDs.first!
        XCTAssertEqual(log.events(for: newID).first?.kind, .joined)
    }
}
