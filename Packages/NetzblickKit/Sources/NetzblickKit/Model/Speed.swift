import Foundation

/// Traffic-light rating of a measured internet speed.
public enum SpeedLevel: String, Codable, Sendable {
    case slow   // rot
    case ok     // gelb
    case fast   // grün

    public var label: String {
        switch self {
        case .slow: return "langsam"
        case .ok: return "okay"
        case .fast: return "schnell"
        }
    }
}

/// Rates a download speed in Mbit/s.
///
/// Reference values:
/// - Tariff known: green from 90 % of the booked maximum (the Bundesnetzagentur's
///   threshold for "Minderleistung"), yellow 50–90 %, red below 50 %.
/// - Tariff unknown: red below 15 Mbit/s (the statutory minimum supply in Germany),
///   yellow 15–50 Mbit/s, green from 50 Mbit/s.
public struct SpeedRating: Hashable, Sendable {
    public var level: SpeedLevel
    /// One plain sentence explaining the colour.
    public var explanation: String

    public static let minimumSupplyMbps = 15.0
    public static let comfortableMbps = 50.0

    public static func rate(downloadMbps: Double, bookedMbps: Double?) -> SpeedRating {
        if let booked = bookedMbps, booked > 0 {
            let share = downloadMbps / booked
            let percent = Int((share * 100).rounded())
            switch share {
            case 0.9...:
                return SpeedRating(level: .fast, explanation: "\(percent) % deines Tarifs – das ist, was du bezahlst.")
            case 0.5..<0.9:
                return SpeedRating(level: .ok, explanation: "\(percent) % deines Tarifs. Spürbar weniger als gebucht.")
            default:
                return SpeedRating(level: .slow, explanation: "Nur \(percent) % deines Tarifs. Das ist deutlich zu wenig.")
            }
        }
        switch downloadMbps {
        case comfortableMbps...:
            return SpeedRating(level: .fast, explanation: "Reicht für mehrere 4K-Streams und Videocalls gleichzeitig.")
        case minimumSupplyMbps..<comfortableMbps:
            return SpeedRating(level: .ok, explanation: "Reicht für HD-Streaming. Mehrere 4K-Streams werden knapp.")
        default:
            return SpeedRating(level: .slow, explanation: "Unter der gesetzlichen Mindestversorgung von 15 Mbit/s.")
        }
    }
}

/// Compares what the iPhone measured with what the FRITZ!Box line can carry.
public enum BottleneckVerdict: Equatable, Sendable {
    /// The phone gets close to the line rate: Wi-Fi is fine.
    case lineIsLimit
    /// The line is much faster than what reaches the phone: Wi-Fi slows things down.
    case wifiIsLimit(lineMbps: Double, phoneMbps: Double)
    /// Not enough data to tell.
    case unknown

    /// The phone result below this share of the line rate counts as a Wi-Fi bottleneck.
    public static let wifiThreshold = 0.6

    public static func judge(phoneMbps: Double, lineMaxMbps: Double?) -> BottleneckVerdict {
        guard let line = lineMaxMbps, line > 0 else { return .unknown }
        if phoneMbps < line * wifiThreshold {
            return .wifiIsLimit(lineMbps: line, phoneMbps: phoneMbps)
        }
        return .lineIsLimit
    }

    public var sentence: String? {
        switch self {
        case .lineIsLimit:
            return "Am iPhone kommt fast alles an, was die Leitung liefert. Das WLAN bremst nicht."
        case let .wifiIsLimit(line, phone):
            return "Die Leitung schafft \(Int(line)) Mbit/s, am iPhone kommen nur \(Int(phone)) an. Das WLAN bremst, nicht die Leitung."
        case .unknown:
            return nil
        }
    }
}
