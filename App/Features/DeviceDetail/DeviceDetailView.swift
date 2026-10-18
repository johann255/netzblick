import SwiftUI
import NetzblickKit

/// One device: facts from the FRITZ!Box, the "new device" acknowledgement and related findings.
struct DeviceDetailView: View {
    let deviceID: String

    @Environment(AppModel.self) private var model

    private var device: Device? {
        model.device(id: deviceID)
    }

    var body: some View {
        NBScreen {
            header
        } content: {
            if let device {
                facts(device)

                if model.newDeviceIDs.contains(device.id) {
                    newCard(device)
                }

                let related = relatedFindings(for: device)
                if !related.isEmpty {
                    findingsSection(related)
                }

                privacyCard
            } else {
                Text("Gerät nicht mehr im Netz.")
                    .font(.nbSans(16))
                    .foregroundStyle(Color.nbMuted)
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Header

    @ViewBuilder
    private var header: some View {
        if let device {
            NBBlueHeader(
                title: device.name,
                subtitle: device.category.title + " · " + device.connectionSummary
            )
        } else {
            NBBlueHeader(title: "Gerät")
        }
    }

    // MARK: - Steckbrief

    private func facts(_ device: Device) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NBSectionTitle("Steckbrief")

            NBCard {
                VStack(spacing: 0) {
                    factRow("Status", value: device.isActive ? "Online" : "Schläft gerade")
                    NBRowDivider()
                    factRow("Verbindung", value: connectionText(device.connection))

                    if let link = device.wifi {
                        NBRowDivider()
                        factRow("Signal", value: signalText(link))

                        if let rate = link.rateMbps {
                            NBRowDivider()
                            factRow("Tempo der Verbindung", value: "\(rate) Mbit/s")
                        }
                    }

                    NBRowDivider()
                    factRow("Hersteller", value: device.vendor ?? "unbekannt")
                    NBRowDivider()
                    factRow("IP-Adresse", value: device.ipAddress ?? "unbekannt")
                    NBRowDivider()
                    factRow("MAC-Adresse", value: device.macAddress ?? "unbekannt", note: macNote(device))
                }
            }
        }
    }

    private func factRow(_ label: String, value: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(label)
                    .font(.nbSans(15))
                    .foregroundStyle(Color.nbInk)
                Spacer(minLength: 8)
                Text(value)
                    .font(.nbSans(14))
                    .foregroundStyle(Color.nbMuted)
                    .multilineTextAlignment(.trailing)
            }

            if let note {
                Text(note)
                    .font(.nbSans(12))
                    .foregroundStyle(Color.nbMuted)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func connectionText(_ connection: Connection) -> String {
        switch connection {
        case .ethernet: return "Kabel (LAN)"
        case let .wifi(link): return "WLAN \(link.band.label)"
        case .unknown: return "unbekannt"
        }
    }

    private func signalText(_ link: WiFiLink) -> String {
        guard let percent = link.signalPercent else { return link.quality.label }
        return "\(percent) % · \(link.quality.label)"
    }

    private func macNote(_ device: Device) -> String? {
        guard let mac = device.macAddress, DeviceClassifier.isRandomized(mac: mac) else { return nil }
        return "Private Adresse: Das Gerät verbirgt seinen Hersteller. Bei Handys ist das normal."
    }

    // MARK: - Neu im Netz

    private func newCard(_ device: Device) -> some View {
        NBCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Neu im Netz")
                    .font(.nbSerif(26))
                    .foregroundStyle(Color.nbInk)

                Text("Dieses Gerät war bisher nicht bekannt. Kennst du es?")
                    .font(.nbSans(14))
                    .foregroundStyle(Color.nbInkSoft)

                Button {
                    model.acknowledge(deviceID: device.id)
                } label: {
                    Text("Kenne ich")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NBPrimaryButtonStyle())
            }
            .padding(16)
        }
    }

    // MARK: - Hinweise

    private func relatedFindings(for device: Device) -> [Finding] {
        model.findings.filter { $0.deviceIDs.contains(device.id) }
    }

    private func findingsSection(_ findings: [Finding]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            NBSectionTitle("Hinweise")

            NBCard {
                VStack(spacing: 0) {
                    ForEach(Array(findings.enumerated()), id: \.element.id) { index, finding in
                        if index > 0 {
                            NBRowDivider()
                        }
                        NavigationLink {
                            FindingDetailView(finding: finding)
                        } label: {
                            NBRow(
                                symbol: "exclamationmark.circle",
                                title: finding.title,
                                subtitle: finding.scope
                            ) {
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(Color.nbMuted)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: - Privatsphäre (Platzhalter)

    private var privacyCard: some View {
        NBCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Für deine Privatsphäre")
                    .font(.nbSerif(26))
                    .foregroundStyle(Color.nbInk)

                Text("Bald: Vorschläge, welche Verbindungen dieses Geräts du sperren kannst – lokal aus Geräteprofilen in der App.")
                    .font(.nbSans(14))
                    .foregroundStyle(Color.nbInkSoft)

                NBChip("ab Version 1.1", style: .tip)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    NavigationStack {
        DeviceDetailView(deviceID: "preview")
    }
    .environment(AppModel())
}
