import Foundation

/// Turns a snapshot into a ranked list of plain-language findings.
/// Every rule is a pure function, so each one is unit-tested on its own.
public struct DiagnosisEngine: Sendable {
    /// Signal (percent) below which a 2.4 GHz device counts as stuck in the slow band.
    public var slowBandSignalThreshold = 40
    /// Signal (percent) below which any Wi-Fi link counts as weak.
    public var weakSignalThreshold = 30

    public init() {}

    public func findings(for snapshot: HouseholdSnapshot, phoneSpeedMbps: Double? = nil) -> [Finding] {
        var result: [Finding] = []
        result += internetDown(snapshot)
        result += slowBand(snapshot)
        result += weakSignal(snapshot)
        result += wifiBottleneck(snapshot, phoneSpeedMbps: phoneSpeedMbps)
        result += firmwareUpdate(snapshot)
        result += wifiEncryption(snapshot)
        result += wps(snapshot)
        result += portForwardings(snapshot)
        result += remoteAccess(snapshot)
        return result.sorted { ($0.severity, $0.title) < ($1.severity, $1.title) }
    }

    // MARK: Rules

    func internetDown(_ s: HouseholdSnapshot) -> [Finding] {
        guard let wan = s.wan, !wan.isUp else { return [] }
        return [Finding(
            id: "internet-down",
            kind: .internetDown,
            severity: .high,
            title: "Die Internetleitung ist getrennt",
            explanation: "Die FRITZ!Box hat gerade keine Verbindung ins Internet. Das Heimnetz selbst funktioniert weiter.",
            scope: "ganzer Haushalt",
            howTo: [
                "Warte zwei Minuten, oft verbindet sich die Box von selbst neu.",
                "Prüfe, ob das Kabel zur Telefon- oder Glasfaserdose fest steckt.",
                "Hilft das nicht: Störung beim Anbieter melden."
            ]
        )]
    }

    func slowBand(_ s: HouseholdSnapshot) -> [Finding] {
        guard s.hasFastRadio else { return [] }
        let stuck = s.devices.filter { d in
            guard d.isActive, !d.isGuest, let w = d.wifi, w.band == .ghz24, let signal = w.signalPercent else { return false }
            // Smart-home gadgets often only speak 2.4 GHz; only flag phones, tablets and computers.
            return signal < slowBandSignalThreshold && [.phoneTablet, .computer].contains(d.category)
        }
        return stuck.map { d in
            Finding(
                id: "slow-band-\(d.id)",
                kind: .slowBand,
                severity: .high,
                title: "\(d.name) hängt im langsamen Band",
                explanation: "Es nutzt 2,4 GHz mit schwachem Signal. Die FRITZ!Box kann solche Geräte automatisch ins schnellere 5-GHz-Band leiten.",
                scope: "1 Gerät",
                deviceIDs: [d.id],
                howTo: [
                    "Öffne fritz.box im Browser und melde dich an.",
                    "Gehe zu WLAN → Funkkanal (bei Mesh: WLAN → Mesh).",
                    "Schalte die Band-Steuerung ein (je nach Version „Band Steering“ oder „WLAN-Bänder automatisch wählen“).",
                    "Verbinde \(d.name) einmal neu mit dem WLAN."
                ]
            )
        }
    }

