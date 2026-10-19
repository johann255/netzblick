import Foundation

/// The three groups a contacted address falls into.
public enum DomainGroup: String, Codable, Sendable, CaseIterable {
    case normal
    case vendor
    case tracking

    public var label: String {
        switch self {
        case .normal: return "Normal"
        case .vendor: return "Hersteller"
        case .tracking: return "Werbung & Tracking"
        }
    }
}

/// Result of looking up one domain.
public struct DomainMatch: Hashable, Codable, Sendable {
    /// Shortened name shown to the user, e.g. "doubleclick.net".
    public var domain: String
    public var group: DomainGroup
    /// Company behind the domain, if the list knows it.
    public var owner: String?
}

/// Sorts domains into groups using the list shipped with the app (`domain-groups.json`, written by us).
public struct DomainGroups: Sendable {
    struct Entry: Decodable {
        var suffix: String
        var group: DomainGroup
        var owner: String?
    }

    struct File: Decodable {
        var ignore: [String]
        var entries: [Entry]
    }

    private let entries: [String: Entry]
    private let ignored: [String]

    init(file: File) {
        var map: [String: Entry] = [:]
        for entry in file.entries {
            // On a duplicate suffix the tracking entry wins.
            if let existing = map[entry.suffix], existing.group == .tracking { continue }
            map[entry.suffix] = entry
        }
        entries = map
        ignored = file.ignore
    }

    /// The list bundled with NetzblickKit.
    public static let bundled: DomainGroups = {
        guard let url = Bundle.module.url(forResource: "domain-groups", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data) else {
            return DomainGroups(file: File(ignore: [], entries: []))
        }
        return DomainGroups(file: file)
    }()

    /// True for names that never leave the home network (fritz.box, *.local, reverse lookups).
    public func isLocal(_ name: String) -> Bool {
        let name = name.lowercased()
        return !name.contains(".") || ignored.contains { name == $0 || name.hasSuffix("." + $0) }
    }

    /// Longest matching suffix decides; unknown names are `.normal`, shortened to their registrable part.
    public func match(_ name: String) -> DomainMatch {
        let labels = name.lowercased().split(separator: ".").map(String.init)
        for start in labels.indices {
            let suffix = labels[start...].joined(separator: ".")
            if let entry = entries[suffix] {
                return DomainMatch(domain: entry.suffix, group: entry.group, owner: entry.owner)
            }
        }
        return DomainMatch(domain: Self.registrable(labels), group: .normal, owner: nil)
    }

    /// "a.b.example.co.uk" → "example.co.uk", "cdn.example.com" → "example.com".
    static func registrable(_ labels: [String]) -> String {
        let twoPartSuffixes: Set<String> = ["co.uk", "org.uk", "com.au", "co.jp", "com.br", "co.at", "gv.at", "com.cn", "com.tr"]
        guard labels.count > 2 else { return labels.joined(separator: ".") }
        let lastTwo = labels.suffix(2).joined(separator: ".")
        let keep = twoPartSuffixes.contains(lastTwo) ? 3 : 2
        return labels.suffix(keep).joined(separator: ".")
    }
}
