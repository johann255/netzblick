import SwiftUI
import NetzblickKit

/// One finding with its steps. Netzblick never changes the FRITZ!Box itself; the steps are for the user.
struct FindingDetailView: View {
    let finding: Finding

    @Environment(AppModel.self) private var model
    @Environment(\.nbAccent) private var accent

    private var affectedDevices: [Device] {
        finding.deviceIDs.compactMap { model.device(id: $0) }
    }

    var body: some View {
        NBScreen {
            NBBlueHeader(
                eyebrow: finding.severity.label.uppercased() + " · " + finding.scope,
                title: finding.title
            )
        } content: {
            NBCard {
                Text(finding.explanation)
                    .font(.nbSans(16))
                    .foregroundStyle(Color.nbInkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            }

            if !finding.howTo.isEmpty {
                NBSectionTitle("So stellst du es ein")
                stepsCard
            }

            linkCard

            if !affectedDevices.isEmpty {
                NBSectionTitle("Betroffene Geräte")
                affectedCard
            }
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Steps

    private var stepsCard: some View {
        NBCard {
            VStack(spacing: 0) {
                ForEach(Array(finding.howTo.enumerated()), id: \.offset) { index, step in
                    if index > 0 {
                        NBRowDivider()
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text("\(index + 1)")
                            .font(.nbSerif(28))
                            .foregroundStyle(accent)
                            .frame(minWidth: 28, alignment: .leading)
                        Text(step)
                            .font(.nbSans(15))
                            .foregroundStyle(Color.nbInk)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                }
            }
        }
    }

    // MARK: - FRITZ!Box link

    private var linkCard: some View {
        NBCard {
            VStack(alignment: .leading, spacing: 12) {
                Link(destination: URL(string: "http://fritz.box")!) {
                    Text("fritz.box öffnen")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(NBPrimaryButtonStyle())

                Text("Netzblick ändert selbst nichts an deiner FRITZ!Box. Menünamen können je nach FRITZ!OS-Version abweichen.")
                    .font(.nbSans(12))
                    .foregroundStyle(Color.nbMuted)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Affected devices

    private var affectedCard: some View {
        NBCard {
            VStack(spacing: 0) {
                ForEach(Array(affectedDevices.enumerated()), id: \.element.id) { index, device in
                    if index > 0 {
                        NBRowDivider()
                    }
                    NBRow(
                        symbol: device.category.symbolName,
                        title: device.name,
                        subtitle: device.connectionSummary
                    )
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        FindingDetailView(
            finding: Finding(
                id: "preview-slow-band",
                kind: .slowBand,
                severity: .high,
                title: "Das iPad hängt im langsamen Band",
                explanation: "Das iPad ist mit dem 2,4-GHz-Band verbunden. Dieses Band ist langsamer und reicht für Videos oft nicht.",
                scope: "1 Gerät",
                deviceIDs: [],
                howTo: [
                    "Öffne die Oberfläche der FRITZ!Box im Browser.",
                    "Wähle das WLAN-Gerät iPad aus der Geräteliste.",
                    "Verbinde es mit dem 5-GHz-Netz, falls es das unterstützt."
                ]
            )
        )
    }
    .environment(AppModel())
}