    func weakSignal(_ s: HouseholdSnapshot) -> [Finding] {
        let weak = s.devices.filter { d in
            guard d.isActive, !d.isGuest, let signal = d.wifi?.signalPercent else { return false }
            let alreadySlowBand = d.wifi?.band == .ghz24 && signal < slowBandSignalThreshold && [.phoneTablet, .computer].contains(d.category) && s.hasFastRadio
            return signal < weakSignalThreshold && !alreadySlowBand
        }
        guard !weak.isEmpty else { return [] }

        // A weak repeater drags down everything behind it: report it on its own.
        if let repeater = weak.first(where: { $0.category == .network }) {
            return [Finding(
                id: "weak-repeater-\(repeater.id)",
                kind: .weakSignal,
                severity: .medium,
                title: "\(repeater.name) steht ungünstig",
                explanation: "Der Repeater empfängt die FRITZ!Box selbst nur schwach und gibt das an alle Geräte weiter. Ein, zwei Meter näher zur Box helfen oft schon.",
                scope: "Geräte hinter dem Repeater",
                deviceIDs: [repeater.id],
                howTo: [
                    "Stelle den Repeater etwa auf halbe Strecke zwischen Box und Funkloch.",
                    "Meide Schränke, Heizkörper und Spiegel direkt daneben.",
                    "Prüfe danach hier erneut: Ziel ist mindestens mittleres Signal."
                ]
            )]
        }
        let names = weak.prefix(3).map(\.name).joined(separator: ", ")
        return [Finding(
            id: "weak-signal",
            kind: .weakSignal,
            severity: .medium,
            title: weak.count == 1 ? "\(names) hat schwaches WLAN" : "\(weak.count) Geräte haben schwaches WLAN",
            explanation: weak.count == 1
                ? "Das Gerät ist weit von der FRITZ!Box entfernt oder durch Wände abgeschirmt."
                : "Betroffen sind unter anderem \(names). Sie sind weit von der Box entfernt oder abgeschirmt.",
            scope: weak.count == 1 ? "1 Gerät" : "\(weak.count) Geräte",
            deviceIDs: weak.map(\.id),
            howTo: [
                "Stelle die FRITZ!Box frei und erhöht auf, nicht in einen Schrank.",
                "Für entfernte Räume hilft ein Repeater oder ein Mesh-Gerät."
            ]
        )]
    }

    func wifiBottleneck(_ s: HouseholdSnapshot, phoneSpeedMbps: Double?) -> [Finding] {
        guard let phone = phoneSpeedMbps,
              case let .wifiIsLimit(line, measured) = BottleneckVerdict.judge(phoneMbps: phone, lineMaxMbps: s.wan?.maxDownstreamMbps)
        else { return [] }
        return [Finding(
            id: "wifi-bottleneck",
            kind: .wifiBottleneck,
            severity: .medium,
            title: "Das WLAN bremst, nicht die Leitung",
            explanation: "Die Leitung schafft \(Int(line)) Mbit/s, am iPhone kommen nur \(Int(measured)) an.",
            scope: "dieses iPhone",
            howTo: [
                "Miss noch einmal näher an der FRITZ!Box.",
                "Ist es dort schneller, liegt es an der Entfernung: Repeater oder Mesh helfen."
            ]
        )]
    }

    func firmwareUpdate(_ s: HouseholdSnapshot) -> [Finding] {
        guard s.box.updateAvailable else { return [] }
        return [Finding(
            id: "firmware-update",
            kind: .firmwareUpdate,
            severity: .medium,
            title: "Update für die FRITZ!Box",
            explanation: "Eine neue FRITZ!OS-Version ist verfügbar. Updates schließen Sicherheitslücken. Während des Updates ist das Internet einige Minuten weg.",
            scope: "FRITZ!Box",
            howTo: [
                "Öffne fritz.box im Browser und melde dich an.",
                "Gehe zu System → Update.",
                "Starte das Update, wenn gerade niemand telefoniert oder streamt."
            ]
        )]
    }
}

// MARK: - Security rules

extension DiagnosisEngine {
    func wifiEncryption(_ s: HouseholdSnapshot) -> [Finding] {
        let home = (s.security?.wlans ?? []).filter { $0.isEnabled && !$0.isGuest }
        let weak = home.filter { [WiFiEncryption.open, .wep, .wpaLegacy].contains($0.encryption) }
        guard !weak.isEmpty else { return [] }
        let isOpen = weak.contains { $0.encryption == .open || $0.encryption == .wep }
        let name = weak.first?.ssid.map { "„\($0)“" } ?? "Dein WLAN"
        return [Finding(
            id: "wifi-encryption",
            kind: .wifiEncryption,
            severity: isOpen ? .high : .medium,
            title: isOpen ? "\(name) ist offen" : "\(name) nutzt eine veraltete Verschlüsselung",
            explanation: isOpen
                ? "Wer in der Nähe ist, kann sich ohne Passwort verbinden und mitlesen, was nicht zusätzlich verschlüsselt ist."
                : "Das alte WPA lässt sich knacken. WPA2 und WPA3 funktionieren mit allen Geräten der letzten zehn Jahre.",
            scope: "ganzes WLAN",
            howTo: [
                "Öffne fritz.box im Browser und melde dich an.",
                "Gehe zu WLAN → Sicherheit → Verschlüsselung.",
                "Wähle „WPA2 + WPA3“ und vergib ein langes Passwort.",
                "Verbinde danach alle Geräte einmal neu mit dem WLAN."
            ]
        )]
    }

