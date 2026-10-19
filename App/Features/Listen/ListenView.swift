import SwiftUI
import NetzblickKit

/// Lauschmodus: start a session, watch it count, then see who talks to whom.
struct ListenView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        NBScreen {
            NBBlueHeader(
                eyebrow: eyebrow,
                title: "Wer funkt",
                italicTail: "nach außen?",
                subtitle: "Welche Adressen deine Geräte im Internet anfragen."
            )
        } content: {
            if model.isListening {
                runningCard
            } else {
                startCard
            }

            if let error = model.listenError, !model.isListening {
                Text(error)
                    .font(.nbSans(15))
                    .foregroundStyle(Color.nbDanger)
                    .padding(.horizontal, 4)
            }

            if let report = model.listenReport {
                summaryCard(report)
                devicesSection(report)
            }

            Text("So entsteht das Bild: Netzblick liest über den Mitschnitt deiner FRITZ!Box nur die Namen der angefragten Adressen, keine Inhalte. Gespeichert wird nur die Zählung, auf diesem iPhone. Verschlüsselte Anfragen sind nicht sichtbar, die Zahlen sind also eine Untergrenze. Geräte im Gastnetz bleiben außen vor.")
                .font(.nbSans(13))
                .foregroundStyle(Color.nbMuted)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var eyebrow: String {
        if model.isListening { return "Lauschmodus · läuft" }
        if let report = model.listenReport { return "Lauschmodus · \(report.timeLabel)" }
        return "Lauschmodus"
    }

    // MARK: - Start / running

    private var startCard: some View {
        NBCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(model.listenReport == nil
                     ? "Netzblick hört 5 Minuten mit, welche Adressen deine Geräte anfragen. Lass die App so lange offen."
                     : "Noch eine Runde? Das neue Ergebnis ersetzt das alte.")
                    .font(.nbSans(15))
                    .foregroundStyle(Color.nbInkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    model.startListening()
                } label: {
                    Text("Lauschen starten").frame(maxWidth: .infinity)
                }
                .buttonStyle(NBPrimaryButtonStyle())
            }
            .padding(16)
        }
    }

    private var runningCard: some View {
        NBCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("\(model.listenHeard)")
                        .font(.nbSerif(56))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(Color.nbInk)
                    Text("Anfragen gehört")
                        .font(.nbSans(15))
                        .foregroundStyle(Color.nbMuted)
                }
                .animation(.default, value: model.listenHeard)

                if let endsAt = model.listenEndsAt {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        let left = max(Int(endsAt.timeIntervalSince(context.date).rounded()), 0)
                        VStack(alignment: .leading, spacing: 8) {
                            ProgressView(value: Double(300 - min(left, 300)), total: 300)
                            Text("noch \(left / 60):\(String(format: "%02d", left % 60)) · lass die App offen")
                                .font(.nbSans(13))
                                .monospacedDigit()
                                .foregroundStyle(Color.nbMuted)
                        }
                    }
                }

                Button {
                    model.stopListening()
                } label: {
                    Text("Jetzt beenden").frame(maxWidth: .infinity)
                }
                .buttonStyle(NBSecondaryButtonStyle())
            }
            .padding(16)
        }
    }

    // MARK: - Result

    private func summaryCard(_ report: ListenReport) -> some View {
        NBCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Anfragen ins Internet")
                        .font(.nbSans(14))
                        .foregroundStyle(Color.nbMuted)
                    Spacer()
                    Text(report.total.formatted(.number.locale(Locale(identifier: "de_DE"))))
                        .font(.nbSerif(34))
                        .foregroundStyle(Color.nbInk)
                }
                ListenShareBar(counts: report.groupCounts)
            }
            .padding(16)
        }
    }

    private func devicesSection(_ report: ListenReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NBSectionTitle("Geräte")
            NBCard {
                VStack(spacing: 0) {
                    ForEach(Array(report.devices.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 { NBRowDivider() }
                        NavigationLink {
                            DeviceDetailView(deviceID: entry.deviceID)
                        } label: {
                            deviceRow(entry)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private func deviceRow(_ entry: DeviceListen) -> some View {
        let tracking = Int((entry.share(.tracking) * 100).rounded())
        return NBRow(
            symbol: model.device(id: entry.deviceID)?.category.symbolName ?? "questionmark.circle",
            title: model.deviceName(id: entry.deviceID),
            subtitle: "\(entry.total) Anfragen · \(tracking) % Werbung & Tracking"
        ) {
            if tracking >= 30 {
                NBChip("Plaudert", style: .warn)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ListenView()
    }
    .environment(AppModel())
}
