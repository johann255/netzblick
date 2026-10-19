import Foundation

/// How often one device asked for one domain during a listening session.
public struct DomainCount: Hashable, Codable, Sendable, Identifiable {
    public var match: DomainMatch
    public var count: Int
    public var id: String { match.domain }
}

/// Everything one device asked for during a session.
public struct DeviceListen: Hashable, Codable, Sendable, Identifiable {
    /// `Device.id` when the device is known, otherwise "ip:<address>".
    public var deviceID: String
    public var domains: [DomainCount]
    public var id: String { deviceID }

    public var total: Int { domains.reduce(0) { $0 + $1.count } }

    public func count(_ group: DomainGroup) -> Int {
        domains.filter { $0.match.group == group }.reduce(0) { $0 + $1.count }
    }

    public func share(_ group: DomainGroup) -> Double {
        total == 0 ? 0 : Double(count(group)) / Double(total)
    }
}

/// Result of one listening session. Only counts are kept, never packets.
public struct ListenReport: Hashable, Codable, Sendable {
    public var startedAt: Date
    public var endedAt: Date
    /// Sorted by number of requests, busiest device first.
    public var devices: [DeviceListen]

    public var total: Int { devices.reduce(0) { $0 + $1.total } }

    public func count(_ group: DomainGroup) -> Int {
        devices.reduce(0) { $0 + $1.count(group) }
    }

    /// Share of all requests in a group (0–1); 0 when nothing was heard.
    public func share(_ group: DomainGroup) -> Double {
        total == 0 ? 0 : Double(count(group)) / Double(total)
    }

    public func device(_ id: String) -> DeviceListen? {
        devices.first { $0.deviceID == id }
    }
}

/// Collects DNS questions into a `ListenReport`.
public struct ListenRecorder: Sendable {
    private let groups: DomainGroups
    private let macToDevice: [String: String]
    private let ipToDevice: [String: String]
    private let guestIDs: Set<String>
    private var counts: [String: [String: (DomainMatch, Int)]] = [:]
    public let startedAt: Date
    public private(set) var lastQueryAt: Date?

    /// `devices` maps MAC/IP of each question to a known device; guest devices are skipped.
    public init(devices: [Device], groups: DomainGroups = .bundled, startedAt: Date = Date()) {
        self.groups = groups
        self.startedAt = startedAt
        var macs: [String: String] = [:]
        var ips: [String: String] = [:]
        for device in devices {
            if let mac = device.macAddress { macs[mac.uppercased()] = device.id }
            if let ip = device.ipAddress { ips[ip] = device.id }
        }
        macToDevice = macs
        ipToDevice = ips
        guestIDs = Set(devices.filter(\.isGuest).map(\.id))
    }

    /// Adds one question. Local names and guest devices are ignored. Returns true if it was counted.
    @discardableResult
    public mutating func record(_ query: DNSQuery) -> Bool {
        guard !groups.isLocal(query.name) else { return false }
        let deviceID = query.sourceMAC.flatMap { macToDevice[$0] }
            ?? ipToDevice[query.sourceIP]
            ?? "ip:\(query.sourceIP)"
        guard !guestIDs.contains(deviceID) else { return false }
        let match = groups.match(query.name)
        var perDevice = counts[deviceID, default: [:]]
        let current = perDevice[match.domain]?.1 ?? 0
        perDevice[match.domain] = (match, current + 1)
        counts[deviceID] = perDevice
        lastQueryAt = query.timestamp
        return true
    }

    public var heardCount: Int {
        counts.values.reduce(0) { $0 + $1.values.reduce(0) { $0 + $1.1 } }
    }

    public func report(endedAt: Date = Date()) -> ListenReport {
        let devices = counts.map { id, domains in
            DeviceListen(
                deviceID: id,
                domains: domains.values
                    .map { DomainCount(match: $0.0, count: $0.1) }
                    .sorted { ($0.count, $1.match.domain) > ($1.count, $0.match.domain) }
            )
        }
        .sorted { ($0.total, $1.deviceID) > ($1.total, $0.deviceID) }
        return ListenReport(startedAt: startedAt, endedAt: endedAt, devices: devices)
    }
}
