import Foundation

/// One change in a device's state, derived by comparing two readings.
public struct PresenceEvent: Hashable, Codable, Sendable {
    public enum Kind: String, Codable, Sendable {
        /// The device showed up for the first time since the log started.
        case joined
        case online
        case offline
    }

    public var deviceID: String
    public var kind: Kind
    /// Time of the reading that noticed the change. The real change happened at most one reading interval earlier.
    public var at: Date

    public init(deviceID: String, kind: Kind, at: Date) {
        self.deviceID = deviceID
        self.kind = kind
        self.at = at
    }

    /// Row title in the device history.
    public var title: String {
        switch kind {
        case .joined: return "Zum ersten Mal gesehen"
        case .online: return "Online"
        case .offline: return "Offline"
        }
    }
}

/// Local history of who was online when, built from every reading (Fing's "network events"
/// and "digital presence" without a cloud). Guest devices are never recorded.
public struct PresenceLog: Hashable, Codable, Sendable {
    public static let retention: TimeInterval = 30 * 24 * 3600
    static let maxEvents = 5000

    public private(set) var events: [PresenceEvent] = []
    /// Last known online state per device id.
    public private(set) var lastActive: [String: Bool] = [:]
    /// Last reading in which the device was online.
    public private(set) var lastSeen: [String: Date] = [:]
    /// Time of the first reading; until then there is no baseline.
    public private(set) var startedAt: Date?

    public init() {}

    /// Folds a reading into the log and returns the events it produced.
    @discardableResult
    public mutating func record(_ snapshot: HouseholdSnapshot) -> [PresenceEvent] {
        let now = snapshot.takenAt
        let home = snapshot.devices.filter { !$0.isGuest }
        let isBaseline = startedAt == nil
        if isBaseline { startedAt = now }

        var produced: [PresenceEvent] = []
        var seenIDs = Set<String>()
        for device in home {
            seenIDs.insert(device.id)
            let previous = lastActive[device.id]
            if device.isActive { lastSeen[device.id] = now }
            lastActive[device.id] = device.isActive
            guard !isBaseline else { continue }
            switch previous {
            case nil:
                produced.append(PresenceEvent(deviceID: device.id, kind: .joined, at: now))
            case let was? where was != device.isActive:
                produced.append(PresenceEvent(deviceID: device.id, kind: device.isActive ? .online : .offline, at: now))
            default:
                break
            }
        }
        // A device the router no longer lists counts as offline.
        for (id, wasActive) in lastActive where wasActive && !seenIDs.contains(id) {
            lastActive[id] = false
            produced.append(PresenceEvent(deviceID: id, kind: .offline, at: now))
        }

        events.append(contentsOf: produced)
        prune(now: now)
        return produced
    }

    /// Newest first.
    public func events(for deviceID: String, limit: Int = 20) -> [PresenceEvent] {
        Array(events.lazy.reversed().filter { $0.deviceID == deviceID }.prefix(limit))
    }

    /// Newest first, across all devices.
    public func recentEvents(limit: Int = 50) -> [PresenceEvent] {
        Array(events.suffix(limit).reversed())
    }

    /// Hours of the day (0–23) in which the device was online at least once within the log.
    /// Used for the "when is it usually home" strip.
    public func onlineHours(for deviceID: String) -> Set<Int> {
        var hours = Set<Int>()
        let calendar = Calendar(identifier: .gregorian)
        // Walk the event list and mark every hour between an online event and the next offline one.
        var onlineSince: Date?
        for event in events where event.deviceID == deviceID {
            switch event.kind {
            case .joined, .online:
                if onlineSince == nil { onlineSince = event.at }
            case .offline:
                if let start = onlineSince {
                    hours.formUnion(Self.hours(from: start, to: event.at, calendar: calendar))
                    onlineSince = nil
                }
            }
        }
        return hours
    }

    static func hours(from start: Date, to end: Date, calendar: Calendar) -> Set<Int> {
        guard end > start else { return [calendar.component(.hour, from: start)] }
        var result = Set<Int>()
        var cursor = start
        while cursor <= end && result.count < 24 {
            result.insert(calendar.component(.hour, from: cursor))
            cursor = cursor.addingTimeInterval(3600)
        }
        result.insert(calendar.component(.hour, from: end))
        return result
    }

    /// Forgets everything about one device ("Gerät vergessen").
    public mutating func forget(deviceID: String) {
        events.removeAll { $0.deviceID == deviceID }
        lastActive[deviceID] = nil
        lastSeen[deviceID] = nil
    }

    private mutating func prune(now: Date) {
        let cutoff = now.addingTimeInterval(-Self.retention)
        if let first = events.first, first.at < cutoff {
            events.removeAll { $0.at < cutoff }
        }
        if events.count > Self.maxEvents {
            events.removeFirst(events.count - Self.maxEvents)
        }
        for (id, date) in lastSeen where date < cutoff && lastActive[id] != true {
            lastSeen[id] = nil
            lastActive[id] = nil
        }
    }
}
