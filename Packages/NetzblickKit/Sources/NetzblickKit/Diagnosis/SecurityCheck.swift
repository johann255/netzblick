import Foundation

/// One line of the security checklist: what was looked at and how it came out.
public struct SecurityCheckItem: Identifiable, Hashable, Sendable {
    public enum State: String, Hashable, Sendable {
        case ok, warn, unknown
    }

    public var id: String
    public var title: String
    /// Short result in plain German, e.g. "WPA2 + WPA3" or "2 Freigaben".
    public var detail: String
    public var state: State

    public init(id: String, title: String, detail: String, state: State) {
        self.id = id
        self.title = title
        self.detail = detail
        self.state = state
    }
}

/// Builds the checklist shown on the security screen. Findings explain the problems;
/// this list also shows what was checked and found fine, like Fing's router check.
public enum SecurityCheck {
    public static func items(for s: HouseholdSnapshot, newDeviceCount: Int = 0) -> [SecurityCheckItem] {
        var items: [SecurityCheckItem] = []
        let security = s.security

        // Wi-Fi encryption of the home network (guest network is not judged).
        let home = (security?.wlans ?? []).filter { $0.isEnabled && !$0.isGuest }
        if home.isEmpty {
            items.append(.init(id: "wifi", title: "WLAN-Verschlüsselung", detail: "nicht lesbar", state: .unknown))
        } else {
            let worst = home.min { rank($0.encryption) < rank($1.encryption) }!.encryption
            let state: SecurityCheckItem.State = worst == .unknown ? .unknown : (worst.isModern ? .ok : .warn)
            items.append(.init(id: "wifi", title: "WLAN-Verschlüsselung", detail: worst.label, state: state))
        }

        switch security?.wpsPinEnabled {
        case .some(true): items.append(.init(id: "wps", title: "WPS-PIN", detail: "an", state: .warn))
        case .some(false): items.append(.init(id: "wps", title: "WPS-PIN", detail: "aus", state: .ok))
        case .none: break // many boxes do not report it; no line rather than a permanent "unknown"
        }

        if let forwardings = security?.portForwardings {
            let active = forwardings.filter(\.isEnabled).count
            items.append(.init(id: "ports", title: "Portfreigaben",
                               detail: active == 0 ? "keine" : (active == 1 ? "1 Freigabe" : "\(active) Freigaben"),
                               state: active == 0 ? .ok : .warn))
        } else {
            items.append(.init(id: "ports", title: "Portfreigaben", detail: "nicht lesbar", state: .unknown))
        }

        if let remote = security?.remoteAccess {
            let detail: String
            switch (remote.httpsEnabled, remote.myFritzEnabled) {
            case (true, _): detail = "HTTPS an" + (remote.httpsPort.map { ", Port \($0)" } ?? "")
            case (false, true): detail = "nur über MyFRITZ!"
            case (false, false): detail = "aus"
            }
            items.append(.init(id: "remote", title: "Fernzugriff auf die Box", detail: detail,
                               state: remote.httpsEnabled ? .warn : .ok))
        } else {
            items.append(.init(id: "remote", title: "Fernzugriff auf die Box", detail: "nicht lesbar", state: .unknown))
        }

        items.append(.init(id: "firmware", title: "FRITZ!OS",
                           detail: s.box.updateAvailable ? "Update verfügbar" : (s.box.firmwareVersion.map { "aktuell (\($0))" } ?? "aktuell"),
                           state: s.box.updateAvailable ? .warn : .ok))

        items.append(.init(id: "new-devices", title: "Unbekannte Geräte",
                           detail: newDeviceCount == 0 ? "keine neuen" : (newDeviceCount == 1 ? "1 neues Gerät" : "\(newDeviceCount) neue Geräte"),
                           state: newDeviceCount == 0 ? .ok : .warn))
        return items
    }

    /// Lower is worse.
    private static func rank(_ e: WiFiEncryption) -> Int {
        switch e {
        case .open: return 0
        case .wep: return 1
        case .wpaLegacy: return 2
        case .unknown: return 3
        case .wpa2: return 4
        case .wpa2wpa3: return 5
        case .wpa3: return 6
        }
    }
}
