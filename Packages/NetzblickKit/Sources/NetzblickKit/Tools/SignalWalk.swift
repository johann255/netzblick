import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Which storey a room is on, for the mini map. Derived from the room name.
public enum Floor: Int, Codable, Sendable, Comparable, CaseIterable {
    case basement = -1
    case ground = 0
    case upper = 1
    case attic = 2

    public static func < (lhs: Floor, rhs: Floor) -> Bool { lhs.rawValue < rhs.rawValue }

    public var title: String {
        switch self {
        case .basement: return "Keller"
        case .ground: return "Wohnung"
        case .upper: return "Obergeschoss"
        case .attic: return "Dachboden"
        }
    }

    public static func guess(for room: String) -> Floor {
        let name = room.lowercased()
        if name.contains("keller") || name.contains("waschküche") || name.contains("heizungsraum") { return .basement }
        if name.contains("dachboden") || name.contains("dach") || name.contains("speicher") { return .attic }
        if name.split(separator: " ").contains("og") || name.contains("obergeschoss") || name.contains("oben") { return .upper }
        return .ground
    }
}

/// One room noted during a walk. Tapping a room again adds a sample; the average smooths out wobble.
public struct SignalSpot: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var floor: Floor
    public var samples: [WiFiLink]

    public init(id: UUID = UUID(), name: String, floor: Floor? = nil, samples: [WiFiLink]) {
        self.id = id
        self.name = name
        self.floor = floor ?? Floor.guess(for: name)
        self.samples = samples
    }

    /// Average signal in percent over all samples that have one.
    public var signalPercent: Int? {
        let values = samples.compactMap(\.signalPercent)
        guard !values.isEmpty else { return nil }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }

    /// Average link rate in Mbit/s.
    public var rateMbps: Int? {
        let values = samples.compactMap(\.rateMbps)
        guard !values.isEmpty else { return nil }
        return Int((Double(values.reduce(0, +)) / Double(values.count)).rounded())
    }

    public var band: WiFiBand? { samples.last?.band }

    public var quality: SignalQuality {
        WiFiLink(band: band ?? .ghz5, signalPercent: signalPercent).quality
    }
}

/// Fing's "Wi-Fi sweet spot" without hardware: walk through the home with the iPhone, tap the room
/// you are in, and Netzblick builds a small map with a repeater recommendation.
public struct SignalWalk: Hashable, Codable, Sendable {
    /// Quick-pick buttons, in the order a home is usually walked.
    public static let suggestedRooms = [
        "Wohnzimmer", "Küche", "Büro", "Schlafzimmer", "Kinderzimmer", "Bad", "Flur",
        "Keller", "Dachboden", "Balkon", "Garten"
    ]
    /// Below this the room counts as a problem for video calls and streaming.
    static let weakBelow = 40
    /// A repeater needs at least this much signal from the box to pass on a good connection.
    static let repeaterNeeds = 55

    public private(set) var spots: [SignalSpot] = []

    public init(spots: [SignalSpot] = []) {
        self.spots = spots
    }

    /// Adds the current reading to the room; a new room is created on first use.
    public mutating func note(_ name: String, link: WiFiLink) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmed.isEmpty ? "Ort \(spots.count + 1)" : trimmed
        if let index = spots.firstIndex(where: { $0.name.caseInsensitiveCompare(label) == .orderedSame }) {
            spots[index].samples.append(link)
        } else {
            spots.append(SignalSpot(name: label, samples: [link]))
        }
    }

    public mutating func remove(id: UUID) {
        spots.removeAll { $0.id == id }
    }

    public mutating func reset() {
        spots = []
    }

    /// Strongest first; spots without a value last.
    public var ranked: [SignalSpot] {
        spots.sorted { ($0.signalPercent ?? -1) > ($1.signalPercent ?? -1) }
    }

    /// Rooms grouped by floor, top floor first, for the mini map.
    public var floors: [(floor: Floor, spots: [SignalSpot])] {
        Dictionary(grouping: spots, by: \.floor)
            .map { (floor: $0.key, spots: $0.value) }
            .sorted { $0.floor > $1.floor }
    }

    /// The room with the best signal; the box is most likely there or next door.
    public var boxRoom: SignalSpot? {
        ranked.first { $0.signalPercent != nil }
    }

    public var weakRooms: [SignalSpot] {
        ranked.filter { ($0.signalPercent ?? 100) < Self.weakBelow }.reversed()
    }

    /// Where to put a repeater: the room that still has good signal from the box and is closest
    /// (by storey, then by signal) to the weakest room. Nil if no room is weak or none is good enough.
    public var repeaterRoom: SignalSpot? {
        guard let worst = weakRooms.first else { return nil }
        let candidates = spots.filter { ($0.signalPercent ?? 0) >= Self.repeaterNeeds && $0.id != boxRoom?.id }
        // Same storey as the problem room first, then the nearest storey; among those the weakest
        // good room, because it is usually the one furthest from the box towards the problem.
        return candidates.min { a, b in
            let da = abs(a.floor.rawValue - worst.floor.rawValue)
            let db = abs(b.floor.rawValue - worst.floor.rawValue)
            if da != db { return da < db }
            return (a.signalPercent ?? 0) < (b.signalPercent ?? 0)
        }
    }

    /// Plain-German conclusion once at least two places are noted.
    public var verdict: String? {
        let measured = ranked.filter { $0.signalPercent != nil }
        guard measured.count >= 2, let best = measured.first else { return nil }
        guard let worst = weakRooms.first, let worstSignal = worst.signalPercent else {
            if measured.allSatisfy({ $0.quality == .strong }) {
                return "Überall starkes Signal. Ein Repeater bringt hier nichts."
            }
            return "Kein Raum ist richtig schwach. Am besten ist der Empfang im Raum „\(best.name)“."
        }
        if let spot = repeaterRoom, let signal = spot.signalPercent {
            return "Stell den Repeater in den Raum „\(spot.name)“. Dort kommt die FRITZ!Box noch gut an (\(signal) %), "
                + "und er ist näher am Raum „\(worst.name)“ (\(worstSignal) %)."
        }
        if worst.floor != best.floor {
            return "Der Raum „\(worst.name)“ liegt auf einem anderen Stockwerk und bekommt kaum WLAN. "
                + "Dort hilft ein Repeater mit Kabel: ein Powerline-Adapter oder ein Mesh-Repeater per LAN."
        }
        return "Der Raum „\(worst.name)“ bekommt kaum WLAN (\(worstSignal) %), und kein Raum dazwischen hat genug Empfang für einen Funk-Repeater. "
            + "Miss noch einen Raum auf halber Strecke, oder nimm einen Repeater mit Kabel."
    }
}

/// The iPhone's own IPv4 address on Wi-Fi (interface en0), to find itself in the router's list.
public enum LocalAddress {
    public static func wifiIPv4() -> String? {
        #if canImport(Darwin)
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let entry = pointer.pointee
            guard let address = entry.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  String(cString: entry.ifa_name) == "en0" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            return String(cString: host)
        }
        return nil
        #else
        return nil
        #endif
    }
}
