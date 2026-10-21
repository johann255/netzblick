import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// One place in the home where the signal was noted during a walk.
public struct SignalSpot: Hashable, Codable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var link: WiFiLink

    public init(id: UUID = UUID(), name: String, link: WiFiLink) {
        self.id = id
        self.name = name
        self.link = link
    }
}

/// Fing's "Wi-Fi sweet spot" without hardware: walk through the home with the iPhone and note
/// the signal the FRITZ!Box reports for it in each room.
public struct SignalWalk: Hashable, Codable, Sendable {
    public private(set) var spots: [SignalSpot] = []

    public init(spots: [SignalSpot] = []) {
        self.spots = spots
    }

    public mutating func note(_ name: String, link: WiFiLink) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let label = trimmed.isEmpty ? "Ort \(spots.count + 1)" : trimmed
        // Noting the same room again replaces the old value.
        spots.removeAll { $0.name.caseInsensitiveCompare(label) == .orderedSame }
        spots.append(SignalSpot(name: label, link: link))
    }

    public mutating func remove(id: UUID) {
        spots.removeAll { $0.id == id }
    }

    /// Strongest first; spots without a value last.
    public var ranked: [SignalSpot] {
        spots.sorted { ($0.link.signalPercent ?? -1) > ($1.link.signalPercent ?? -1) }
    }

    /// Plain-German conclusion once at least two places are noted.
    public var verdict: String? {
        let ranked = ranked.filter { $0.link.signalPercent != nil }
        guard ranked.count >= 2, let best = ranked.first, let worst = ranked.last else { return nil }
        if worst.link.quality == .weak {
            return "Im Raum „\(worst.name)“ ist das WLAN schwach. Ein Repeater auf halber Strecke zwischen „\(best.name)“ und „\(worst.name)“ hilft am meisten."
        }
        if ranked.allSatisfy({ $0.link.quality == .strong }) {
            return "Überall starkes Signal. Am WLAN liegt es nicht."
        }
        return "Am besten ist der Empfang im Raum „\(best.name)“, am schwächsten im Raum „\(worst.name)“. Für Videocalls und Streaming eignet sich „\(best.name)“."
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