    func wps(_ s: HouseholdSnapshot) -> [Finding] {
        guard s.security?.wpsPinEnabled == true else { return [] }
        return [Finding(
            id: "wps-pin",
            kind: .wps,
            severity: .medium,
            title: "WPS mit PIN ist eingeschaltet",
            explanation: "Über die WPS-PIN kann sich ein Gerät ohne WLAN-Passwort anmelden. Die PIN lässt sich in Stunden erraten.",
            scope: "ganzes WLAN",
            howTo: [
                "Öffne fritz.box im Browser und melde dich an.",
                "Gehe zu WLAN → Sicherheit → WPS-Schnellverbindung.",
                "Schalte das PIN-Verfahren aus. Die Taste an der Box (Push-Button) kannst du behalten."
            ]
        )]
    }

    func portForwardings(_ s: HouseholdSnapshot) -> [Finding] {
        let open = s.security?.activeForwardings ?? []
        guard !open.isEmpty else { return [] }
        let byClient = Dictionary(grouping: open, by: \.internalClient)
        let devices = byClient.keys.compactMap { s.device(ip: $0) }
        let names = byClient.keys.sorted().map { ip in s.device(ip: ip)?.name ?? ip }
        let ports = open.map { "\($0.externalPort)/\($0.transport.rawValue)" }.sorted().prefix(4).joined(separator: ", ")
        let subject = byClient.count == 1 ? "\(names[0]) ist" : "\(byClient.count) Geräte sind"
        return [Finding(
            id: "port-forwarding",
            kind: .portForwarding,
            severity: .medium,
            title: "\(subject) aus dem Internet erreichbar",
            explanation: "Die FRITZ!Box leitet Anfragen aus dem Internet weiter (Port \(ports)). "
                + "Das braucht es etwa für Spielkonsolen oder einen eigenen Server. Kennst du die Freigabe nicht, schalte sie ab.",
            scope: byClient.count == 1 ? "1 Gerät" : "\(byClient.count) Geräte",
            deviceIDs: devices.map(\.id),
            howTo: [
                "Öffne fritz.box im Browser und melde dich an.",
                "Gehe zu Internet → Freigaben → Portfreigaben.",
                "Entferne Freigaben, die du nicht kennst. Bei Geräten mit „Selbstständige Portfreigaben“ kannst du das Häkchen abwählen."
            ]
        )]
    }

    func remoteAccess(_ s: HouseholdSnapshot) -> [Finding] {
        guard let remote = s.security?.remoteAccess, remote.httpsEnabled else { return [] }
        return [Finding(
            id: "remote-access",
            kind: .remoteAccess,
            severity: .info,
            title: "Die FRITZ!Box ist aus dem Internet erreichbar",
            explanation: "Der Fernzugriff über HTTPS ist an. Mit einem starken Passwort ist das in Ordnung. Nutzt du ihn nicht, ist aus besser.",
            scope: "FRITZ!Box",
            howTo: [
                "Öffne fritz.box im Browser und melde dich an.",
                "Gehe zu Internet → Freigaben → FRITZ!Box-Dienste.",
                "Nimm das Häkchen bei „Internetzugriff auf die FRITZ!Box über HTTPS“ heraus, wenn du ihn nicht brauchst."
            ]
        )]
    }
}

/// Remembers which devices the user has already seen, to spot new ones.
public struct NewDeviceDetector: Sendable {
    public init() {}

    /// Ids in `snapshot` that are not in `known`. Guests and randomised MACs of known names are ignored.
    public func newDeviceIDs(in snapshot: HouseholdSnapshot, known: Set<String>) -> Set<String> {
        guard !known.isEmpty else { return [] } // first run: everything is "known"
        return Set(snapshot.devices.filter { !$0.isGuest && !known.contains($0.id) }.map(\.id))
    }
}
